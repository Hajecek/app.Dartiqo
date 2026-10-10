import Foundation

extension Match {
    /// Applies a real visit. Unthrown darts after a bust or finish are discarded.
    public mutating func submit(_ darts: [Dart], allowPartial: Bool = false) throws {
        guard currentDarts.isEmpty else { throw GameError.unfinishedVisit }
        var next = self
        try next.applyVisit(darts)
        if !allowPartial && darts.count < 3 && next.visits.last?.bust != true && next.visits.last?.checkout != true { throw GameError.invalidDarts }
        self = next
    }
    private mutating func applyVisit(_ darts: [Dart]) throws {
        guard !finished else { throw GameError.finished }
        guard legWinner == nil, !needsBullOff else { throw GameError.legEnded }
        guard (1...3).contains(darts.count), darts.allSatisfy(\.isValid) else { throw GameError.invalidDarts }
        undoStack.append(snapshot)
        let index = active
        let before = states[index]
        var used: [Dart] = []; var credited = 0; var bust = false; var won = false
        for dart in darts {
            used.append(dart)
            switch config.mode {
            case .x01:
                if !states[index].opened {
                    guard dart.multiplier == 2 else { continue }
                    states[index].opened = true
                }
                let next = states[index].remaining - dart.score
                let rule = config.outRule(for: index)
                if next < 0 || (next == 1 && rule != .straight) || (next == 0 && !rule.allows(dart)) {
                    states[index] = before; credited = 0; bust = true
                } else {
                    states[index].remaining = next; credited += dart.score; won = next == 0
                }
            case .cricket:
                guard dart.segment >= 15 && (dart.segment <= 20 || dart.segment == 25) else { continue }
                let old = states[index].marks[dart.segment, default: 0]
                let excess = max(0, old + dart.multiplier - 3)
                states[index].marks[dart.segment] = min(3, old + dart.multiplier)
                if !config.settings.cricketNoScore && states.indices.contains(where: { $0 != index && states[$0].marks[dart.segment, default: 0] < 3 }) {
                    states[index].points += excess * dart.segment; credited += excess * dart.segment
                }
                won = [15,16,17,18,19,20,25].allSatisfy { states[index].marks[$0, default: 0] == 3 } && (config.settings.cricketNoScore || states.indices.allSatisfy { $0 == index || states[index].points >= states[$0].points })
            case .aroundClock:
                let target = states[index].clockTarget == 21 ? 25 : states[index].clockTarget
                if dart.segment == target && (target == 25 ? (config.settings.clockStyle == .any || dart.multiplier == 2) : config.settings.clockStyle.accepts(dart)) { states[index].clockTarget += 1; credited += 1 }
                won = states[index].clockTarget == 22
            case .countUp:
                states[index].points += dart.score; credited += dart.score
            }
            if bust || won { break }
        }
        states[index].rounds += 1
        visits.append(Visit(player: index, leg: leg, darts: used, credited: credited, bust: bust, checkout: won, remaining: states[index].remaining))
        if config.mode == .countUp && states.allSatisfy({ $0.rounds >= config.settings.countUpRounds }) {
            let high = states.map(\.points).max() ?? 0
            let leaders = states.indices.filter { states[$0].points == high }
            winner = leaders.count == 1 ? leaders[0] : nil
            finished = true; completedAt = Date()
        } else if won {
            winLeg(index)
        } else {
            active = (active + 1) % players.count
            checkDartLimit()
        }
    }
    private mutating func winLeg(_ index: Int) {
        states[index].legs += 1; legWinner = index
        let instant = [.aroundClock, .countUp].contains(config.mode)
        if instant || config.setsToWin <= 1 {
            if instant || states[index].legs >= config.legsToWin {
                finished = true; winner = index; completedAt = Date()
            }
        } else if states[index].legs >= config.legsToWin {
            states[index].sets += 1
            if states[index].sets >= config.setsToWin {
                finished = true; winner = index; completedAt = Date()
            }
        }
    }
    /// Kolik šipek na hráče v legu zbývá do rozhozu. `nil`, když se limit nehraje.
    public var dartLimitRounds: Int? {
        guard config.mode == .x01, let limit = config.settings.dartLimit, limit >= 3 else { return nil }
        return limit / 3
    }
    /// Po posledním kole limitu se leg nedohrává. Rozhodne rozhoz na střed.
    mutating func checkDartLimit() {
        guard let rounds = dartLimitRounds, legWinner == nil, !finished,
              states.allSatisfy({ $0.rounds >= rounds }) else { return }
        awaitingBullOff = true
    }
    /// Leg po vypršení limitu bere vítěz rozhozu na střed.
    public mutating func awardBullOff(to player: Int) {
        guard needsBullOff, players.indices.contains(player) else { return }
        undoStack.append(snapshot)
        pendingDarts = nil
        awaitingBullOff = nil
        var decided = bullOffLegs ?? [:]
        decided[leg] = player
        bullOffLegs = decided
        winLeg(player)
    }
    public mutating func nextLeg() {
        guard legWinner != nil, !finished else { return }
        // Keep last visit snapshot so undo at the start of a leg restores its winning visit.
        let setClosed = config.setsToWin > 1 && states.contains { $0.legs >= config.legsToWin }
        states = states.enumerated().map { player, state in
            var fresh = PlayerState(config: config, player: player)
            fresh.sets = state.sets
            fresh.legs = setClosed ? 0 : state.legs
            return fresh
        }
        starter = (starter + 1) % players.count; active = starter; leg += 1; legWinner = nil
    }
    public mutating func undo() {
        guard let old = undoStack.popLast() else { return }
        pendingDarts = nil
        states = old.states; active = old.active; starter = old.starter; leg = old.leg
        legWinner = old.legWinner; winner = old.winner; finished = old.finished
        awaitingBullOff = old.awaitingBullOff; bullOffLegs = old.bullOffLegs
        visits = Array(visits.prefix(old.visitCount)); completedAt = nil
    }
    /// Vrátí zápas do stavu těsně před zvoleným kolem; to i všechna další kola zmizí.
    @discardableResult
    public mutating func rewind(before visitID: UUID) -> Bool {
        guard let index = visits.firstIndex(where: { $0.id == visitID }) else { return false }
        var next = self
        next.pendingDarts = nil
        while next.visits.count > index, !next.undoStack.isEmpty { next.undo() }
        guard next.visits.count == index else { return false }
        self = next
        return true
    }
    /// Undo bot replies together with the human visit they answered.
    public mutating func undoHumanTurn() {
        guard !undoStack.isEmpty else { return }
        let hasHuman = players.contains { $0.botLevel == nil }
        repeat { undo() } while hasHuman && currentPlayer.botLevel != nil && !undoStack.isEmpty
    }
}

