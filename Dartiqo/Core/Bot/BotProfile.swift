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
    /// Cílový tříšipkový průměr vlastního bota. Spolu s `customCheckout` zapne vlastní profil.
    public var customAverage: Double?
    /// Cílová úspěšnost mířeného double, 0…1.
    public var customCheckout: Double?
    public var customName: String?
    /// 0…1. `nil` nechá stabilitu ze stylu a průměru.
    public var customConsistency: Double?
    public var customPressure: Double?
    public var customIntelligence: Double?
    public var isCustom: Bool { customAverage != nil && customCheckout != nil }

    public init(
        level: Int,
        style: BotPlayingStyle = .balanced,
        adaptive: Bool = false,
        customAverage: Double? = nil,
        customCheckout: Double? = nil,
        customName: String? = nil,
        customConsistency: Double? = nil,
        customPressure: Double? = nil,
        customIntelligence: Double? = nil
    ) {
        self.level = min(BotDifficulty.count, max(1, level))
        self.style = style
        self.adaptive = adaptive
        if let customAverage, let customCheckout {
            self.customAverage = min(BotDifficulty.maximumAverage, max(BotDifficulty.minimumAverage, customAverage))
            self.customCheckout = min(BotDifficulty.maximumCheckout, max(BotDifficulty.minimumCheckout, customCheckout))
            self.customName = SeatDraft.customBotName(customName)
            self.customConsistency = customConsistency.map { min(1, max(0, $0)) }
            self.customPressure = customPressure.map { min(1, max(0, $0)) }
            self.customIntelligence = customIntelligence.map { min(1, max(0, $0)) }
            self.adaptive = false
            self.level = BotDifficulty.nearestLevel(forAverage: self.customAverage ?? customAverage)
        } else {
            self.customAverage = nil
            self.customCheckout = nil
            self.customName = nil
            self.customConsistency = nil
            self.customPressure = nil
            self.customIntelligence = nil
        }
    }
}

