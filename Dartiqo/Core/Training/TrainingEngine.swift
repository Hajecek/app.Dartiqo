import Foundation

enum TrainingEngine {
    static func start(definition: TrainingDefinition, config: TrainingConfig, owner: UUID, context: TrainingContext = TrainingContext(), seed: UInt64 = UInt64.random(in: 1...UInt64.max), now: Date = Date(), names: [String] = []) -> TrainingSession {
        let tuned = definition.kind.tuned(config, context)
        let seated = definition.options.multiplayer ? min(2, max(1, config.players)) : 1
        var people = names
        if people.isEmpty { people = ["Hráč"] }
        if seated == 2, people.count < 2 {
            let second = config.secondName.trimmingCharacters(in: .whitespacesAndNewlines)
            people.append(second.isEmpty ? "Hráč 2" : second)
        }
        return TrainingSession(
            owner: owner,
            definitionID: definition.id,
            config: config,
            seed: seed,
            kind: tuned,
            assignment: TrainingDeals.deal(tuned, seed: seed, config: config, context: context),
            players: seated,
            names: Array(people.prefix(seated)),
            startedAt: now
        )
    }

    static func project(_ session: TrainingSession, at now: Date = Date()) -> TrainingProjection {
        TrainingReplay.play(session, at: session.finishedAt ?? now)
    }

    static func record(_ action: TrainingAction, into session: inout TrainingSession, at now: Date = Date()) {
        guard session.status == .playing else { return }
        let current = TrainingReplay.play(session, at: now)
        if current.finished {
            close(&session, with: current, at: now)
            return
        }
        switch (current.phase, action) {
        case (.scoring, .dart(let dart)) where dart.isValid:
            session.actions.append(.dart(dart))
        case (.memorize, .ready):
            session.actions.append(.ready)
        case (.choose, .choose(let value)) where value == 0 || value == 1:
            session.actions.append(.choose(value))
        default:
            return
        }
        let next = TrainingReplay.play(session, at: now)
        if next.finished { close(&session, with: next, at: now) }
    }

    static func undo(_ session: inout TrainingSession) {
        guard !session.actions.isEmpty else { return }
        session.actions.removeLast()
        session.status = .playing
        session.finishedAt = nil
        session.result = nil
    }

    static func restart(_ session: inout TrainingSession) {
        session.actions = []
        session.status = .playing
        session.finishedAt = nil
        session.result = nil
    }

    static func abandon(_ session: inout TrainingSession, at now: Date = Date()) {
        guard session.status == .playing else { return }
        session.status = .abandoned
        session.finishedAt = now
        session.result = nil
    }

    /// Časové hry se uzavřou i bez dalšího hodu, jakmile limit vyprší.
    static func sync(_ session: inout TrainingSession, at now: Date = Date()) {
        guard session.status == .playing else { return }
        let current = TrainingReplay.play(session, at: now)
        if current.finished { close(&session, with: current, at: now) }
    }

    private static func close(_ session: inout TrainingSession, with projection: TrainingProjection, at now: Date) {
        session.finishedAt = now
        session.status = .completed
        session.result = projection.result
    }
}

private func resolvedLevel(_ config: TrainingConfig, _ context: TrainingContext) -> TrainingLevel {
    guard config.level == .adaptive else { return config.level }
    if let accuracy = context.recentAccuracy {
        if accuracy >= 0.6 { return .pro }
        if accuracy >= 0.35 { return .advanced }
    }
    return .beginner
}

private func easierLimit(_ value: Int, _ level: TrainingLevel) -> Int {
    switch level {
    case .beginner: return value + max(2, value / 2)
    case .pro: return max(3, value - max(2, value / 4))
    default: return value
    }
}

private func easierNeed(_ value: Int, _ level: TrainingLevel) -> Int {
    switch level {
    case .beginner: return max(1, value - 1)
    case .pro: return value + 1
    default: return value
    }
}

private func easierAccuracy(_ value: Double, _ level: TrainingLevel) -> Double {
    switch level {
    case .beginner: return max(0.08, value - 0.15)
    case .pro: return min(0.85, value + 0.12)
    default: return value
    }
}

private func easierLives(_ value: Int, _ level: TrainingLevel) -> Int {
    switch level {
    case .beginner: return value + 1
    case .pro: return max(1, value - 1)
    default: return value
    }
}

