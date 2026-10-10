import Foundation

/// Společná X01 pravidla pro zápas i trénink. Zápasové `applyVisit` volá stejné predikáty.
enum ScoringRules {
    struct VisitOutcome: Equatable {
        var remaining: Int
        var opened: Bool
        var credited: Int
        var bust: Bool
        var won: Bool
        var used: [Dart]
    }

    /// Double-in: než se hra otevře, počítá se jen double. Šipka se přesto považuje za hozenou.
    static func counts(_ dart: Dart, opened: Bool, doubleIn: Bool) -> Bool {
        !doubleIn || opened || dart.multiplier == 2
    }

    /// Přehoz: pod nulu, na 1 při double/master out, nebo na nulu šipkou, která out nesplňuje.
    static func isBust(remaining: Int, dart: Dart, rule: OutRule) -> Bool {
        let next = remaining - dart.score
        return next < 0 || (next == 1 && rule != .straight) || (next == 0 && !rule.allows(dart))
    }

    /// Jedna návštěva. Po bustu nebo zavření se další šipky z pole nehrají a bust vrací stav ze začátku návštěvy.
    static func applyVisit(remaining: Int, opened: Bool, darts: [Dart], rule: OutRule, doubleIn: Bool) -> VisitOutcome {
        let startRemaining = remaining
        let startOpened = opened
        var remaining = remaining
        var opened = opened
        var credited = 0
        var bust = false
        var won = false
        var used: [Dart] = []
        for dart in darts where dart.isValid {
            used.append(dart)
            if !counts(dart, opened: opened, doubleIn: doubleIn) { continue }
            if doubleIn && !opened { opened = true }
            if isBust(remaining: remaining, dart: dart, rule: rule) {
                return VisitOutcome(remaining: startRemaining, opened: startOpened, credited: 0, bust: true, won: false, used: used)
            }
            remaining -= dart.score
            credited += dart.score
            won = remaining == 0
            if won { break }
        }
        return VisitOutcome(remaining: remaining, opened: opened, credited: credited, bust: bust, won: won, used: used)
    }
}
