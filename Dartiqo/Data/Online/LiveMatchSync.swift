import Foundation

/// Co web potřebuje k živému zobrazení. Skóre počítá telefon, web ho jen kreslí.
struct LiveMatchState: Encodable, Equatable {
    struct PlayerLine: Encodable, Equatable {
        var name: String
        var bot: Bool
        var score: String
        var legs: Int
        var sets: Int
        var average: Double
        var darts: Int
        var last: Int?
        var checkout: String
        var marks: [String: Int]
    }

    struct VisitLine: Encodable, Equatable {
        var player: Int
        var darts: [String]
        var score: Int
        var bust: Bool
        var checkout: Bool
    }

    var seq = 0
    var status: String
    var mode: String
    var title: String
    var startedAt: Date
    var leg: Int
    var set: Int
    var legsToWin: Int
    var setsToWin: Int
    var active: Int
    var winner: Int?
    var numbers: [Int]
    var players: [PlayerLine]
    var currentDarts: [String]
    var visits: [VisitLine]

    init(match: Match) {
        let live = match.liveProjection
        let config = match.config
        let pending = match.currentDarts.count
        status = match.finished ? "finished" : "live"
        mode = config.mode.rawValue
        title = config.summary
        startedAt = match.createdAt
        leg = live.leg
        set = config.playsSets ? live.states.reduce(0) { $0 + $1.sets } + 1 : 1
        legsToWin = config.legsToWin
        setsToWin = config.setsToWin
        active = live.active
        winner = match.winner
        numbers = config.mode == .cricket ? config.settings.activeCricketNumbers : []
        players = match.players.indices.map { index in
            let state = live.states[index]
            var checkout = ""
            if config.mode == .x01, index == live.active, !match.finished,
               let route = Checkout.route(for: state.remaining, rule: config.outRule(for: index), darts: 3 - pending) {
                checkout = route.map(\.label).joined(separator: " ")
            }
            return PlayerLine(
                name: match.players[index].name,
                bot: match.players[index].botLevel != nil || match.isGhost(index),
                score: Self.figure(state, mode: config.mode),
                legs: state.legs,
                sets: state.sets,
                average: (match.average(for: index) * 100).rounded() / 100,
                darts: match.thrownDarts(for: index),
                last: match.lastTurnScore(for: index),
                checkout: checkout,
                marks: config.mode == .cricket ? Dictionary(uniqueKeysWithValues: state.marks.map { (String($0.key), $0.value) }) : [:]
            )
        }
        currentDarts = match.currentDarts.map(\.label)
        visits = match.visits.suffix(12).map {
            VisitLine(player: $0.player, darts: $0.darts.map(\.label), score: $0.credited, bust: $0.bust, checkout: $0.checkout)
        }
    }

    private static func figure(_ state: PlayerState, mode: GameMode) -> String {
        switch mode {
        case .x01: return "\(state.remaining)"
        case .cricket, .countUp: return "\(state.points)"
        case .aroundClock: return state.clockTarget > 20 ? "Bull" : "\(state.clockTarget)"
        }
    }
}

/// Posílá stav rozehraného zápasu na web. Vždy jen jeden požadavek, novější stav přepíše čekající.
@MainActor final class LiveMatchSync {
    private struct Job {
        var id: UUID
        var state: LiveMatchState
        var attempts = 0
    }

    private unowned let account: DartiqoAccount
    private var sentID: UUID?
    private var sentState: LiveMatchState?
    private var lastSeq: [UUID: Int] = [:]
    private var queue: [Job] = []
    private var sending = false
    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    init(account: DartiqoAccount) {
        self.account = account
    }

    func update(_ match: Match?) {
        guard account.isSignedIn else {
            sentID = nil
            sentState = nil
            queue.removeAll()
            return
        }
        // Vypnutý přenos se pro web chová jako ukončený zápas
        let match = account.liveSharing ? match : nil
        // Zápas zmizel, nebo ho nahradil jiný, aniž by doběhl: web ho přestane ukazovat
        if let sentID, let sentState, sentState.status == "live", sentID != match?.id {
            var abandoned = sentState
            abandoned.status = "abandoned"
            enqueue(Job(id: sentID, state: abandoned))
        }
        guard let match else {
            sentID = nil
            sentState = nil
            return
        }
        let state = LiveMatchState(match: match)
        guard match.id != sentID || state != sentState else { return }
        sentID = match.id
        sentState = state
        enqueue(Job(id: match.id, state: state))
    }

    private func enqueue(_ job: Job) {
        queue.removeAll { $0.id == job.id }
        queue.append(job)
        guard !sending else { return }
        Task { await drain() }
    }

    private func drain() async {
        sending = true
        defer { sending = false }
        while !queue.isEmpty {
            var job = queue.removeFirst()
            guard let api = account.api else { queue.removeAll(); return }
            // Desetiny sekundy od začátku zápasu rostou i po restartu aplikace, server tak nezahodí nový stav
            let elapsed = Int(Date().timeIntervalSince(job.state.startedAt) * 10)
            job.state.seq = max((lastSeq[job.id] ?? 0) + 1, elapsed, 1)
            lastSeq[job.id] = job.state.seq
            do {
                try await api.pushLiveMatch(id: job.id, body: try encoder.encode(job.state))
            } catch APIError.unauthorized {
                account.handleUnauthorized()
                queue.removeAll()
                return
            } catch {
                // Výpadek sítě: zkusit znovu, pokud mezitím nepřišel novější stav
                job.attempts += 1
                if job.attempts < 3, !queue.contains(where: { $0.id == job.id }) {
                    try? await Task.sleep(for: .seconds(3))
                    if !queue.contains(where: { $0.id == job.id }) { queue.append(job) }
                }
            }
        }
    }
}