extension TrainingKind {
    func tuned(_ config: TrainingConfig, _ context: TrainingContext) -> TrainingKind {
        let level = resolvedLevel(config, context)
        switch self {
        case .around(let mult, let bull, let limit):
            return .around(mult: mult, bull: bull, limit: config.dartCount ?? easierLimit(limit, level))
        case .bobs27, .jdc, .halve:
            return self
        case .volume(let aim, let darts, let accuracy):
            let count = config.dartCount ?? darts
            let rate = config.requiredAccuracy ?? easierAccuracy(accuracy, level)
            return .volume(aim: aim, darts: count, accuracy: rate)
        case .shanghai(let numbers, let instant, let limit):
            let picked = (config.segments ?? []).filter { (1...20).contains($0) }
            let used = picked.isEmpty ? numbers : picked.sorted()
            return .shanghai(numbers: used, instant: instant, limit: config.dartCount ?? easierLimit(limit, level))
        case .cricket(let numbers, let limit):
            return .cricket(numbers: numbers, limit: config.dartCount ?? easierLimit(limit, level))
        case .checkoutFixed(let leaves, let visits, let need, let doubleIn):
            return .checkoutFixed(leaves: leaves, visits: config.rounds ?? visits, need: config.rounds ?? easierNeed(need, level), doubleIn: doubleIn)
        case .checkoutUntil(let start, let visits, let doubleIn):
            return .checkoutUntil(start: config.targetScore ?? start, visits: config.rounds ?? easierLimit(visits, level), doubleIn: doubleIn)
        case .checkoutRange(let low, let high, let count, let need):
            let rounds = config.rounds ?? count
            return .checkoutRange(low: low, high: high, count: rounds, need: min(rounds, config.rounds ?? easierNeed(need, level)))
        case .checkoutGenerated(let mode, let need):
            return .checkoutGenerated(mode: mode, need: easierNeed(need, level))
        case .x01(let start, let limit, let doubleIn, let average):
            let fixed = [9, 15, 30, 60].contains(limit)
            let cap = fixed ? limit : (config.dartCount ?? easierLimit(limit, level))
            let scaled = average.map { value -> Double in
                let shifted = level == .beginner ? value - 12 : level == .pro ? value + 12 : value
                return min(120, max(20, shifted))
            }
            let target = config.targetScore.map(Double.init) ?? scaled
            return .x01(start: start, limit: cap, doubleIn: doubleIn, minAverage: target)
        case .visitGoal(let atLeast, let exact, let count, let need):
            let rounds = config.rounds ?? count
            return .visitGoal(atLeast: atLeast, exact: exact, count: rounds, need: min(rounds, easierNeed(need, level)))
        case .ladder(let targets):
            if level == .beginner { return .ladder(targets: Array(targets.prefix(4))) }
            return .ladder(targets: targets)
        case .consistency(let visits, let spread, let floor):
            let rounds = config.rounds ?? (level == .beginner ? max(4, visits - 2) : level == .pro ? visits + 2 : visits)
            let band = level == .beginner ? spread + 25 : level == .pro ? max(12, spread - 15) : spread
            let minimum = config.targetScore ?? (level == .beginner ? max(15, floor - 15) : level == .pro ? floor + 15 : floor)
            return .consistency(visits: rounds, spread: band, floor: minimum)
        case .highScore(let visits):
            return .highScore(visits: config.rounds ?? visits)
        case .average(let visits, let target):
            let shifted = level == .beginner ? target - 15 : level == .pro ? target + 15 : target
            return .average(visits: config.rounds ?? visits, target: Double(config.targetScore ?? Int(shifted)))
        case .sniper(let rounds, let need):
            let count = config.rounds ?? rounds
            return .sniper(rounds: count, need: min(count, easierNeed(need, level)))
        case .hunter(let rounds, let lives):
            return .hunter(rounds: config.rounds ?? rounds, lives: config.lives ?? easierLives(lives, level))
        case .survivor(let steps, let lives):
            return .survivor(steps: config.rounds ?? steps, lives: config.lives ?? easierLives(lives, level))
        case .streak(let aim, let need, let limit):
            return .streak(aim: aim, need: easierNeed(need, level), limit: config.dartCount ?? easierLimit(limit, level))
        case .switchTreble(let darts, let need):
            let count = config.dartCount ?? darts
            return .switchTreble(darts: count, need: min(count, easierNeed(need, level)))
        case .roulette(let visits, let need):
            let count = config.rounds ?? visits
            return .roulette(visits: count, need: min(count, easierNeed(need, level)))
        case .bullScore(let darts, let target):
            let shifted = level == .beginner ? max(40, target - 80) : level == .pro ? target + 100 : target
            return .bullScore(darts: config.dartCount ?? darts, target: config.targetScore ?? shifted)
        case .combo(let need, let limit):
            return .combo(need: easierNeed(need, level), limit: config.dartCount ?? easierLimit(limit, level))
        case .sudden(let need, let limit):
            return .sudden(need: easierNeed(need, level), limit: config.dartCount ?? easierLimit(limit, level))
        case .puzzle(let count, let need):
            let rounds = config.rounds ?? count
            return .puzzle(count: rounds, need: min(rounds, easierNeed(need, level)))
        case .rush(let seconds, let need, let limit):
            return .rush(seconds: Int(config.timeLimit ?? Double(seconds)), need: easierNeed(need, level), limit: config.dartCount ?? limit)
        case .marathon(let tasks, let limit):
            return .marathon(tasks: tasks, limit: config.dartCount ?? easierLimit(limit, level))
        case .risk(let rounds, let target):
            let shifted = level == .beginner ? max(40, target - 40) : level == .pro ? target + 40 : target
            return .risk(rounds: config.rounds ?? rounds, target: config.targetScore ?? shifted)
        case .chaos(let limit):
            return .chaos(limit: config.dartCount ?? easierLimit(limit, level))
        case .segments(let pick, let mult, let darts, let accuracy):
            return .segments(pick: pick, mult: mult, darts: config.dartCount ?? darts, accuracy: config.requiredAccuracy ?? easierAccuracy(accuracy, level))
        case .perfect(let visits, let need, let total):
            let rounds = config.rounds ?? visits
            return .perfect(visits: rounds, need: min(rounds, easierNeed(need, level)), total: total)
        case .exact(let rounds, let need):
            let count = config.rounds ?? rounds
            return .exact(rounds: count, need: min(count, easierNeed(need, level)))
        case .memory(let length):
            let sized = level == .beginner ? max(3, length - 1) : level == .pro ? length + 2 : length
            return .memory(length: config.rounds ?? sized)
        case .escape(let rooms, let lives):
            return .escape(rooms: rooms, lives: config.lives ?? easierLives(lives, level))
        case .tower(let floors):
            let count = level == .beginner ? max(4, floors - 2) : floors
            return .tower(floors: count)
        case .oneDart(let rounds, let need):
            let count = config.rounds ?? rounds
            return .oneDart(rounds: count, need: min(count, easierNeed(need, level)))
        case .ghost(let visits):
            return .ghost(visits: config.rounds ?? visits)
        case .comeback(let opponentVisits):
            let visits = level == .beginner ? opponentVisits + 1 : level == .pro ? max(2, opponentVisits - 1) : opponentVisits
            return .comeback(opponentVisits: visits)
        case .finalDart(let visits, let need):
            let count = config.rounds ?? visits
            return .finalDart(visits: count, need: min(count, easierNeed(need, level)))
        case .daily(let tasks):
            return .daily(tasks: tasks)
        case .world(let stops):
            return .world(stops: stops)
        case .boss(let lives):
            return .boss(lives: config.lives ?? easierLives(lives, level))
        case .stepList(let tasks, let darts, let fail):
            return .stepList(tasks: config.rounds ?? tasks, darts: darts, fail: fail)
        }
    }
}

