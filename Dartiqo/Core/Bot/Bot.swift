import Foundation

public struct BotLevel: Identifiable {
    public let id: Int
    public let name: String
    public let precision: Double
    /// Jméno postavy, se kterou hráč hraje. Vyšší úrovně jen připomínají známé hráče.
    public let persona: String
    public let nickname: String
    /// Portrét v assetech.
    public var photo: String { "BotLevel\(id)" }
    public static let all: [BotLevel] = [
        .init(id: 1, name: "První šipky", precision: 0.035, persona: "Pepa Mráz", nickname: "Kapsa"),
        .init(id: 2, name: "Začátečník", precision: 0.07, persona: "Jana Malá", nickname: "Jednička"),
        .init(id: 3, name: "Hospodský hráč", precision: 0.12, persona: "Franta Beran", nickname: "Pivko"),
        .init(id: 4, name: "Pravidelný hráč", precision: 0.18, persona: "Lucie Dvořáková", nickname: "Double"),
        .init(id: 5, name: "Klubový hráč", precision: 0.25, persona: "Honza Kos", nickname: "Plamen"),
        .init(id: 6, name: "Ligový hráč", precision: 0.32, persona: "Peter Wrighton", nickname: "Snakebyte"),
        .init(id: 7, name: "Expert", precision: 0.39, persona: "Gerwin Pryce", nickname: "Ice-Man"),
        .init(id: 8, name: "Mistr", precision: 0.46, persona: "Gary Andersen", nickname: "Flying Skot"),
        .init(id: 9, name: "Profesionál", precision: 0.53, persona: "Luke Litler", nickname: "Nukeboy"),
        .init(id: 10, name: "Legenda", precision: 0.60, persona: "Phil Tayler", nickname: "Powerhouse")
    ]
    public static func get(_ level: Int) -> BotLevel { all[min(9, max(0, level - 1))] }

    /// Orientační statistiky podle úrovně.
    /// Level 10 ≈ průměrný PDC tour pro (televizní / ProTour čísla ~2024):
    /// průměr cca 92–98, doubles ~40–45 %, zhruba 0,3× 180 na leg.
    private var profile: BotStatProfile { BotStatProfile.forLevel(id) }

    public var averageLow: Int { profile.averageLow }
    public var averageHigh: Int { profile.averageHigh }
    public var averageText: String { "\(averageLow)–\(averageHigh)" }

    public var checkoutLow: Int { profile.checkoutLow }
    public var checkoutHigh: Int { profile.checkoutHigh }
    public var checkoutText: String { "\(checkoutLow)–\(checkoutHigh) %" }

    /// Orientační počet maxim na leg (klasická profi statistika).
    public var oneEightiesPerLeg: Double { profile.oneEightiesPerLeg }
    public var maxVisitText: String {
        let value = oneEightiesPerLeg.formatted(.number.precision(.fractionLength(oneEightiesPerLeg < 0.1 ? 2 : 1)))
        return "\(value) / leg"
    }

    public var throwSeconds: Double { profile.throwSeconds }
    public var throwTempoLabel: String {
        switch throwSeconds {
        case ..<1.0: return "Rychlé"
        case ..<1.7: return "Plynulé"
        default: return "Klidné"
        }
    }
    public var throwTempoText: String {
        let seconds = throwSeconds.formatted(.number.precision(.fractionLength(1)))
        return "\(throwTempoLabel) · ~\(seconds) s"
    }
}

/// Veřejně zobrazované odhady výkonu bota. Level 10 sedí na průměrném PDC profíkovi.
private struct BotStatProfile {
    var averageLow: Int
    var averageHigh: Int
    var checkoutLow: Int
    var checkoutHigh: Int
    var oneEightiesPerLeg: Double
    var throwSeconds: Double

    static func forLevel(_ level: Int) -> BotStatProfile {
        let index = min(9, max(0, level - 1))
        return ladder[index]
    }

