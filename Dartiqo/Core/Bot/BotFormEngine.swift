import Foundation

/// Krátkodobá forma jedné návštěvy. Mění rozptyl šipek, ne výsledné skóre.
public struct BotVisitForm: Equatable {
    public var sigmaScale: Double
    public var biasX: Double
    public var biasY: Double
    public static let neutral = BotVisitForm(sigmaScale: 1, biasX: 0, biasY: 0)
}

public enum BotFormEngine {
    /// Forma společná pro tři šipky návštěvy. Vychází ze zápasu, takže se uprostřed kola nemění.
    public static func form(in game: Match, profile: BotProfile) -> BotVisitForm {
        let thrown = game.visits.filter { $0.player == game.active && $0.leg == game.leg }.count
        var rng = BotRNG(seed: visitSeed(matchID: game.id, leg: game.leg, player: game.active, completedVisits: thrown))
        return sample(consistency: profile.consistency, using: &rng)
    }

    public static func visitSeed(matchID: UUID, leg: Int, player: Int, completedVisits: Int) -> UInt64 {
        let u = matchID.uuid
        var mixed = UInt64(u.0) | (UInt64(u.1) << 8) | (UInt64(u.2) << 16) | (UInt64(u.3) << 24)
            | (UInt64(u.4) << 32) | (UInt64(u.5) << 40) | (UInt64(u.6) << 48) | (UInt64(u.7) << 56)
        mixed ^= UInt64(u.8) &* 0x9E3779B97F4A7C15
        mixed ^= UInt64(u.9) &* 0xBF58476D1CE4E5B9
        mixed ^= UInt64(leg) &* 0x94D049BB133111EB
        mixed ^= UInt64(player) &* 0xD1B54A32D192ED03
        mixed ^= UInt64(completedVisits) &* 0x2545F4914F6CDD1D
        return mixed == 0 ? 1 : mixed
    }

    public static func sample<R: RandomNumberGenerator>(consistency: Double, using rng: inout R) -> BotVisitForm {
        let swing = 1 - min(1, max(0, consistency))
        let roll = Double.random(in: 0..<1, using: &rng)
        let raw: Double
        switch roll {
        case ..<0.04: raw = 0.62
        case ..<0.18: raw = 0.80
        case ..<0.74: raw = 1
        case ..<0.92: raw = 1.18
        default: raw = 1.45
        }
        let scale = 1 + (raw - 1) * (0.35 + 0.65 * swing)
        let bias = 0.018 * swing
        return BotVisitForm(
            sigmaScale: scale,
            biasX: Double.random(in: -bias...bias, using: &rng),
            biasY: Double.random(in: -bias...bias, using: &rng)
        )
    }

    /// Mírné zhoršení v závěru. Nemění skóre napřímo a nerozhoduje výsledek předem.
    public static func pressure(in game: Match, profile: BotProfile) -> Double {
        guard game.config.mode == .x01 else { return 1 }
        let remaining = game.currentState.remaining
        var heat = 0.0
        if (2...170).contains(remaining) { heat += 0.4 }
        let rivals = game.states.enumerated().filter { $0.offset != game.active }.map(\.element.remaining)
        if let best = rivals.min(), best <= 100, best < remaining { heat += 0.35 }
        let deciding = game.config.legsToWin > 1 && game.states.filter { $0.legs >= game.config.legsToWin - 1 }.count >= 2
        if deciding { heat += 0.25 }
        heat = min(1, heat)
        let weakness = 1 - min(1, max(0, profile.pressureResistance))
        return 1 + weakness * heat * 0.12
    }
}