enum TrainingDeals {
    static func deal(_ kind: TrainingKind, seed: UInt64, config: TrainingConfig, context: TrainingContext) -> TrainingAssignment {
        var rng = TrainingRNG(seed: seed)
        var deal = TrainingAssignment()
        switch kind {
        case .around(let mult, let bull, _):
            deal.aims = (1...20).map { Aim.segment($0, mult) }
            if bull { deal.aims.append(.bull) }
        case .jdc:
            deal.aims = [.anyDouble, .segment(15, nil), .anyDouble, .segment(16, nil), .anyDouble, .segment(17, nil), .segment(18, nil), .segment(19, nil), .segment(20, nil), .bull]
        case .halve:
            deal.aims = (15...20).reversed().map { Aim.segment($0, nil) } + [.anyDouble, .anyTriple, .bull]
        case .checkoutFixed(let leaves, _, _, _):
            let split = splitLeaves(leaves)
            deal.leaves = split.ok
            deal.bogeys = split.bogeys
        case .checkoutRange(let low, let high, let count, _):
            var pool = checkoutables(low...high)
            if pool.isEmpty { pool = checkoutables(2...170) }
            deal.leaves = (0..<count).map { _ in rng.pick(pool) }
        case .checkoutGenerated(let mode, _):
            switch mode {
            case "ladder":
                deal.leaves = splitLeaves([40, 60, 80, 100, 120, 140, 160, 170]).ok
            case "countdown":
                deal.leaves = splitLeaves(Array(stride(from: 170, through: 40, by: -10))).ok
            case "doubles":
                deal.leaves = (1...20).map { $0 * 2 } + [50]
            default:
                let split = splitLeaves(Array(1...100))
                deal.leaves = split.ok
                deal.bogeys = split.bogeys
            }
        case .sniper(let rounds, _):
            deal.aims = (0..<rounds).map { _ in Aim.segment(rng.int(1...20), rng.int(1...3)) }
        case .hunter(let rounds, _), .roulette(let rounds, _):
            deal.aims = (0..<rounds).map { _ in Aim.segment(rng.int(1...20), 2) }
        case .survivor(let steps, _):
            var aims: [Aim] = []
            for number in [20, 19, 18, 17, 16, 15] {
                aims.append(contentsOf: [.segment(number, 1), .segment(number, 2), .segment(number, 3)])
            }
            aims.append(.innerBull)
            deal.aims = Array(aims.prefix(max(1, steps)))
        case .switchTreble(let darts, _):
            deal.aims = (0..<darts).map { _ in Aim.segment(rng.int(1...20), 3) }
        case .sudden(let need, _), .oneDart(let need, _):
            let count = max(need, kindOneCount(kind))
            deal.aims = (0..<count).map { _ in rng.pick(mixedAims()) }
        case .rush(_, let need, _):
            deal.aims = (0..<max(need, 24)).map { _ in rng.pick(mixedAims()) }
        case .puzzle(let count, _):
            let pool = checkoutables(32...170)
            for _ in 0..<count {
                let leave = rng.pick(pool)
                if let route = Checkout.route(for: leave) { deal.routes.append(route) }
            }
        case .exact(let rounds, _):
            let presets = exactPresets()
            deal.solutions = (0..<rounds).map { _ in rng.pick(presets) }
        case .perfect(let visits, _, _):
            deal.solutions = Array(repeating: [Dart(20), Dart(20), Dart(20)], count: visits)
        case .memory(let length):
            let pool = (1...20).map { Dart($0, 1) } + [Dart(20, 2), Dart(20, 3), Dart(25, 1)]
            deal.memory = (0..<length).map { _ in rng.pick(pool) }
        case .escape(let rooms, _):
            let leaves = splitLeaves([40, 32, 36, 24, 50, 20]).ok
            deal.leaves = Array(leaves.prefix(rooms))
            deal.labels = Array(["Chodba", "Bar", "Pódium", "Finále", "Šatna", "Střecha"].prefix(rooms))
        case .tower(let floors):
            let aims: [Aim] = [.segment(20, 1), .segment(19, 1), .anyDouble, .segment(20, 2), .segment(19, 3), .anyTriple, .bull, .innerBull]
            deal.aims = Array(aims.prefix(floors))
            deal.labels = (1...floors).map { "Patro \($0)" }
        case .marathon(let tasks, _):
            deal.aims = Array(marathonAims().prefix(tasks))
        case .daily(let tasks):
            deal.aims = Array(rng.shuffle(mixedAims()).prefix(tasks))
        case .world(let stops):
            let tour: [(String, Aim)] = [
                ("Praha", .segment(20, 3)), ("Londýn", .segment(16, 2)), ("New York", .bull),
                ("Tokio", .segment(19, 3)), ("Sydney", .segment(18, 2)), ("Berlín", .anyDouble),
                ("Dublin", .segment(17, 3)), ("Káhira", .innerBull)
            ]
            let picked = Array(tour.prefix(stops))
            deal.labels = picked.map(\.0)
            deal.aims = picked.map(\.1)
        case .boss:
            deal.aims = [.segment(20, 3), .segment(19, 3), .bull]
            deal.leaves = [40, 32, 50]
            deal.labels = ["Nováček", "Regular", "Legenda"]
        case .chaos:
            deal.aims = rng.shuffle((1...20).map { Aim.segment($0, nil) })
        case .segments(let pick, let mult, _, _):
            deal.aims = segmentAims(pick, mult: mult, config: config, context: context)
        case .ghost:
            deal.ghostScores = visitChunks(config.ghostDarts ?? [])
        case .finalDart(let visits, _):
            deal.aims = (0..<visits).map { _ in rng.pick(mixedAims()) }
        case .combo:
            deal.aims = [.segment(20, 1), .segment(20, 2), .segment(20, 3), .bull]
        case .streak(let aim, _, _):
            deal.aims = [aim]
        case .volume(let aim, _, _):
            deal.aims = [aim]
        case .stepList(let tasks, _, _):
            deal.aims = Array(marathonAims().prefix(tasks))
        default:
            break
        }
        return deal
    }

