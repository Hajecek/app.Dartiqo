import Foundation
import UIKit

/// Odehraný zápas ve tvaru, který ukládá web do tabulky `matches`.
/// Statistiky server počítá sám z hodů, proto se posílají jen hody a pravidla.
struct MatchUpload: Encodable {
    struct Config: Encodable {
        var mode: String
        var startingScore: Int
        var outRule: String
        var doubleIn: Bool
        var format: String
        var legsToWin: Int
        var setsToWin: Int
        var entry: String
        var dartLimit: Int?
        var cricketNumbers: [Int]
        var cricketNoScore: Bool
        var clockStyle: String
        var countUpRounds: Int
    }
    struct Ghost: Encodable {
        var kind: String?
        var label: String?
        var average: Double?
    }
    struct Bot: Encodable {
        var level: Int?
        var style: String?
        var adaptive: Bool
        var average: Double?
        var checkout: Double?
        var consistency: Double?
        var pressure: Double?
        var intelligence: Double?
    }
    struct Handicap: Encodable {
        var startingScore: Int?
        var outRule: String?
        var doubleIn: Bool?
    }
    struct Final: Encodable {
        var remaining: Int
        var points: Int
        var clockTarget: Int
    }
    struct PlayerLine: Encodable {
        var id: String
        var name: String
        /// owner, friend, guest, bot nebo ghost
        var kind: String
        var username: String?
        var bot: Bot?
        var handicap: Handicap?
        var final: Final
    }
    struct DartLine: Encodable {
        var s: Int
        var m: Int
        var x: Double?
        var y: Double?
    }
    struct VisitLine: Encodable {
        var player: Int
        var leg: Int
        var darts: [DartLine]
        var score: Int
        var remaining: Int
        var bust: Bool
        var checkout: Bool
        var total: Bool
    }

    var status: String
    var title: String
    var startedAt: Date
    var finishedAt: Date
    var playSeconds: Int
    var config: Config
    var ghost: Ghost?
    var openingStarter: Int
    var winner: Int?
    var bullOffLegs: [String: Int]
    var players: [PlayerLine]
    var visits: [VisitLine]
    var appVersion: String?
    var device: String
    /// Celý zápas z aplikace beze změny, aby šlo cokoli dopočítat i později.
    var match: Match