/// Soupeř tak, jak nastoupí. Vlastní průměr a double mají přednost před Adaptive AI.
public struct ResolvedBot: Equatable {
    public var level: Int
    public var adaptive: Bool
    public var style: BotPlayingStyle
    public var average: Double?
    public var checkout: Double?
    public var consistency: Double?
    public var pressure: Double?
    public var intelligence: Double?
    public var isCustom: Bool { average != nil && checkout != nil }
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
        let tuned = shape(
            Knobs(
                triple: spec.tripleSigma,
                double: spec.doubleSigma,
                single: spec.singleSigma,
                bull: spec.bullSigma,
                consistency: spec.consistency,
                intelligence: spec.intelligence,
                pressure: spec.pressureResistance,
                scoring: Dart(20, 3),
                doubles: standardDoubles
            ),
            style: style,
            identity: identity,
            lockAccuracy: false
        )
        return assemble(
            id: "\(spec.level)-\(style.rawValue)-\(identity)",
            name: spec.persona,
            level: spec.level,
            style: style,
            average: spec.targetAverage,
            checkout: spec.targetDoubleHit,
            knobs: tuned
        )
    }

    /// Vlastní soupeř. Double řídí zavírání, skórovací rozptyl se dopočítá tak, aby celý leg seděl na průměr.
    /// Styl k tomu přidá způsob hry a čísla neposouvá.
    public static func custom(
        average: Double,
        checkout: Double,
        style: BotPlayingStyle = .balanced,
        name: String = "Vlastní",
        consistency: Double? = nil,
        pressure: Double? = nil,
        intelligence: Double? = nil
    ) -> BotProfile {
        let average = min(BotDifficulty.maximumAverage, max(BotDifficulty.minimumAverage, average))
        let checkout = min(BotDifficulty.maximumCheckout, max(BotDifficulty.minimumCheckout, checkout))
        let persona = BotDifficulty.blend(at: BotDifficulty.index(forAverage: average))
        let scoring = BotDifficulty.scoringSigma(at: BotDifficulty.scoringIndex(forAverage: average, checkout: checkout))
        let finishing = BotDifficulty.finishingSpread(forCheckout: checkout)
        var tuned = shape(
            Knobs(
                triple: scoring,
                double: finishing.doubleSigma,
                single: scoring,
                bull: finishing.bullSigma,
                consistency: persona.consistency,
                intelligence: persona.intelligence,
                pressure: persona.pressureResistance,
                scoring: Dart(20, 3),
                doubles: standardDoubles
            ),
            style: style,
            identity: 0,
            lockAccuracy: true
        )
        if let consistency { tuned.consistency = min(1, max(0, consistency)) }
        if let pressure { tuned.pressure = min(1, max(0, pressure)) }
        if let intelligence { tuned.intelligence = min(1, max(0, intelligence)) }
        return assemble(
            id: "custom-\(style.rawValue)",
            name: name,
            level: BotDifficulty.nearestLevel(forAverage: average),
            style: style,
            average: average,
            checkout: checkout,
            knobs: tuned
        )
    }

    public static func from(player: Player) -> BotProfile {
        let style = player.botStyle ?? .balanced
        if let average = player.botAverage, let checkout = player.botCheckout {
            return custom(
                average: average,
                checkout: checkout,
                style: style,
                name: player.name,
                consistency: player.botConsistency,
                pressure: player.botPressure,
                intelligence: player.botIntelligence
            )
        }
        guard let level = player.botLevel else { return reference(level: 1) }
        let identity = player.id.uuidString.utf8.reduce(UInt64(1469598103934665603)) { ($0 ^ UInt64($1)) &* 1099511628211 }
        return make(level: level, style: style, identity: identity)
    }

    private struct Knobs {
        var triple: Double
        var double: Double
        var single: Double
        var bull: Double
        var consistency: Double
        var intelligence: Double
        var pressure: Double
        var scoring: Dart
        var doubles: [Int]
    }

    /// `lockAccuracy` nechá průměr a double na nastavených číslech. Styl pořád mění výkyvy, hlavu a oblíbená pole.
    private static func shape(_ base: Knobs, style: BotPlayingStyle, identity: UInt64, lockAccuracy: Bool) -> Knobs {
        var triple = base.triple
        var double = base.double
        var single = base.single
        var bull = base.bull
        var consistency = base.consistency
        var intelligence = base.intelligence
        let pressure = base.pressure
        var scoring = base.scoring
        var doubles = base.doubles

        switch style {
        case .balanced:
            break
        case .scoringSpecialist:
            if !lockAccuracy {
                triple *= 0.90
                single *= 0.92
                double *= 1.20
                bull *= 1.12
            }
            intelligence *= 0.92
        case .checkoutSpecialist:
            if !lockAccuracy {
                triple *= 1.10
                single *= 1.05
                double *= 0.82
                bull *= 0.86
            }
            intelligence = min(0.98, intelligence + 0.08)
            doubles = [16, 20, 8, 10, 4, 2, 12, 18, 6, 14, 5, 9, 11, 13, 15, 17, 19, 7, 3, 1]
        case .consistent:
            consistency = min(0.97, consistency + 0.18)
        case .aggressive:
            if !lockAccuracy { triple *= 0.97 }
            intelligence *= 0.82
            scoring = Dart(20, 3)
        case .tactical:
            intelligence = min(0.98, intelligence + 0.12)
            if !lockAccuracy { triple *= 1.02 }
            doubles = [20, 16, 18, 10, 8, 4, 2, 12, 6, 14, 5, 9, 11, 13, 15, 17, 19, 7, 3, 1]
        case .unpredictable:
            // Výkyvy formy samy srazí průměr, přesnost proto zůstává podle úrovně.
            consistency = max(0.12, consistency - 0.30)
        }

        if identity != 0 && !lockAccuracy {
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

        return Knobs(
            triple: triple,
            double: double,
            single: single,
            bull: bull,
            consistency: consistency,
            intelligence: intelligence,
            pressure: pressure,
            scoring: scoring,
            doubles: doubles
        )
    }

    private static func assemble(
        id: String,
        name: String,
        level: Int,
        style: BotPlayingStyle,
        average: Double,
        checkout: Double,
        knobs: Knobs
    ) -> BotProfile {
        let aim = knobs.triple * BotThrowModel.aimShare
        return BotProfile(
            id: id,
            name: name,
            level: level,
            style: style,
            targetAverage: average,
            targetDoubleHit: checkout,
            scoringAccuracy: checkout,
            tripleAccuracy: checkout,
            doubleAccuracy: checkout,
            bullAccuracy: checkout * 0.72,
            horizontalDispersion: knobs.triple * BotThrowModel.horizontalScale,
            verticalDispersion: knobs.triple * BotThrowModel.verticalScale,
            consistency: knobs.consistency,
            checkoutIntelligence: knobs.intelligence,
            pressureResistance: knobs.pressure,
            aimError: aim,
            preferredScoringTarget: knobs.scoring,
            preferredDoubles: knobs.doubles,
            tripleSigma: knobs.triple,
            doubleSigma: knobs.double,
            singleSigma: knobs.single,
            bullSigma: knobs.bull,
            horizontalScale: BotThrowModel.horizontalScale,
            verticalScale: BotThrowModel.verticalScale
        )
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