    private static func kindOneCount(_ kind: TrainingKind) -> Int {
        switch kind {
        case .oneDart(let rounds, _): return rounds
        case .sudden(let need, let limit): return min(limit, max(need, 8))
        default: return 8
        }
    }

    static func checkoutables(_ range: ClosedRange<Int>) -> [Int] {
        range.filter { Checkout.canFinish($0) }
    }

    private static func splitLeaves(_ scores: [Int]) -> (ok: [Int], bogeys: [Int]) {
        var ok: [Int] = []
        var bogeys: [Int] = []
        for score in scores {
            if Checkout.canFinish(score) { ok.append(score) } else { bogeys.append(score) }
        }
        return (ok, bogeys)
    }

    private static func mixedAims() -> [Aim] {
        [.segment(20, 3), .segment(19, 3), .segment(16, 2), .segment(20, 2), .segment(20, 1), .bull, .anyDouble, .segment(18, 3), .segment(15, 2), .innerBull]
    }

    private static func marathonAims() -> [Aim] {
        var aims: [Aim] = (1...10).map { .segment($0, nil) }
        aims.append(contentsOf: [.segment(20, 3), .segment(19, 3), .segment(18, 2), .segment(16, 2), .anyDouble, .anyTriple, .bull, .segment(20, 1), .innerBull, .segment(12, 2)])
        return aims
    }