public enum Checkout {
    /// Doubles players actually aim at when finishing (most common first).
    private static let preferredDoubles = [20, 16, 8, 4, 2, 18, 12, 10, 6, 14, 5, 9, 11, 13, 15, 17, 19, 7, 3, 1, 25]

    /// Setup shots in human preference: big trebles → bull → singles → rare trebles last.
    /// Avoids tips like T3 for 15; prefers S7→D4 / S3→D6 style routes.
    private static let preferredSetups: [Dart] = {
        let power = [20, 19, 18, 17, 16, 15, 14, 13, 12, 11, 10].map { Dart($0, 3) }
        let bull = [Dart(25, 2), Dart(25)]
        let singles = (1...20).reversed().map { Dart($0) }
        let rareTrebles = [9, 8, 7, 6, 5, 4, 3, 2, 1].map { Dart($0, 3) }
        let setupDoubles = [20, 16, 8, 4, 2, 18, 12, 10, 6, 14].map { Dart($0, 2) }
        return power + bull + singles + rareTrebles + setupDoubles
    }()

    /// Legal checkout using routes players recognise — popular doubles and natural setups.
    public static func route(for score: Int, rule: OutRule = .double, darts: Int = 3) -> [Dart]? {
        guard score > 0, darts > 0, score <= 180 else { return nil }
        let ends = finishingDarts(rule: rule)

        for end in ends where end.score == score { return [end] }
        if darts >= 2, let two = twoDart(score: score, ends: ends) { return two }
        if darts >= 3 {
            for first in preferredSetups {
                let left = score - first.score
                guard left > 0 else { continue }
                if let end = ends.first(where: { $0.score == left }) {
                    return [first, end]
                }
                if let rest = twoDart(score: left, ends: ends) {
                    return [first] + rest
                }
            }
        }
        return nil
    }

