import Foundation

public enum StatsPeriod: String, CaseIterable, Identifiable {
    case all, today, yesterday, week, month, quarter, year, custom

    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .all: return "Celé období"
        case .today: return "Dnes"
        case .yesterday: return "Včera"
        case .week: return "7 dní"
        case .month: return "30 dní"
        case .quarter: return "90 dní"
        case .year: return "Rok"
        case .custom: return "Vlastní rozsah"
        }
    }
    public var symbol: String {
        switch self {
        case .all: return "infinity"
        case .today: return "sun.max"
        case .yesterday: return "moon"
        case .custom: return "calendar.badge.clock"
        default: return "calendar"
        }
    }
    /// Polootevřený interval [start, end). `nil` = bez omezení. U `.custom` se počítá s celými dny `from`–`to`.
    public func range(now: Date = Date(), from: Date = Date(), to: Date = Date(), calendar: Calendar = .current) -> Range<Date>? {
        let today = calendar.startOfDay(for: now)
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: today) ?? now
        func back(_ days: Int) -> Range<Date> { (calendar.date(byAdding: .day, value: -days, to: now) ?? now)..<Date.distantFuture }
        switch self {
        case .all: return nil
        case .today: return today..<tomorrow
        case .yesterday: return (calendar.date(byAdding: .day, value: -1, to: today) ?? today)..<today
        case .week: return back(7)
        case .month: return back(30)
        case .quarter: return back(90)
        case .year: return back(365)
        case .custom:
            let start = calendar.startOfDay(for: min(from, to))
            let lastDay = calendar.startOfDay(for: max(from, to))
            return start..<(calendar.date(byAdding: .day, value: 1, to: lastDay) ?? lastDay)
        }
    }
}

/// Souhrn výkonu jednoho hráče přes dokončené zápasy.
public struct PlayerStats {
    public struct MatchPoint: Identifiable {
        public let id: UUID
        public let date: Date
        public let average: Double
        public let first9: Double?
        public let checkout: Double?
        public let won: Bool
    }

    public var mode: GameMode = .x01
    public var matches = 0
    public var wins = 0
    public var legsPlayed = 0
    public var legsWon = 0
    public var darts = 0
    public var visits = 0
    public var points = 0
    public var first9Points = 0
    public var first9Darts = 0
    public var decidingLegs = 0
    public var decidingWon = 0
    public var checkout = CheckoutStats()
    public var bestVisit = 0
    public var bestLegDarts: Int?
    public var bestMatchAverage: Double?
    public var n180 = 0
    public var n140 = 0
    public var n100 = 0
    public var n60 = 0
    public var positioned: [Dart] = []
    public var timeline: [MatchPoint] = []

    public init() {}

    public var isEmpty: Bool { matches == 0 }
    /// X01: průměr na tři šipky. Ostatní režimy: body na kolo.
    public var average: Double {
        if mode == .x01 { return darts == 0 ? 0 : Double(points) * 3 / Double(darts) }
        return visits == 0 ? 0 : Double(points) / Double(visits)
    }
    public var first9Average: Double { first9Darts == 0 ? 0 : Double(first9Points) * 3 / Double(first9Darts) }
    public var winRate: Double { matches == 0 ? 0 : Double(wins) / Double(matches) * 100 }
    public var decidingRate: Double? { decidingLegs == 0 ? nil : Double(decidingWon) / Double(decidingLegs) * 100 }

    public static func make(matches all: [Match], playerID: UUID, mode: GameMode, range: Range<Date>?) -> PlayerStats {
        var stats = PlayerStats()
        stats.mode = mode
        let chosen = all
            .filter { $0.config.mode == mode && (range?.contains($0.completedAt ?? $0.createdAt) ?? true) }
            .sorted { ($0.completedAt ?? $0.createdAt) < ($1.completedAt ?? $1.createdAt) }

        for match in chosen {
            guard let p = match.players.firstIndex(where: { $0.id == playerID }) else { continue }
            let mine = match.visits.filter { $0.player == p }
            stats.matches += 1
            if match.winner == p { stats.wins += 1 }
            stats.legsPlayed += Set(match.visits.map(\.leg)).count
            stats.legsWon += match.states[p].legs
            stats.darts += mine.reduce(0) { $0 + $1.darts.count }
            stats.visits += mine.count
            stats.points += mine.reduce(0) { $0 + $1.credited }
            stats.bestVisit = max(stats.bestVisit, mine.map(\.credited).max() ?? 0)
            stats.positioned += mine.filter { $0.enteredAsTotal != true }.flatMap(\.darts).filter { $0.x != nil && $0.y != nil }

            var matchFirst9: Double?
            var matchCheckout: Double?
            if mode == .x01 {
                for visit in mine {
                    switch visit.credited {
                    case 180: stats.n180 += 1
                    case 140..<180: stats.n140 += 1
                    case 100..<140: stats.n100 += 1
                    case 60..<100: stats.n60 += 1
                    default: break
                    }
                }
                var points9 = 0, darts9 = 0
                for leg in Set(mine.map(\.leg)) {
                    let opening = mine.filter { $0.leg == leg }.prefix(3)
                    points9 += opening.reduce(0) { $0 + $1.credited }
                    darts9 += opening.reduce(0) { $0 + $1.darts.count }
                    if let finish = mine.last(where: { $0.leg == leg && $0.checkout }), finish.player == p {
                        let legDarts = mine.filter { $0.leg == leg }.reduce(0) { $0 + $1.darts.count }
                        stats.bestLegDarts = min(stats.bestLegDarts ?? .max, legDarts)
                    }
                }
                stats.first9Points += points9
                stats.first9Darts += darts9
                if darts9 > 0 { matchFirst9 = Double(points9) * 3 / Double(darts9) }
                let average = match.average(for: p)
                if !mine.isEmpty { stats.bestMatchAverage = max(stats.bestMatchAverage ?? 0, average) }
                let finish = CheckoutStats.make(from: match, player: p)
                matchCheckout = finish.percentage
                stats.checkout.merge(finish)
            }

            if match.config.legsToWin > 1 && match.players.count > 1 {
                var won = Array(repeating: 0, count: match.players.count)
                for leg in Set(match.visits.map(\.leg)).sorted() {
                    guard let winner = match.visits.last(where: { $0.leg == leg && $0.checkout })?.player,
                          won.indices.contains(winner) else { continue }
                    if won.filter({ $0 == match.config.legsToWin - 1 }).count >= 2 {
                        stats.decidingLegs += 1
                        if winner == p { stats.decidingWon += 1 }
                    }
                    won[winner] += 1
                }
            }

            stats.timeline.append(MatchPoint(
                id: match.id,
                date: match.completedAt ?? match.createdAt,
                average: mode == .x01 ? match.average(for: p) : (mine.isEmpty ? 0 : Double(mine.reduce(0) { $0 + $1.credited }) / Double(mine.count)),
                first9: matchFirst9,
                checkout: matchCheckout,
                won: match.winner == p
            ))
        }
        return stats
    }
}
