import Foundation

/// Jedna položka rozkladu XP za dohraný zápas.
public struct MatchXPLine: Identifiable, Equatable {
    public var id: String
    public var title: String
    public var detail: String
    public var symbol: String
    public var amount: Int

    public init(id: String, title: String, detail: String, symbol: String, amount: Int) {
        self.id = id
        self.title = title
        self.detail = detail
        self.symbol = symbol
        self.amount = amount
    }

    public var signedText: String {
        amount > 0 ? "+\(amount)" : "\(amount)"
    }
}

/// Součet XP a řádků „za co“ pro jednoho hráče v zápase.
public struct MatchXPBreakdown: Equatable {
    public var lines: [MatchXPLine]
    public var total: Int { lines.reduce(0) { $0 + $1.amount } }
    public var hasAward: Bool { !lines.isEmpty }

    public init(lines: [MatchXPLine] = []) {
        self.lines = lines.filter { $0.amount != 0 }
    }
}

/// Pásmo od–do s pevnou odměnou XP.
public struct MatchXPBand: Equatable {
    public var from: Double
    /// Horní hranice. `nil` = od `from` výš. U `closed == false` je interval `[from, to)`.
    public var to: Double?
    public var xp: Int
    /// `true` = `[from, to]` včetně (checkout skóre). `false` = `[from, to)`.
    public var closed = false

    public var label: String {
        if let to {
            let upper = closed ? to : to - 1
            return "\(Self.format(from))–\(Self.format(upper))"
        }
        return "\(Self.format(from))+"
    }

    public func contains(_ value: Double) -> Bool {
        guard value >= from else { return false }
        guard let to else { return true }
        return closed ? value <= to : value < to
    }

    private static func format(_ value: Double) -> String {
        value == floor(value) ? "\(Int(value))" : String(format: "%.0f", value)
    }
}

/// XP za zápasy — pásma „od–do = XP“ + trest za prohru.
public enum MatchRewards {
    public static let finishXP = 40
    public static let winXP = 50
    public static let drawXP = 15
    /// Motivace vyhrát: prohra proti soupeři bere XP.
    public static let lossXP = -25

    /// Průměr 3-šipek (X01): 30–39 = 5 XP, 40–49 = 12 XP, …
    public static let averageBands: [MatchXPBand] = [
        MatchXPBand(from: 30, to: 40, xp: 5),
        MatchXPBand(from: 40, to: 50, xp: 12),
        MatchXPBand(from: 50, to: 60, xp: 22),
        MatchXPBand(from: 60, to: 70, xp: 35),
        MatchXPBand(from: 70, to: 80, xp: 50),
        MatchXPBand(from: 80, to: 90, xp: 65),
        MatchXPBand(from: 90, to: nil, xp: 80)
    ]

    /// Úspěšnost zavírání (%): 10–19 = 5 XP, 20–29 = 12 XP, …
    public static let checkoutRateBands: [MatchXPBand] = [
        MatchXPBand(from: 10, to: 20, xp: 5),
        MatchXPBand(from: 20, to: 30, xp: 12),
        MatchXPBand(from: 30, to: 40, xp: 22),
        MatchXPBand(from: 40, to: 50, xp: 35),
        MatchXPBand(from: 50, to: 60, xp: 50),
        MatchXPBand(from: 60, to: nil, xp: 65)
    ]

    /// Výše jednoho checkoutu (včetně hranic).
    public static let checkoutScoreBands: [MatchXPBand] = [
        MatchXPBand(from: 2, to: 40, xp: 8, closed: true),
        MatchXPBand(from: 41, to: 60, xp: 12, closed: true),
        MatchXPBand(from: 61, to: 100, xp: 18, closed: true),
        MatchXPBand(from: 101, to: 140, xp: 28, closed: true),
        MatchXPBand(from: 141, to: 169, xp: 40, closed: true),
        MatchXPBand(from: 170, to: nil, xp: 55, closed: true)
    ]

    /// Nejlepší návštěva v zápase.
    public static let bestVisitBands: [MatchXPBand] = [
        MatchXPBand(from: 60, to: 100, xp: 5),
        MatchXPBand(from: 100, to: 140, xp: 12),
        MatchXPBand(from: 140, to: 180, xp: 22),
        MatchXPBand(from: 180, to: nil, xp: 35)
    ]

    public static func award(match: Match, playerID: UUID) -> MatchXPBreakdown {
        guard let index = match.players.firstIndex(where: { $0.id == playerID }) else {
            return MatchXPBreakdown()
        }
        return award(match: match, player: index)
    }

    public static func award(match: Match, player: Int) -> MatchXPBreakdown {
        guard match.players.indices.contains(player) else { return MatchXPBreakdown() }
        let visits = match.visits.filter { $0.player == player }
        let darts = visits.reduce(0) { $0 + $1.darts.count }
        guard darts > 0 else { return MatchXPBreakdown() }

        var lines: [MatchXPLine] = []

        lines.append(MatchXPLine(
            id: "finish",
            title: "Dohraný zápas",
            detail: "Základ za dokončení · \(match.config.mode.shortTitle)",
            symbol: "flag.checkered",
            amount: finishXP
        ))

        if match.countsForCompetitiveRecord, match.finished {
            if match.winner == player {
                lines.append(MatchXPLine(
                    id: "win",
                    title: "Výhra",
                    detail: competitiveDetail(match, player: player),
                    symbol: "trophy.fill",
                    amount: winXP
                ))
            } else if match.winner == nil {
                lines.append(MatchXPLine(
                    id: "draw",
                    title: "Remíza",
                    detail: competitiveDetail(match, player: player),
                    symbol: "equal.circle.fill",
                    amount: drawXP
                ))
            } else {
                lines.append(MatchXPLine(
                    id: "loss",
                    title: "Prohra",
                    detail: "\(competitiveDetail(match, player: player)) · motivace příště vyhrát",
                    symbol: "xmark.circle.fill",
                    amount: lossXP
                ))
            }
        }

        switch match.config.mode {
        case .x01:
            lines += x01Performance(match: match, player: player, visits: visits)
        case .cricket, .countUp:
            lines += pointsPerformance(match: match, player: player)
        case .aroundClock:
            lines += clockPerformance(match: match, player: player, darts: darts)
        }

        return MatchXPBreakdown(lines: lines)
    }

