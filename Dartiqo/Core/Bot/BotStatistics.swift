import Foundation

/// Statistiky bota ze skutečných návštěv. Stejná pravidla jako u člověka, bez druhého počítadla.
public struct BotStatistics: Equatable {
    public var threeDartAverage: Double
    public var first9Average: Double
    public var checkoutPercentage: Double?
    public var checkoutAttempts: Int
    public var highestCheckout: Int
    public var bestLegDarts: Int?
    public var worstLegDarts: Int?
    public var count100: Int
    public var count140: Int
    public var count180: Int
    public var busts: Int
    public var darts: Int
    public var legsWon: Int
    public var legsLost: Int
    public var setsWon: Int
    public var setsLost: Int

    public static func make(from match: Match, player: Int) -> BotStatistics {
        let mine = match.visits.filter { $0.player == player }
        let darts = mine.reduce(0) { $0 + $1.darts.count }
        let points = mine.reduce(0) { $0 + $1.credited }
        var first9Points = 0
        var first9Darts = 0
        var best: Int?
        var worst: Int?
        var wonLegs = Set<Int>()
        for leg in Set(mine.map(\.leg)) {
            let opening = mine.filter { $0.leg == leg }.prefix(3)
            first9Points += opening.reduce(0) { $0 + $1.credited }
            first9Darts += opening.reduce(0) { $0 + $1.darts.count }
            if mine.contains(where: { $0.leg == leg && $0.checkout }) {
                wonLegs.insert(leg)
                let used = mine.filter { $0.leg == leg }.reduce(0) { $0 + $1.darts.count }
                best = min(best ?? used, used)
                worst = max(worst ?? used, used)
            }
        }
        let checkout = CheckoutStats.make(from: match, player: player)
        var n100 = 0, n140 = 0, n180 = 0
        for visit in mine {
            switch visit.credited {
            case 180: n180 += 1
            case 140..<180: n140 += 1
            case 100..<140: n100 += 1
            default: break
            }
        }
        let completed = Set(match.visits.filter(\.checkout).map(\.leg)).union(match.bullOffLegs?.keys.map { $0 } ?? [])
        let lost = completed.filter { leg in
            let winner = match.bullOffLegs?[leg] ?? match.visits.last { $0.leg == leg && $0.checkout }?.player
            return winner != player && mine.contains { $0.leg == leg }
        }.count
        let mySets = match.states.indices.contains(player) ? match.states[player].sets : 0
        let theirSets = match.states.enumerated().filter { $0.offset != player }.map(\.element.sets).max() ?? 0
        return BotStatistics(
            threeDartAverage: darts == 0 ? 0 : Double(points) * 3 / Double(darts),
            first9Average: first9Darts == 0 ? 0 : Double(first9Points) * 3 / Double(first9Darts),
            checkoutPercentage: checkout.percentage,
            checkoutAttempts: checkout.attempts,
            highestCheckout: checkout.highest,
            bestLegDarts: best,
            worstLegDarts: worst,
            count100: n100,
            count140: n140,
            count180: n180,
            busts: mine.filter(\.bust).count,
            darts: darts,
            legsWon: wonLegs.count + (match.bullOffLegs?.values.filter { $0 == player }.count ?? 0),
            legsLost: lost,
            setsWon: mySets,
            setsLost: theirSets
        )
    }
}
