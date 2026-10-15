import Foundation

/// Herní styl. Stejná úroveň proto nemusí hrát stejně.
public enum BotPlayingStyle: String, Codable, CaseIterable, Identifiable {
    case balanced
    case scoringSpecialist
    case checkoutSpecialist
    case consistent
    case aggressive
    case tactical
    case unpredictable

    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .balanced: return "Vyrovnaný"
        case .scoringSpecialist: return "Skórovací specialista"
        case .checkoutSpecialist: return "Specialista na zavírání"
        case .consistent: return "Stabilní hráč"
        case .aggressive: return "Agresivní hráč"
        case .tactical: return "Taktický hráč"
        case .unpredictable: return "Nepředvídatelný"
        }
    }
    public var detail: String {
        switch self {
        case .balanced: return "Skóre i zavírání podle úrovně."
        case .scoringSpecialist: return "Silné skóre, slabší double."
        case .checkoutSpecialist: return "Nižší skóre, jistější zavírání."
        case .consistent: return "Menší výkyvy mezi koly."
        case .aggressive: return "Míří na vysoké scoringové cíle."
        case .tactical: return "Připravuje si výhodné zavření."
        case .unpredictable: return "Velké rozdíly mezi návštěvami."
        }
    }
}

/// Volba soupeře před zápasem.
public struct BotChoice: Equatable {
    public var level: Int
    public var style: BotPlayingStyle
    public var adaptive: Bool
    public init(level: Int, style: BotPlayingStyle = .balanced, adaptive: Bool = false) {
        self.level = min(BotDifficulty.count, max(1, level))
        self.style = style
        self.adaptive = adaptive
    }
}

/// Individuální bot. Přesnost je rozptyl hodu, ne předem dané skóre návštěvy.
public struct BotProfile: Identifiable, Equatable {
    public var id: String
    public var name: String
    public var level: Int
    public var style: BotPlayingStyle
    public var targetAverage: Double
    public var targetDoubleHit: Double
    /// Pravděpodobnost zásahu mířeného singlu / triple / double / bull u referenčního profilu úrovně.
    public var scoringAccuracy: Double
    public var tripleAccuracy: Double
    public var doubleAccuracy: Double
    public var bullAccuracy: Double
    public var horizontalDispersion: Double
    public var verticalDispersion: Double
    public var consistency: Double
    public var checkoutIntelligence: Double
    public var pressureResistance: Double
    public var aimError: Double
    public var preferredScoringTarget: Dart
    public var preferredDoubles: [Int]

    var tripleSigma: Double
    var doubleSigma: Double
    var singleSigma: Double
    var bullSigma: Double
    var horizontalScale: Double
    var verticalScale: Double

    public static let standardDoubles = [20, 16, 8, 4, 2, 18, 12, 10, 6, 14, 5, 9, 11, 13, 15, 17, 19, 7, 3, 1]

    func sigma(for target: Dart) -> Double {
        if target.segment == 25 { return bullSigma }
        switch target.multiplier {
        case 3: return tripleSigma
        case 2: return doubleSigma
        default: return singleSigma
        }
    }

    /// Referenční profil úrovně bez osobního rozptylu. Používá ho kalibrace.
    public static func reference(level: Int, style: BotPlayingStyle = .balanced) -> BotProfile {
        make(level: level, style: style, identity: 0)
    }