    private static func finishingDarts(rule: OutRule) -> [Dart] {
        let doubles = preferredDoubles.map { Dart($0, 2) }
        switch rule {
        case .double:
            return doubles
        case .master:
            let trebles = (1...20).reversed().map { Dart($0, 3) }
            return doubles + trebles
        case .straight:
            return doubles + preferredSetups
        }
    }

    /// Prefer leaving a popular double; pick the most natural setup that scores the remainder.
    private static func twoDart(score: Int, ends: [Dart]) -> [Dart]? {
        for end in ends {
            let need = score - end.score
            guard need > 0 else { continue }
            if let setup = preferredSetups.first(where: { $0.score == need }) {
                return [setup, end]
            }
        }
        return nil
    }

    /// One-dart leaves players recognise, best first. Bull sits with the big doubles.
    private static let favouriteLeaves = [40, 32, 50, 36, 24, 16, 20, 8, 12, 28, 18, 38, 34, 30, 26, 22, 14, 10, 6, 4, 2]
    /// Comfortable two- and three-dart scores when a double is out of reach this visit.
    private static let classicLeaves = [100, 80, 60, 110, 120, 81, 85, 90, 96, 64, 68, 76, 84, 41, 45, 61, 65, 70, 130, 140, 150]

    /// Natural scoring shots for a setup: big trebles, singles, bull, then rarer beds.
    private static let setupAims: [Dart] = {
        var seen = Set<Dart>()
        var aims: [Dart] = []
        func add(_ dart: Dart) {
            guard seen.insert(dart).inserted else { return }
            aims.append(dart)
        }
        for segment in [20, 19, 18, 17, 16, 15] { add(Dart(segment, 3)) }
        for segment in stride(from: 20, through: 1, by: -1) { add(Dart(segment)) }
        add(Dart(25, 2)); add(Dart(25))
        for segment in stride(from: 14, through: 1, by: -1) { add(Dart(segment, 3)) }
        for segment in [20, 16, 8, 4, 2, 18, 12, 10, 6, 14] { add(Dart(segment, 2)) }
        for segment in 1...20 { add(Dart(segment, 2)) }
        return aims
    }()

    private static let checkoutableLeaves: [OutRule: [Int]] = {
        Dictionary(uniqueKeysWithValues: OutRule.allCases.map { rule in
            (rule, (1...170).filter { route(for: $0, rule: rule, darts: 3) != nil })
        })
    }()

    /// A visit that cannot finish. `darts` land on `leaves`, which itself has a checkout.
    public struct SetupHint: Equatable {
        public let darts: [Dart]
        public let leaves: Int
        public let leaveLabel: String
    }

