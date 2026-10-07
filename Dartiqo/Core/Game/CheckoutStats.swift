import Foundation

/// Pokusy a zásahy na jednom doublu (bull = 25).
public struct DoubleStat: Identifiable, Equatable {
    public let segment: Int
    public var attempts = 0
    public var hits = 0

    public var id: Int { segment }
    public var label: String { segment == 25 ? "Bull" : "D\(segment)" }
    public var percentage: Double { attempts == 0 ? 0 : Double(hits) / Double(attempts) * 100 }
}

/// Statistika zavírání v X01 s double nebo master out.
///
/// Šipka na double je každá šipka hozená ve chvíli, kdy hráči zbývá skóre zavíratelné
/// jednou šipkou (sudé 2–40 nebo 50). Návštěvy zapsané součtem nemají jednotlivé šipky,
/// proto se do pokusů nepočítají, ale jejich zavření ano.
public struct CheckoutStats: Equatable {
    public var attempts = 0
    public var hits = 0
    public var checkouts: [Int] = []
    public var doubles: [Int: DoubleStat] = [:]
    /// Některá zavření nebo pokusy byly zapsané součtem, takže pokusy nejsou úplné.
    public var unknownAttempts = false

    public init() {}

    public var hasData: Bool { attempts > 0 || !checkouts.isEmpty }
    public var percentage: Double? { attempts == 0 ? nil : Double(hits) / Double(attempts) * 100 }
    public var highest: Int { checkouts.max() ?? 0 }
    public var average: Double { checkouts.isEmpty ? 0 : Double(checkouts.reduce(0, +)) / Double(checkouts.count) }
    public var sortedDoubles: [DoubleStat] {
        doubles.values.sorted { lhs, rhs in
            lhs.attempts == rhs.attempts ? lhs.segment > rhs.segment : lhs.attempts > rhs.attempts
        }
    }
    public var favourite: DoubleStat? {
        doubles.values.filter { $0.hits > 0 }.max { lhs, rhs in
            lhs.hits == rhs.hits ? lhs.percentage < rhs.percentage : lhs.hits < rhs.hits
        }
    }
    /// Kolik zavření spadá do pásem 2–40, 41–100 a 101–170.
    public var ranges: [(title: String, count: Int)] {
        [("2–40", checkouts.filter { $0 <= 40 }.count),
         ("41–100", checkouts.filter { (41...100).contains($0) }.count),
         ("101–170", checkouts.filter { $0 > 100 }.count)]
    }

    public mutating func merge(_ other: CheckoutStats) {
        attempts += other.attempts
        hits += other.hits
        checkouts += other.checkouts
        unknownAttempts = unknownAttempts || other.unknownAttempts
        for (segment, stat) in other.doubles {
            var current = doubles[segment] ?? DoubleStat(segment: segment)
            current.attempts += stat.attempts
            current.hits += stat.hits
            doubles[segment] = current
        }
    }

    /// Double, na který jde zbývající skóre zavřít jednou šipkou.
    public static func finishingDouble(for remaining: Int) -> Int? {
        if remaining == 50 { return 25 }
        if (2...40).contains(remaining), remaining.isMultiple(of: 2) { return remaining / 2 }
        return nil
    }

    public static func make(from match: Match, player: Int, leg: Int? = nil) -> CheckoutStats {
        var stats = CheckoutStats()
        guard match.config.mode == .x01, match.config.outRule != .straight else { return stats }
        let start = match.config.startingScore
        var remaining: [Int: Int] = [:]
        var opened: [Int: Bool] = [:]

        for visit in match.visits where visit.player == player {
            let before = remaining[visit.leg] ?? start
            defer { remaining[visit.leg] = visit.remaining }
            guard leg == nil || visit.leg == leg else {
                if visit.darts.contains(where: { $0.multiplier == 2 }) { opened[visit.leg] = true }
                continue
            }
            if visit.checkout { stats.checkouts.append(before) }

            if visit.enteredAsTotal == true {
                if visit.checkout || finishingDouble(for: before) != nil { stats.unknownAttempts = true }
                continue
            }

            var left = before
            var isOpen = opened[visit.leg] ?? !match.config.doubleIn
            for dart in visit.darts {
                if !isOpen {
                    guard dart.multiplier == 2 else { continue }
                    isOpen = true
                }
                let next = left - dart.score
                if let target = finishingDouble(for: left) {
                    var stat = stats.doubles[target] ?? DoubleStat(segment: target)
                    stat.attempts += 1
                    stats.attempts += 1
                    if dart.segment == target && dart.multiplier == 2 { stat.hits += 1 }
                    if next == 0 && match.config.outRule.allows(dart) { stats.hits += 1 }
                    stats.doubles[target] = stat
                }
                if next < 0 || next == 1 || (next == 0 && !match.config.outRule.allows(dart)) { break }
                left = next
                if left == 0 { break }
            }
            opened[visit.leg] = isOpen
        }
        return stats
    }
}
