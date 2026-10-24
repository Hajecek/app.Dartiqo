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
        var setup: String
        var setupLeave: String
        var out: String
        var marks: [String: Int]
    }

    struct VisitLine: Encodable, Equatable {
        var player: Int
        var leg: Int
        var set: Int
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
            var setup = ""
            var setupLeave = ""
            let left = 3 - pending
            if config.mode == .x01, index == live.active, !match.finished, left > 0 {
                let rule = config.outRule(for: index)
                if let route = Checkout.route(for: state.remaining, rule: rule, darts: left) {
                    checkout = route.map(\.label).joined(separator: " ")
                } else if let hint = Checkout.setup(for: state.remaining, rule: rule, darts: left) {
                    setup = hint.darts.map(\.label).joined(separator: " ")
                    setupLeave = hint.leaveLabel
                }
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
                setup: setup,
                setupLeave: setupLeave,
                out: config.mode == .x01 ? config.outRule(for: index).rawValue : "",
                marks: config.mode == .cricket ? Dictionary(uniqueKeysWithValues: state.marks.map { (String($0.key), $0.value) }) : [:]
            )
        }
        currentDarts = match.currentDarts.map(\.label)
        let setByLeg = Self.setByLeg(in: match)
        // Web kreslí všechny legy, proto jde celá historie. Strop drží požadavek v limitu serveru.
        visits = match.visits.suffix(1500).map {
            VisitLine(
                player: $0.player,
                leg: $0.leg,
                set: setByLeg[$0.leg] ?? 1,
                darts: $0.darts.map(\.label),
                score: $0.credited,
                bust: $0.bust,
                checkout: $0.checkout
            )
        }
    }

    /// Číslo setu u každého legu. Stejná logika jako historie hodů v aplikaci.
    private static func setByLeg(in match: Match) -> [Int: Int] {
        guard match.config.playsSets else {
            return Dictionary(uniqueKeysWithValues: Set(match.visits.map(\.leg) + [match.leg]).map { ($0, 1) })
        }
        let target = match.config.legsToWin
        var set = 1
        var setLegs = Array(repeating: 0, count: match.players.count)
        var map: [Int: Int] = [:]
        var numbers = Set(match.visits.map(\.leg))
        numbers.insert(match.leg)
        numbers.formUnion(match.bullOffLegs?.keys.map { $0 } ?? [])
        for leg in numbers.sorted() {
            map[leg] = set
            let winner = match.bullOffLegs?[leg]
                ?? match.visits.last(where: { $0.leg == leg && $0.checkout })?.player
                ?? (leg == match.leg && match.finished ? match.winner : nil)
            guard let winner else { continue }
            setLegs[winner] += 1
            if setLegs[winner] >= target {
                set += 1
                setLegs = Array(repeating: 0, count: match.players.count)
            }
        }
        return map
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
                // Výpadek sítě: u živého zápasu zkoušet dál, novější stav starý požadavek nahradí
                job.attempts += 1
                let live = job.state.status == "live"
                if (live || job.attempts < 4), !queue.contains(where: { $0.id == job.id }) {
                    let delay = min(live ? 8.0 : 3.0, pow(1.5, Double(min(job.attempts, 8))))
                    try? await Task.sleep(for: .seconds(delay))
                    if !queue.contains(where: { $0.id == job.id }) { queue.append(job) }
                }
            }
        }
    }
}
