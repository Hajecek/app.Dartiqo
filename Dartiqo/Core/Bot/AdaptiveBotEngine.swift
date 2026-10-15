import Foundation

/// Volba úrovně podle posledních legů hráče. Mění se mezi zápasy, ne během hodu.
public struct AdaptiveReading: Equatable {
    public var legs: Int
    public var threeDartAverage: Double
    public var first9Average: Double
    public var checkoutPercentage: Double
    public var dartsPerLeg: Double
    public var stability: Double
    public var recentWinRate: Double?
    public var recommendedLevel: Int
}

public enum AdaptiveBotEngine {
    public static let sampleSize = 20
    /// Bez historie ať nováček nedostane soupeře, který ho umaže.
    public static let fallbackLevel = 4

    public static func level(forThreeDartAverage average: Double) -> Int {
        guard average.isFinite else { return 1 }
        let raw = Int(((average - 12.5) / 5).rounded())
        return min(BotDifficulty.count, max(1, raw))
    }

    /// ±1 podle posledních výsledků. Nestabilní hráč nedostane příplatek navíc.
    public static func challenge(base: Int, recentWinRate: Double?, unstable: Bool) -> Int {
        var level = min(BotDifficulty.count, max(1, base))
        guard let recentWinRate, !unstable else { return level }
        if recentWinRate >= 0.60 { level += 1 }
        if recentWinRate <= 0.35 { level -= 1 }
        return min(BotDifficulty.count, max(1, level))
    }

    public static func reading(matches: [Match], playerID: UUID, limit: Int = sampleSize) -> AdaptiveReading {
        var samples: [LegSample] = []
        let ordered = matches.sorted { ($0.completedAt ?? $0.createdAt) > ($1.completedAt ?? $1.createdAt) }
        for match in ordered where match.config.mode == .x01 {
            guard let player = match.players.firstIndex(where: { $0.id == playerID }) else { continue }
            let legs = Set(match.visits.filter { $0.player == player }.map(\.leg)).sorted(by: >)
            for leg in legs {
                guard samples.count < limit else { break }
                guard let sample = LegSample.make(match: match, player: player, leg: leg) else { continue }
                samples.append(sample)
            }
            if samples.count >= limit { break }
        }
        guard samples.count >= 3 else {
            return AdaptiveReading(
                legs: samples.count,
                threeDartAverage: 0,
                first9Average: 0,
                checkoutPercentage: 0,
                dartsPerLeg: 0,
                stability: 0,
                recentWinRate: nil,
                recommendedLevel: fallbackLevel
            )
        }
        let darts = samples.reduce(0) { $0 + $1.darts }
        let points = samples.reduce(0) { $0 + $1.points }
        let average = darts == 0 ? 0 : Double(points) * 3 / Double(darts)
        let first9Darts = samples.reduce(0) { $0 + $1.first9Darts }
        let first9Points = samples.reduce(0) { $0 + $1.first9Points }
        let first9 = first9Darts == 0 ? average : Double(first9Points) * 3 / Double(first9Darts)
        let attempts = samples.reduce(0) { $0 + $1.checkoutAttempts }
        let hits = samples.reduce(0) { $0 + $1.checkoutHits }
        let checkout = attempts == 0 ? 0 : Double(hits) / Double(attempts) * 100
        let perLeg = Double(darts) / Double(samples.count)
        let legAverages = samples.map { $0.darts == 0 ? 0 : Double($0.points) * 3 / Double($0.darts) }
        let mean = legAverages.reduce(0, +) / Double(legAverages.count)
        let variance = legAverages.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(legAverages.count)
        let stability = variance.squareRoot()
        let decided = samples.filter { $0.won != nil }
        let winRate = decided.isEmpty ? nil : Double(decided.filter { $0.won == true }.count) / Double(decided.count)
        var skill = average
        if first9 > average + 10 { skill = average * 0.75 + first9 * 0.25 }
        let base = level(forThreeDartAverage: skill)
        let recommended = challenge(base: base, recentWinRate: winRate, unstable: stability > 18)
        return AdaptiveReading(
            legs: samples.count,
            threeDartAverage: average,
            first9Average: first9,
            checkoutPercentage: checkout,
            dartsPerLeg: perLeg,
            stability: stability,
            recentWinRate: winRate,
            recommendedLevel: recommended
        )
    }

    public static func recommendedLevel(matches: [Match], playerID: UUID) -> Int {
        reading(matches: matches, playerID: playerID).recommendedLevel
    }

    private struct LegSample {
        var points: Int
        var darts: Int
        var first9Points: Int
        var first9Darts: Int
        var checkoutAttempts: Int
        var checkoutHits: Int
        var won: Bool?

        static func make(match: Match, player: Int, leg: Int) -> LegSample? {
            let mine = match.visits.filter { $0.player == player && $0.leg == leg }
            guard !mine.isEmpty else { return nil }
            let completed = match.visits.contains { $0.leg == leg && $0.checkout } || match.bullOffLegs?[leg] != nil
            guard completed else { return nil }
            let winner = match.bullOffLegs?[leg] ?? match.visits.last { $0.leg == leg && $0.checkout }?.player
            let opening = mine.prefix(3)
            let finish = CheckoutStats.make(from: match, player: player, leg: leg)
            return LegSample(
                points: mine.reduce(0) { $0 + $1.credited },
                darts: mine.reduce(0) { $0 + $1.darts.count },
                first9Points: opening.reduce(0) { $0 + $1.credited },
                first9Darts: opening.reduce(0) { $0 + $1.darts.count },
                checkoutAttempts: finish.attempts,
                checkoutHits: finish.hits,
                won: winner.map { $0 == player }
            )
        }
    }
}