    /// When a finish is impossible, the most natural way to leave a score you can close later.
    public static func setup(for score: Int, rule: OutRule = .double, darts: Int = 3) -> SetupHint? {
        guard (1...3).contains(darts), (2...180).contains(score) else { return nil }
        guard route(for: score, rule: rule, darts: darts) == nil else { return nil }
        let floor = rule == .straight ? 1 : 2
        guard score > floor else { return nil }

        var cache = PathCache()
        var best: (path: [Dart], leave: Int, quality: Int)?
        for leave in checkoutableLeaves[rule] ?? [] where leave >= floor && leave < score {
            guard let path = scoringPath(need: score - leave, darts: darts, cache: &cache), !path.isEmpty else { continue }
            let quality = setupQuality(path: path, leave: leave, from: score, rule: rule, floor: floor)
            if best == nil || quality < best!.quality {
                best = (path, leave, quality)
            }
        }
        guard let best else { return nil }
        return SetupHint(darts: best.path, leaves: best.leave, leaveLabel: leaveLabel(for: best.leave, rule: rule))
    }

    private static func leaveLabel(for leave: Int, rule: OutRule) -> String {
        if let dart = route(for: leave, rule: rule, darts: 1)?.first {
            if dart.segment == 25, dart.multiplier == 2 { return "Bull" }
            return dart.label
        }
        return "\(leave)"
    }

    private static func setupQuality(path: [Dart], leave: Int, from score: Int, rule: OutRule, floor: Int) -> Int {
        var quality: Int
        if let rank = favouriteLeaves.firstIndex(of: leave) {
            quality = rank * 55
        } else if let rank = classicLeaves.firstIndex(of: leave) {
            quality = 640 + rank * 18
        } else if let finish = route(for: leave, rule: rule, darts: 3) {
            quality = 980 + finish.count * 120
            if let end = finish.last, end.multiplier == 2 || end.segment == 25 {
                quality += (preferredDoubles.firstIndex(of: end.segment) ?? 24) * 8
            }
        } else {
            quality = 5_000
        }
        if leave <= 4 { quality += 500 }
        for (index, dart) in path.enumerated() {
            let aim = setupAims.firstIndex(of: dart) ?? 100
            quality += aim * (index == 0 ? 14 : 4)
        }
        quality += (path.count - 1) * 35
        if let first = path.first {
            quality -= insurance(first, from: score, floor: floor, rule: rule)
        }
        return quality
    }

    /// Treble (and double) beds where a smaller ring still leaves a finish.
    private static func insurance(_ dart: Dart, from score: Int, floor: Int, rule: OutRule) -> Int {
        guard dart.segment <= 20 else { return 0 }
        var bonus = 0
        if dart.multiplier >= 2 {
            let single = score - dart.segment
            if single >= floor, route(for: single, rule: rule, darts: 3) != nil { bonus += 220 }
        }
        if dart.multiplier == 3 {
            let double = score - dart.segment * 2
            if double >= floor, route(for: double, rule: rule, darts: 3) != nil { bonus += 80 }
        }
        return bonus
    }

    private struct PathCache {
        var found: [Int: [Dart]] = [:]
        var absent = Set<Int>()
        func key(_ need: Int, _ darts: Int) -> Int { (need << 2) | darts }
    }

    /// Fewest, most natural darts that score exactly `need`.
    private static func scoringPath(need: Int, darts: Int, cache: inout PathCache) -> [Dart]? {
        if need == 0 { return [] }
        let key = cache.key(need, darts)
        if let hit = cache.found[key] { return hit }
        if cache.absent.contains(key) { return nil }
        let path = findScoringPath(need: need, darts: darts, cache: &cache)
        if let path { cache.found[key] = path } else { cache.absent.insert(key) }
        return path
    }

    private static func findScoringPath(need: Int, darts: Int, cache: inout PathCache) -> [Dart]? {
        guard darts > 0, need > 0, need <= 60 * darts else { return nil }
        if let single = setupAims.first(where: { $0.score == need }) { return [single] }
        guard darts > 1 else { return nil }
        for first in setupAims where first.score < need {
            if let rest = scoringPath(need: need - first.score, darts: darts - 1, cache: &cache) {
                return [first] + rest
            }
        }
        return nil
    }
}
