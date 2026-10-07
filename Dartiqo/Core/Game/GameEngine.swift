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
        guard legWinner == nil else { throw GameError.legEnded }
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
                if next < 0 || (next == 1 && config.outRule != .straight) || (next == 0 && !config.outRule.allows(dart)) {
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
            states[index].legs += 1; legWinner = index
            if states[index].legs >= config.legsToWin || [.aroundClock, .countUp].contains(config.mode) {
                finished = true; winner = index; completedAt = Date()
            }
        } else { active = (active + 1) % players.count }
    }
    public mutating func nextLeg() {
        guard legWinner != nil, !finished else { return }
        // Keep last visit snapshot so undo at the start of a leg restores its winning visit.
        states = states.map { state in var fresh = PlayerState(config: config); fresh.legs = state.legs; return fresh }
        starter = (starter + 1) % players.count; active = starter; leg += 1; legWinner = nil
    }
    public mutating func undo() {
        guard let old = undoStack.popLast() else { return }
        pendingDarts = nil
        states = old.states; active = old.active; starter = old.starter; leg = old.leg
        legWinner = old.legWinner; winner = old.winner; finished = old.finished
        visits = Array(visits.prefix(old.visitCount)); completedAt = nil
    }
    /// Undo bot replies together with the human visit they answered.
    public mutating func undoHumanTurn() {
        guard !undoStack.isEmpty else { return }
        repeat { undo() } while currentPlayer.botLevel != nil && !undoStack.isEmpty
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
}
