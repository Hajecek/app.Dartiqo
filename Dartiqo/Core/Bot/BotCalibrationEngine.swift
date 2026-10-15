import Foundation

/// Výsledek dávky legů. Slouží ke kalibraci, ne během zápasu.
public struct BotCalibrationReport: Equatable {
    public var level: Int
    public var style: BotPlayingStyle
    public var legs: Int
    public var threeDartAverage: Double
    public var targetAverage: Double
    public var doubleHitRate: Double
    public var targetDoubleHit: Double
    public var first9Average: Double
    public var dartsPerLeg: Double
    public var perLeg180: Double
    public var bustsPerLeg: Double
    public var checkoutPercentage: Double
    public var highestCheckout: Int
    public var visitSpread: Double
    public var averageError: Double { threeDartAverage - targetAverage }
    public var doubleError: Double { doubleHitRate - targetDoubleHit }
}

/// Oddělené od živé hry. Legy jedou přes stejný zápasový engine a seedovatelný generátor.
public enum BotCalibrationEngine {
    /// Úspěšnost šipky mířené na D20, včetně výkyvů formy. Není to procento zavřených legů.
    public static func doubleHitRate(
        level: Int,
        style: BotPlayingStyle = .balanced,
        attempts: Int = 4_000,
        seed: UInt64 = 1
    ) -> Double {
        let profile = BotProfile.reference(level: level, style: style)
        var rng = BotRNG(seed: seed)
        var hits = 0
        var form = BotVisitForm.neutral
        let count = max(1, attempts)
        for index in 0..<count {
            if index % 3 == 0 { form = BotFormEngine.sample(consistency: profile.consistency, using: &rng) }
            let shot = DartThrowSimulator.throw(at: Dart(20, 2), profile: profile, form: form, using: &rng)
            if shot == Dart(20, 2) { hits += 1 }
        }
        return Double(hits) / Double(count)
    }

    /// X01. Každý leg je samostatný zápas, ať se statistiky nesčítají dvakrát a undo stack neroste.
    public static func simulate(
        level: Int,
        style: BotPlayingStyle = .balanced,
        legs: Int,
        seed: UInt64 = 1,
        startingScore: Int = 501,
        rule: OutRule = .double
    ) -> BotCalibrationReport {
        let profile = BotProfile.reference(level: level, style: style)
        var rng = BotRNG(seed: seed)
        var points = 0
        var darts = 0
        var first9Points = 0
        var first9Darts = 0
        var aimedDoubles = 0
        var hitDoubles = 0
        var totals180 = 0
        var busts = 0
        var checkout = CheckoutStats()
        var legAverages: [Double] = []
        let play = max(1, legs)

        for index in 0..<play {
            var match = Match(
                config: GameConfig(mode: .x01, startingScore: startingScore, outRule: rule, legsToWin: 1),
                players: [Player(id: stableID(seed, UInt64(index) &+ 1), name: profile.name, botLevel: level, botStyle: style)]
            )
            match.id = stableID(seed ^ 0xA5A5, UInt64(index) &+ 99)
            var guardVisits = 0
            while !match.finished && guardVisits < 4_000 {
                let shots = BotGameController.simulateVisit(in: match, profile: profile, using: &rng)
                guard !shots.isEmpty else { break }
                for shot in shots where shot.aim.multiplier == 2 {
                    aimedDoubles += 1
                    if shot.result == shot.aim { hitDoubles += 1 }
                }
                try? match.submit(shots.map(\.result))
                guardVisits += 1
            }
            let legPoints = match.visits.reduce(0) { $0 + $1.credited }
            let legDarts = match.visits.reduce(0) { $0 + $1.darts.count }
            points += legPoints
            darts += legDarts
            let opening = match.visits.prefix(3)
            first9Points += opening.reduce(0) { $0 + $1.credited }
            first9Darts += opening.reduce(0) { $0 + $1.darts.count }
            totals180 += match.visits.filter { $0.credited == 180 }.count
            busts += match.visits.filter(\.bust).count
            checkout.merge(CheckoutStats.make(from: match, player: 0))
            if legDarts > 0 { legAverages.append(Double(legPoints) * 3 / Double(legDarts)) }
        }

        let mean = legAverages.isEmpty ? 0 : legAverages.reduce(0, +) / Double(legAverages.count)
        let variance = legAverages.isEmpty ? 0 : legAverages.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(legAverages.count)
        return BotCalibrationReport(
            level: profile.level,
            style: style,
            legs: play,
            threeDartAverage: darts == 0 ? 0 : Double(points) * 3 / Double(darts),
            targetAverage: profile.targetAverage,
            doubleHitRate: aimedDoubles == 0 ? 0 : Double(hitDoubles) / Double(aimedDoubles),
            targetDoubleHit: profile.targetDoubleHit,
            first9Average: first9Darts == 0 ? 0 : Double(first9Points) * 3 / Double(first9Darts),
            dartsPerLeg: Double(darts) / Double(play),
            perLeg180: Double(totals180) / Double(play),
            bustsPerLeg: Double(busts) / Double(play),
            checkoutPercentage: checkout.percentage ?? 0,
            highestCheckout: checkout.highest,
            visitSpread: variance.squareRoot()
        )
    }

    static func stableID(_ high: UInt64, _ low: UInt64) -> UUID {
        UUID(uuid: (
            UInt8(truncatingIfNeeded: high >> 56), UInt8(truncatingIfNeeded: high >> 48),
            UInt8(truncatingIfNeeded: high >> 40), UInt8(truncatingIfNeeded: high >> 32),
            UInt8(truncatingIfNeeded: high >> 24), UInt8(truncatingIfNeeded: high >> 16),
            UInt8(truncatingIfNeeded: high >> 8), UInt8(truncatingIfNeeded: high),
            UInt8(truncatingIfNeeded: low >> 56), UInt8(truncatingIfNeeded: low >> 48),
            UInt8(truncatingIfNeeded: low >> 40), UInt8(truncatingIfNeeded: low >> 32),
            UInt8(truncatingIfNeeded: low >> 24), UInt8(truncatingIfNeeded: low >> 16),
            UInt8(truncatingIfNeeded: low >> 8), UInt8(truncatingIfNeeded: low)
        ))
    }
}