    /// Od začátečníka po průměrného tour profíka. Ne elite 100+ avg.
    private static let ladder: [BotStatProfile] = [
        .init(averageLow: 18, averageHigh: 28, checkoutLow: 3, checkoutHigh: 8, oneEightiesPerLeg: 0.02, throwSeconds: 2.6),
        .init(averageLow: 24, averageHigh: 34, checkoutLow: 5, checkoutHigh: 12, oneEightiesPerLeg: 0.04, throwSeconds: 2.4),
        .init(averageLow: 32, averageHigh: 42, checkoutLow: 8, checkoutHigh: 16, oneEightiesPerLeg: 0.06, throwSeconds: 2.2),
        .init(averageLow: 40, averageHigh: 50, checkoutLow: 12, checkoutHigh: 22, oneEightiesPerLeg: 0.08, throwSeconds: 1.8),
        .init(averageLow: 52, averageHigh: 62, checkoutLow: 18, checkoutHigh: 28, oneEightiesPerLeg: 0.12, throwSeconds: 1.5),
        .init(averageLow: 62, averageHigh: 72, checkoutLow: 24, checkoutHigh: 34, oneEightiesPerLeg: 0.18, throwSeconds: 1.3),
        .init(averageLow: 72, averageHigh: 82, checkoutLow: 30, checkoutHigh: 38, oneEightiesPerLeg: 0.22, throwSeconds: 1.1),
        .init(averageLow: 82, averageHigh: 90, checkoutLow: 34, checkoutHigh: 42, oneEightiesPerLeg: 0.26, throwSeconds: 0.9),
        .init(averageLow: 88, averageHigh: 95, checkoutLow: 38, checkoutHigh: 44, oneEightiesPerLeg: 0.30, throwSeconds: 0.8),
        // Lv. 10 — průměrný PDC ProTour / TV pro (ne Humphries/Littler 100+)
        .init(averageLow: 92, averageHigh: 98, checkoutLow: 40, checkoutHigh: 45, oneEightiesPerLeg: 0.32, throwSeconds: 0.7)
    ]
}
public enum Bot {
    private static let board = [20,1,18,4,13,6,10,15,2,17,3,19,7,16,8,11,14,9,12,5]
    public static func target(in game: Match, dartsLeft: Int) -> Dart {
        let state = game.currentState
        switch game.config.mode {
        case .x01:
            if !state.opened { return Dart(20, 2) }
            if let route = Checkout.route(for: state.remaining, rule: game.config.outRule(for: game.active), darts: dartsLeft) { return route[0] }
            if state.remaining > 60 { return Dart(20,3) }
            // Leave a familiar double; never deliberately strand one.
            let safe = state.remaining - 32
            if (1...20).contains(safe) { return Dart(safe) }
            return Dart(state.remaining > 40 ? 20 : max(1, state.remaining - 2))
        case .cricket:
            let numbers = [20,19,18,17,16,15,25]
            if let open = numbers.first(where: { state.marks[$0, default: 0] < 3 }) { return Dart(open, open == 25 ? 2 : 3) }
            if let scoring = numbers.first(where: { n in game.states.indices.contains { $0 != game.active && game.states[$0].marks[n, default: 0] < 3 } }) { return Dart(scoring, scoring == 25 ? 2 : 3) }
            return Dart(25,2)
        case .aroundClock:
            if state.clockTarget == 21 { return Dart(25, game.config.settings.clockStyle == .any ? 1 : 2) }
            return Dart(min(20,state.clockTarget), game.config.settings.clockStyle == .any ? 1 : game.config.settings.clockStyle == .doubles ? 2 : 3)
        case .countUp: return Dart(20,3)
        }
    }
    public static func throwDart<R: RandomNumberGenerator>(at target: Dart, level: Int, using rng: inout R) -> Dart {
        let p = BotLevel.get(level).precision
        let exact = target.multiplier == 1 ? min(0.98, p + 0.25) : target.multiplier == 2 ? p * 0.9 + 0.05 : p
        if Double.random(in: 0..<1, using: &rng) < exact { return target }
        let miss = Double.random(in: 0..<1, using: &rng)
        if miss < 0.38 - p * 0.40 { return .miss }
        if target.segment == 25 { return miss < 0.58 ? Dart(25) : Dart(Int.random(in: 1...20, using: &rng)) }
        if miss < 0.64 { return Dart(target.segment) }
        let index = board.firstIndex(of: target.segment) ?? 0
        let offset = Bool.random(using: &rng) ? 1 : 19
        return Dart(board[(index + offset) % 20], miss > 0.94 ? target.multiplier : 1)
    }
    public static func visit<R: RandomNumberGenerator>(in game: Match, using rng: inout R) -> [Dart] {
        var darts: [Dart] = []
        for _ in 0..<3 {
            var simulated = game
            if !darts.isEmpty {
                try? simulated.submit(darts, allowPartial: true)
                if simulated.visits.last?.bust == true || simulated.legWinner != nil { break }
                simulated.active = game.active
            }
            darts.append(throwDart(at: target(in: simulated, dartsLeft: 3 - darts.count), level: game.currentPlayer.botLevel ?? 1, using: &rng))
        }
        return darts
    }
}
