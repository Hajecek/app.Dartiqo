import Foundation

public struct BotLevel: Identifiable {
    public let id: Int
    public let name: String
    public let persona: String
    public let nickname: String
    /// Portrét. Úrovně 11–20 sdílejí deset existujících fotek.
    public var photo: String { "BotLevel\(((id - 1) % 10) + 1)" }

    public static let all: [BotLevel] = BotDifficulty.levels.map {
        BotLevel(id: $0.level, name: $0.name, persona: $0.persona, nickname: $0.nickname)
    }

    public static func get(_ level: Int) -> BotLevel {
        all[min(BotDifficulty.count - 1, max(0, level - 1))]
    }

    private var tuning: BotDifficulty.Level { BotDifficulty.level(id) }

    public var averageLow: Int { Int((tuning.targetAverage - 4).rounded()) }
    public var averageHigh: Int { Int((tuning.targetAverage + 4).rounded()) }
    public var averageText: String { tuning.targetAverage.formatted(.number.precision(.fractionLength(1))) }
    public var checkoutLow: Int { max(1, Int((tuning.targetDoubleHit * 100).rounded()) - 2) }
    public var checkoutHigh: Int { min(99, Int((tuning.targetDoubleHit * 100).rounded()) + 2) }
    public var checkoutText: String { "\(Int((tuning.targetDoubleHit * 100).rounded())) %" }
    public var oneEightiesPerLeg: Double { max(0, (tuning.targetAverage - 50) / 110) }
    public var maxVisitText: String {
        let value = oneEightiesPerLeg.formatted(.number.precision(.fractionLength(oneEightiesPerLeg < 0.1 ? 2 : 1)))
        return "\(value) / leg"
    }
    public var throwSeconds: Double { tuning.throwSeconds }
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

public enum Bot {
    public static func target(in game: Match, dartsLeft: Int) -> Dart {
        BotTargetSelector.deterministicAim(in: game, dartsLeft: dartsLeft)
    }

    /// Rozptyl jedné šipky kolem zvoleného pole. Bez formy návštěvy, ať srovnání úrovní stojí jen na přesnosti.
    public static func throwDart<R: RandomNumberGenerator>(at target: Dart, level: Int, using rng: inout R) -> Dart {
        let profile = BotProfile.reference(level: level)
        return DartThrowSimulator.throw(at: target, profile: profile, form: .neutral, pressure: 1, using: &rng)
    }

    public static func visit<R: RandomNumberGenerator>(in game: Match, using rng: inout R) -> [Dart] {
        BotGameController.visit(in: game, using: &rng)
    }
}