    init(match: Match, owner: UUID, friends: [Friend], profiles: [Profile]) {
        let config = match.config
        let options = config.settings
        status = match.finished ? "finished" : "abandoned"
        title = config.summary
        startedAt = match.createdAt
        finishedAt = match.completedAt ?? Date()
        playSeconds = Int(match.playedDuration.rounded())
        self.config = Config(
            mode: config.mode.rawValue,
            startingScore: config.startingScore,
            outRule: config.outRule.rawValue,
            doubleIn: config.doubleIn,
            format: config.format.rawValue,
            legsToWin: config.legsToWin,
            setsToWin: config.setsToWin,
            entry: options.entry.rawValue,
            dartLimit: options.dartLimit,
            cricketNumbers: options.activeCricketNumbers,
            cricketNoScore: options.cricketNoScore,
            clockStyle: options.clockStyle.rawValue,
            countUpRounds: options.countUpRounds
        )
        ghost = match.ghostVisits == nil ? nil : Ghost(kind: match.ghostKind?.rawValue, label: match.ghostLabel, average: match.ghostAverage)
        openingStarter = match.resolvedOpeningStarter
        winner = match.finished ? match.winner : nil
        bullOffLegs = Dictionary(uniqueKeysWithValues: (match.bullOffLegs ?? [:]).map { (String($0.key), $0.value) })
        players = match.players.enumerated().map { index, player in
            let friend = friends.first { $0.id == player.id || $0.linkedProfileID == player.id }
            let housemate = profiles.first { $0.id == player.id }
            let kind = match.isGhost(index) ? "ghost"
                : player.botLevel != nil ? "bot"
                : player.id == owner ? "owner"
                : friend != nil || housemate != nil ? "friend"
                : "guest"
            let handicap = config.mode == .x01 ? config.handicaps?[safe: index].flatMap { $0.isEmpty ? nil : $0 } : nil
            let state = match.states[index]
            return PlayerLine(
                id: player.id.uuidString.lowercased(),
                name: player.name,
                kind: kind,
                username: kind == "owner" ? nil : (friend?.username ?? housemate?.username),
                bot: player.botLevel == nil ? nil : Bot(
                    level: player.botLevel,
                    style: player.botStyle?.rawValue,
                    adaptive: player.adaptiveBot == true,
                    average: player.botAverage,
                    checkout: player.botCheckout,
                    consistency: player.botConsistency,
                    pressure: player.botPressure,
                    intelligence: player.botIntelligence
                ),
                handicap: handicap.map { Handicap(startingScore: $0.startingScore, outRule: $0.outRule?.rawValue, doubleIn: $0.doubleIn) },
                final: Final(remaining: state.remaining, points: state.points, clockTarget: state.clockTarget)
            )
        }
        visits = match.visits.map { visit in
            VisitLine(
                player: visit.player,
                leg: visit.leg,
                darts: visit.darts.map { DartLine(s: $0.segment, m: $0.multiplier, x: $0.x, y: $0.y) },
                score: visit.credited,
                remaining: visit.remaining,
                bust: visit.bust,
                checkout: visit.checkout,
                total: visit.enteredAsTotal == true
            )
        }
        appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
        device = UIDevice.current.name
        var raw = match
        raw.undoStack = []
        self.match = raw
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? { indices.contains(index) ? self[index] : nil }
}

/// Posílá odehrané zápasy na web. Server vrací, které zápasy už má,
/// takže se nic nepošle dvakrát a po přeinstalaci se dorovná zbytek.
@MainActor final class MatchSync {
    private unowned let account: DartiqoAccount
    private var running = false
    private var again = false
    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    init(account: DartiqoAccount) {
        self.account = account
    }

    func run(_ store: AppStore) async {
        guard !running else { again = true; return }
        running = true
        defer { running = false }
        repeat {
            again = false
            await pass(store)
        } while again
    }

    private func pass(_ store: AppStore) async {
        guard let api = account.api, let profile = store.profile, let accountID = account.user?.id, profile.accountID == accountID else { return }
        do {
            for id in store.data.pendingMatchDeletes ?? [] {
                try await api.deleteMatch(id: id)
                store.matchDeleteSynced(id)
            }
            store.trackUploadsOnce()
            let known = Set(try await api.matchIDs())
            let isKnown = { (match: Match) in known.contains(match.id.uuidString.lowercased()) }
            let uploaded = Set(store.data.uploadedMatches ?? [])
            let pendingDeletes = Set(store.data.pendingMatchDeletes ?? [])
            store.removeMatchesDeletedOnWeb(Set(store.matches.filter { uploaded.contains($0.id) && !isKnown($0) && !pendingDeletes.contains($0.id) }.map(\.id)))
            store.matchesUploaded(store.matches.filter { $0.finished && isKnown($0) }.map(\.id))
            for match in store.data.pendingAbandoned ?? [] {
                try await api.deleteMatch(id: match.id)
                store.abandonedMatchSynced(match.id)
            }
            let finished = store.matches.filter { $0.finished && !isKnown($0) }
            for match in finished {
                do {
                    let body = try encoder.encode(MatchUpload(match: match, owner: profile.id, friends: store.friends, profiles: store.data.profiles))
                    try await api.uploadMatch(id: match.id, body: body)
                    store.matchesUploaded([match.id])
                } catch APIError.server, is EncodingError {
                    // Zápas, který server odmítl nebo nejde zakódovat, by frontu blokoval napořád.
                }
            }
            await account.refresh(into: store)
        } catch APIError.unauthorized {
            account.handleUnauthorized()
        } catch {
            // Bez sítě se zkusí znovu při dalším otevření aplikace nebo po dalším zápase.
        }
    }
}
