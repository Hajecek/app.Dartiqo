import Foundation
import Combine

/// Napojí obrazovku zápasu na online zápas. Server drží šipky, telefon si z nich přehraje stejný `Match`
/// jako u lokální hry, takže tabule, ceremonie i statistiky vypadají stejně.
@MainActor
final class OnlineMatchLink: ObservableObject {
    /// Lokální hra. Nic neposílá a `MatchView` dál pracuje s rozehraným zápasem v `AppStore`.
    static let local = OnlineMatchLink()

    struct RemoteUpdate {
        var game: Match
        /// Kolo soupeře, které nový stav uzavřel. Bez něj přibyly jen šipky rozhozeného kola.
        var visit: Visit?
    }

    let isOnline: Bool
    let yourSlot: Int
    /// Veřejné id online zápasu. Pro bilanci dokončených zápasů.
    var publicMatchID: String { matchID }
    @Published private(set) var game: Match?
    /// Zvedne se, když na serveru přibyly šipky soupeře. Obrazovka si je vyzvedne přes `takeRemote()`.
    @Published private(set) var remoteToken = 0
    /// Zvedne se, když se telefon musel srovnat se serverem a rozjeté kolo na obrazovce už neplatí.
    @Published private(set) var resetToken = 0
    @Published var notice: String?

    private let session: OnlineSession?
    private let matchID: String
    private let matchKey = UUID()
    private let startedAt = Date()
    private var config: GameConfig
    private var players: [Player] = []
    private var photoPaths: [UUID: String] = [:]
    private var serverDarts: [Dart] = []
    private var pendingRemote: Match?
    private var outbox: [Dart] = []
    private var sending = false
    private var subscription: AnyCancellable?

    private init() {
        isOnline = false
        yourSlot = 0
        session = nil
        matchID = ""
        config = GameConfig()
    }

    init(session: OnlineSession, match: OnlineMatch, profileID: UUID?) {
        isOnline = true
        yourSlot = match.yourSlot ?? 0
        self.session = session
        matchID = match.id
        config = match.rules.config
        players = match.players.sorted { $0.slot < $1.slot }.map { player in
            let id = player.you ? (profileID ?? Self.uuid(player.id)) : Self.uuid(player.id)
            return Player(id: id, name: player.name)
        }
        for (player, online) in zip(players, match.players.sorted { $0.slot < $1.slot }) {
            photoPaths[player.id] = online.photo
        }
        if let darts = match.state.thrownDarts {
            serverDarts = darts
            game = settled(replay(darts))
        }
        subscription = session.$match
            .compactMap { $0 }
            .filter { [matchID] in $0.id == matchID }
            .sink { [weak self] next in
                Task { @MainActor in self?.ingest(next) }
            }
    }

    var yourTurn: Bool {
        guard isOnline, let game else { return false }
        return !game.finished && game.legWinner == nil && game.active == yourSlot
    }

    func isRemote(_ player: Int) -> Bool {
        isOnline && player != yourSlot
    }

    func photo(for playerID: UUID) -> Data? {
        session?.photo(photoPaths[playerID])
    }

    // MARK: Zápis z obrazovky

    /// Obrazovka chce zapsat nový stav. Projde stejný stav s jinými volbami, jedna nová šipka hráče na tahu,
    /// nebo šipky, které už potvrdil server. Vrácení šipek online nejde.
    func propose(_ next: Match?) {
        guard isOnline, let next, let current = game else { return }
        let before = Self.darts(of: current)
        let after = Self.darts(of: next)
        if after == before {
            config.options = next.config.options
            game = next
            return
        }
        if after == serverDarts, after.count > before.count {
            game = next
            return
        }
        if after.count == before.count + 1, Array(after.prefix(before.count)) == before, yourTurn, let dart = after.last {
            game = next
            outbox.append(dart)
            if !sending { Task { await drain() } }
            return
        }
        resetToken &+= 1
    }

    /// Šipky soupeře, které obrazovka ještě neukázala.
    func takeRemote() -> RemoteUpdate? {
        guard let next = pendingRemote, let current = game else { return nil }
        pendingRemote = nil
        let visit = next.visits.count > current.visits.count ? next.visits.last : nil
        return RemoteUpdate(game: next, visit: visit)
    }

    func abandon() async -> Bool {
        guard let session else { return true }
        return await session.abandon()
    }

    // MARK: Server

    private func ingest(_ match: OnlineMatch) {
        guard outbox.isEmpty, !sending, let darts = match.state.thrownDarts else { return }
        serverDarts = darts
        guard let current = game else {
            game = settled(replay(darts))
            return
        }
        let local = Self.darts(of: current)
        if darts == local { return }
        if darts.count > local.count, Array(darts.prefix(local.count)) == local,
           let next = extend(current, with: Array(darts.dropFirst(local.count))) {
            pendingRemote = next
            remoteToken &+= 1
            return
        }
        hardReset(to: darts)
    }

    private func drain() async {
        sending = true
        while !outbox.isEmpty {
            guard let session, let api = DartiqoAccount.shared.api, let seq = session.match?.seq else {
                await failSend("Přihlas se k účtu Dartiqo.")
                return
            }
            let dart = outbox.removeFirst()
            do {
                session.adopt(try await api.throwOnlineDart(matchID, seq: seq, dart: dart))
            } catch let failure as OnlineFailure {
                if let match = failure.match { session.adopt(match) }
                await failSend(failure.message)
                return
            } catch {
                await failSend(error.localizedDescription)
                return
            }
        }
        sending = false
        if let match = session?.match, match.id == matchID { ingest(match) }
    }

    /// Server šipku nepřijal, nebo odpověď nedorazila. Platí stav ze serveru.
    private func failSend(_ message: String) async {
        outbox.removeAll()
        notice = message
        await session?.refresh(matchID)
        sending = false
        if let darts = session?.match?.state.thrownDarts {
            serverDarts = darts
            hardReset(to: darts)
        }
    }

    private func hardReset(to darts: [Dart]) {
        pendingRemote = nil
        game = settled(replay(darts))
        resetToken &+= 1
    }

    // MARK: Přehrání šipek

    private func replay(_ darts: [Dart]) -> Match? {
        var fresh = Match(config: config, players: players, firstPlayer: 0)
        fresh.id = matchKey
        fresh.createdAt = startedAt
        return extend(fresh, with: darts)
    }

    private func extend(_ start: Match, with darts: [Dart]) -> Match? {
        var game = start
        for dart in darts {
            if game.legWinner != nil, !game.finished { Self.advanceLeg(&game) }
            do { try game.recordDart(dart) } catch { return nil }
        }
        return game
    }

    /// Po otevření nebo srovnání se serverem už ceremonie dohraného legu neběží. Hra rovnou pokračuje dalším legem.
    private func settled(_ game: Match?) -> Match? {
        guard var game else { return nil }
        if game.legWinner != nil, !game.finished { Self.advanceLeg(&game) }
        return game
    }

    /// Server střídá začínajícího hráče po legu. Rozhodující leg online nikdo nevybírá.
    static func advanceLeg(_ game: inout Match) {
        game.nextLeg()
        if game.needsDecidingStarter { game.resolveDecidingStarter(to: game.active) }
    }

    static func darts(of game: Match) -> [Dart] {
        game.visits.flatMap(\.darts) + game.currentDarts
    }

    private static func uuid(_ publicId: String) -> UUID {
        AppStore.stableID(forOnlineMatch: publicId)
    }
}