    // MARK: - X01

    private static func x01Performance(match: Match, player: Int, visits: [Visit]) -> [MatchXPLine] {
        var lines: [MatchXPLine] = []

        let average = match.average(for: player)
        if let band = band(for: average, in: averageBands) {
            lines.append(MatchXPLine(
                id: "average",
                title: "Průměr \(String(format: "%.1f", average))",
                detail: "Pásmo \(band.label) = \(band.xp) XP",
                symbol: "chart.line.uptrend.xyaxis",
                amount: band.xp
            ))
        }

        let finish = CheckoutStats.make(from: match, player: player)
        if finish.attempts > 0, let rate = finish.percentage, let band = band(for: rate, in: checkoutRateBands) {
            lines.append(MatchXPLine(
                id: "checkout-rate",
                title: "Zavírání \(Int(rate.rounded())) %",
                detail: "Pásmo \(band.label) % = \(band.xp) XP · \(finish.hits)/\(finish.attempts)",
                symbol: "percent",
                amount: band.xp
            ))
        }

        let checkouts = visits.filter(\.checkout)
        for (offset, visit) in checkouts.enumerated() {
            let score = Double(visit.credited)
            guard let band = band(for: score, in: checkoutScoreBands) else { continue }
            lines.append(MatchXPLine(
                id: "checkout-\(offset)-\(visit.id.uuidString)",
                title: "Checkout \(visit.credited)",
                detail: "Pásmo \(band.label) = \(band.xp) XP",
                symbol: "flag.fill",
                amount: band.xp
            ))
        }

        let best = match.best(for: player)
        if let band = band(for: Double(best), in: bestVisitBands) {
            lines.append(MatchXPLine(
                id: "best-visit",
                title: "Nejlepší kolo \(best)",
                detail: "Pásmo \(band.label) = \(band.xp) XP",
                symbol: "bolt.fill",
                amount: band.xp
            ))
        }

        let wonLegs = match.states[player].legs
        if wonLegs > 0 {
            let amount = min(24, wonLegs * 8)
            lines.append(MatchXPLine(
                id: "legs",
                title: wonLegs == 1 ? "1 vyhraný leg" : "\(wonLegs) vyhrané legy",
                detail: "+8 XP za leg · max 24 · \(match.config.lengthLine)",
                symbol: "rectangle.split.3x1.fill",
                amount: amount
            ))
        }

        return lines
    }

    // MARK: - Ostatní režimy

    private static let pointsBands: [MatchXPBand] = [
        MatchXPBand(from: 20, to: 50, xp: 8),
        MatchXPBand(from: 50, to: 100, xp: 15),
        MatchXPBand(from: 100, to: 150, xp: 25),
        MatchXPBand(from: 150, to: 200, xp: 35),
        MatchXPBand(from: 200, to: nil, xp: 45)
    ]

    private static func pointsPerformance(match: Match, player: Int) -> [MatchXPLine] {
        let points = match.states[player].points
        guard let band = band(for: Double(points), in: pointsBands) else { return [] }
        return [MatchXPLine(
            id: "points",
            title: "\(points) bodů",
            detail: "Pásmo \(band.label) = \(band.xp) XP",
            symbol: "number",
            amount: band.xp
        )]
    }

    private static let clockBands: [MatchXPBand] = [
        MatchXPBand(from: 5, to: 10, xp: 8),
        MatchXPBand(from: 10, to: 15, xp: 15),
        MatchXPBand(from: 15, to: 20, xp: 22),
        MatchXPBand(from: 20, to: 21, xp: 30),
        MatchXPBand(from: 21, to: nil, xp: 40)
    ]

    private static func clockPerformance(match: Match, player: Int, darts: Int) -> [MatchXPLine] {
        let target = match.states[player].clockTarget
        let progress = Double(min(21, max(0, target >= 21 ? 21 : target - 1)))
        guard progress > 0, let band = band(for: progress, in: clockBands) else { return [] }
        let title = target >= 21 ? "Around the Clock hotovo" : "Postup \(Int(progress))/20"
        return [MatchXPLine(
            id: "clock",
            title: title,
            detail: "Pásmo \(band.label) = \(band.xp) XP · \(darts) šipek",
            symbol: target >= 21 ? "clock.fill" : "clock",
            amount: band.xp
        )]
    }

    private static func band(for value: Double, in bands: [MatchXPBand]) -> MatchXPBand? {
        bands.first { $0.contains(value) }
    }

    private static func competitiveDetail(_ match: Match, player: Int) -> String {
        let legs = match.states.map(\.legs)
        let mine = legs[player]
        let theirs = legs.enumerated().filter { $0.offset != player }.map(\.element).max() ?? 0
        return "\(mine):\(theirs) · \(match.config.lengthLine)"
    }
}