    /// `identity` 0 je čistá úroveň. Jinak dva boti stejné úrovně dostanou mírně jiné rozptyly a doubly.
    public static func make(level: Int, style: BotPlayingStyle = .balanced, identity: UInt64 = 0) -> BotProfile {
        let spec = BotDifficulty.level(level)
        var triple = spec.tripleSigma
        var double = spec.doubleSigma
        var single = spec.singleSigma
        var bull = spec.bullSigma
        var consistency = spec.consistency
        var intelligence = spec.intelligence
        var pressure = spec.pressureResistance
        var scoring = Dart(20, 3)
        var doubles = standardDoubles

        switch style {
        case .balanced:
            break
        case .scoringSpecialist:
            triple *= 0.90
            single *= 0.92
            double *= 1.20
            bull *= 1.12
            intelligence *= 0.92
        case .checkoutSpecialist:
            triple *= 1.16
            single *= 1.08
            double *= 0.82
            bull *= 0.86
            intelligence = min(0.98, intelligence + 0.08)
            doubles = [16, 20, 8, 10, 4, 2, 12, 18, 6, 14, 5, 9, 11, 13, 15, 17, 19, 7, 3, 1]
        case .consistent:
            consistency = min(0.97, consistency + 0.18)
        case .aggressive:
            triple *= 0.94
            intelligence *= 0.82
            scoring = Dart(20, 3)
        case .tactical:
            intelligence = min(0.98, intelligence + 0.12)
            triple *= 1.04
            doubles = [20, 16, 18, 10, 8, 4, 2, 12, 6, 14, 5, 9, 11, 13, 15, 17, 19, 7, 3, 1]
        case .unpredictable:
            consistency = max(0.12, consistency - 0.30)
            triple *= 1.04
            double *= 1.05
        }

        if identity != 0 {
            var rng = BotRNG(seed: identity)
            let tilt = 0.94 + Double.random(in: 0..<0.12, using: &rng)
            triple *= tilt
            single *= tilt
            double *= (2 - tilt)
            bull *= (2 - tilt)
            let swapA = Int.random(in: 0..<4, using: &rng)
            let swapB = Int.random(in: 0..<6, using: &rng)
            if swapA != swapB { doubles.swapAt(swapA, swapB) }
            if style == .unpredictable {
                let options = [20, 19, 18, 17]
                scoring = Dart(options[Int.random(in: 0..<options.count, using: &rng)], 3)
            }
        }

        let aim = triple * BotThrowModel.aimShare
        return BotProfile(
            id: "\(spec.level)-\(style.rawValue)-\(identity)",
            name: spec.persona,
            level: spec.level,
            style: style,
            targetAverage: spec.targetAverage,
            targetDoubleHit: spec.targetDoubleHit,
            scoringAccuracy: spec.targetDoubleHit,
            tripleAccuracy: spec.targetDoubleHit,
            doubleAccuracy: spec.targetDoubleHit,
            bullAccuracy: spec.targetDoubleHit * 0.72,
            horizontalDispersion: triple * BotThrowModel.horizontalScale,
            verticalDispersion: triple * BotThrowModel.verticalScale,
            consistency: consistency,
            checkoutIntelligence: intelligence,
            pressureResistance: pressure,
            aimError: aim,
            preferredScoringTarget: scoring,
            preferredDoubles: doubles,
            tripleSigma: triple,
            doubleSigma: double,
            singleSigma: single,
            bullSigma: bull,
            horizontalScale: BotThrowModel.horizontalScale,
            verticalScale: BotThrowModel.verticalScale
        )
    }

    public static func from(player: Player) -> BotProfile {
        guard let level = player.botLevel else { return reference(level: 1) }
        let identity = player.id.uuidString.utf8.reduce(UInt64(1469598103934665603)) { ($0 ^ UInt64($1)) &* 1099511628211 }
        return make(level: level, style: player.botStyle ?? .balanced, identity: identity)
    }
}

/// Seedovatelný generátor pro reprodukovatelné simulace.
public struct BotRNG: RandomNumberGenerator {
    public var state: UInt64
    public init(seed: UInt64) {
        self.state = seed == 0 ? 0x9E3779B97F4A7C15 : seed
    }
    public mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}

enum Gaussian {
    static func sample<R: RandomNumberGenerator>(_ rng: inout R) -> Double {
        let u1 = Double.random(in: Double.leastNonzeroMagnitude..<1, using: &rng)
        let u2 = Double.random(in: 0..<1, using: &rng)
        return (-2 * log(u1)).squareRoot() * cos(2 * Double.pi * u2)
    }
}