    private static func exactPresets() -> [[Dart]] {
        [
            [Dart(20), Dart(20), Dart(20)],
            [Dart(20, 3), Dart(20), Dart(20)],
            [Dart(20), Dart(20), Dart(1)],
            [Dart(20, 3), Dart(19), Dart(1)],
            [Dart(20, 3), Dart(20), Dart(5)],
            [Dart(16, 2), Dart(16), Dart(16)],
            [Dart(20, 3), Dart(19, 3), Dart(20)],
            [Dart(15), Dart(15), Dart(15)]
        ]
    }

    private static func segmentAims(_ pick: SegmentPick, mult: Int?, config: TrainingConfig, context: TrainingContext) -> [Aim] {
        if let custom = config.segments?.filter({ (1...20).contains($0) || $0 == 25 }), !custom.isEmpty {
            return custom.map { Aim.segment($0, $0 == 25 ? nil : mult) }
        }
        switch pick {
        case .list(let numbers):
            return numbers.map { Aim.segment($0, $0 == 25 ? nil : mult) }
        case .singles:
            return (1...20).map { Aim.segment($0, 1) }
        case .rare:
            let numbers = context.rareSegments.isEmpty ? [5, 7, 3, 2, 11, 9] : context.rareSegments
            return numbers.map { Aim.segment($0, mult) }
        case .weak:
            if !context.weakAims.isEmpty { return context.weakAims }
            return [.segment(20, 3), .segment(16, 2), .segment(20, nil), .bull]
        }
    }

    private static func visitChunks(_ darts: [Dart]) -> [Int] {
        guard !darts.isEmpty else { return [] }
        var scores: [Int] = []
        var index = 0
        while index < darts.count {
            let end = min(index + 3, darts.count)
            scores.append(darts[index..<end].reduce(0) { $0 + $1.score })
            index = end
        }
        return scores
    }
}

func idealScoringDart(remaining: Int, dartsInVisit: Int, budget: Int, doubleIn: Bool, opened: Bool) -> Dart {
    if doubleIn && !opened {
        for segment in [20, 16, 8, 10, 4, 2, 1] {
            let dart = Dart(segment, 2)
            if !ScoringRules.isBust(remaining: remaining, dart: dart, rule: .double) { return dart }
        }
    }
    let room = max(1, min(3 - dartsInVisit, budget))
    if let route = Checkout.route(for: remaining, darts: room), let first = route.first { return first }
    for multiplier in [3, 2, 1] {
        let segments = multiplier == 1 ? Array(stride(from: 20, through: 1, by: -1)) : [20, 19, 18, 17, 16, 15, 14, 13, 12, 11, 10]
        for segment in segments {
            let dart = Dart(segment, multiplier)
            if !ScoringRules.isBust(remaining: remaining, dart: dart, rule: .double) { return dart }
        }
    }
    if !ScoringRules.isBust(remaining: remaining, dart: Dart(25), rule: .double) { return Dart(25) }
    return .miss
}
