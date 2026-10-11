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

/// Čas u terče přes všechny režimy, rozdělený podle toho, s kým se hrálo.
public struct PlayTime {
    public enum Kind: String, CaseIterable, Identifiable {
        case training, bots, friends
        public var id: String { rawValue }
        public var title: String {
            switch self {
            case .training: return "Sám"
            case .bots: return "S botem"
            case .friends: return "S kamarády"
            }
        }
        public var detail: String {
            switch self {
            case .training: return "sólo zápasy a trénink"
            case .bots: return "aspoň jeden bot"
            case .friends: return "jen lidé"
            }
        }
        public var symbol: String {
            switch self {
            case .training: return "figure.mind.and.body"
            case .bots: return "cpu"
            case .friends: return "person.2.fill"
            }
        }
        public static func of(_ match: Match) -> Kind {
            if match.players.count == 1 { return .training }
            return match.players.contains { $0.botLevel != nil } ? .bots : .friends
        }
    }

    public struct Day: Identifiable {
        public let date: Date
        public let kind: Kind
        public let seconds: TimeInterval
        public var id: String { "\(date.timeIntervalSince1970)-\(kind.rawValue)" }
    }

    public var seconds: [Kind: TimeInterval] = [:]
    public var matches: [Kind: Int] = [:]
    public var byMode: [GameMode: TimeInterval] = [:]
    /// Počet her v režimu.
    public var matchesByMode: [GameMode: Int] = [:]
    /// Čas podle dne v týdnu (Calendar weekday 1…7).
    public var byWeekday: [Int: TimeInterval] = [:]
    /// Začátek dne → čas podle druhu hry.
    public var daily: [Date: [Kind: TimeInterval]] = [:]
    public var longest: TimeInterval = 0
    public var shortest: TimeInterval = 0
    /// Nejdelší hry (id, popisek, délka) — až 8.
    public var longestMatches: [(id: UUID, title: String, seconds: TimeInterval, date: Date)] = []
    public var total: TimeInterval { seconds.values.reduce(0, +) }
    public var matchCount: Int { matches.values.reduce(0, +) }
    public var activeDays: Int { daily.count }
    public var perMatch: TimeInterval { matchCount == 0 ? 0 : total / Double(matchCount) }
    public var perActiveDay: TimeInterval { activeDays == 0 ? 0 : total / Double(activeDays) }
    public func share(_ kind: Kind) -> Double { total <= 0 ? 0 : (seconds[kind] ?? 0) / total }
    public func share(mode: GameMode) -> Double { total <= 0 ? 0 : (byMode[mode] ?? 0) / total }
    /// Den s nejvyšším součtem času.
    public var busiestDay: (date: Date, seconds: TimeInterval)? {
        daily.map { ($0.key, $0.value.values.reduce(0, +)) }.max(by: { $0.1 < $1.1 })
    }

    public init() {}

    /// Hotový sólo úsek (trénink) mimo klasický zápas.
    public struct SoloSegment: Identifiable, Equatable {
        public var id: UUID
        public var endedAt: Date
        public var seconds: TimeInterval
        public var title: String
        public init(id: UUID, endedAt: Date, seconds: TimeInterval, title: String) {
            self.id = id
            self.endedAt = endedAt
            self.seconds = seconds
            self.title = title
        }
    }

    public static func make(
        matches all: [Match],
        playerID: UUID,
        range: Range<Date>?,
        solo: [SoloSegment] = [],
        calendar: Calendar = .current
    ) -> PlayTime {
        var time = PlayTime()
        var shortest: TimeInterval?
        var ranked: [(id: UUID, title: String, seconds: TimeInterval, date: Date)] = []

        func absorb(kind: Kind, duration: TimeInterval, stamp: Date, mode: GameMode?, title: String, id: UUID) {
            guard duration > 0 else { return }
            time.seconds[kind, default: 0] += duration
            time.matches[kind, default: 0] += 1
            if let mode {
                time.byMode[mode, default: 0] += duration
                time.matchesByMode[mode, default: 0] += 1
            }
            time.longest = max(time.longest, duration)
            shortest = min(shortest ?? duration, duration)
            let day = calendar.startOfDay(for: stamp)
            time.daily[day, default: [:]][kind, default: 0] += duration
            time.byWeekday[calendar.component(.weekday, from: stamp), default: 0] += duration
            ranked.append((id, title, duration, stamp))
        }

        for match in all where match.players.contains(where: { $0.id == playerID }) && (range?.contains(match.completedAt ?? match.createdAt) ?? true) {
            let stamp = match.completedAt ?? match.createdAt
            let rivals = match.players.filter { $0.id != playerID }.map(\.name)
            let title = rivals.isEmpty
                ? "\(match.config.mode.shortTitle) · sám"
                : "\(match.config.mode.shortTitle) · \(rivals.joined(separator: ", "))"
            absorb(
                kind: Kind.of(match),
                duration: match.playedDuration,
                stamp: stamp,
                mode: match.config.mode,
                title: title,
                id: match.id
            )
        }

        // Trénink / sólo mimo zápas — v profilu pod „Sám“.
        for segment in solo where range?.contains(segment.endedAt) ?? true {
            absorb(
                kind: .training,
                duration: segment.seconds,
                stamp: segment.endedAt,
                mode: nil,
                title: segment.title,
                id: segment.id
            )
        }

        time.shortest = shortest ?? 0
        time.longestMatches = ranked.sorted { $0.seconds > $1.seconds }.prefix(8).map { $0 }
        return time
    }

    /// Sloupce po dnech pro graf. Dny bez hry zůstanou prázdné, aby byla vidět pravidelnost.
    public func days(ending end: Date, count: Int, calendar: Calendar = .current) -> [Day] {
        let last = calendar.startOfDay(for: end)
        return (0..<count).reversed().flatMap { offset -> [Day] in
            guard let date = calendar.date(byAdding: .day, value: -offset, to: last) else { return [] }
            return Kind.allCases.map { Day(date: date, kind: $0, seconds: daily[date]?[$0] ?? 0) }
        }
    }

    /// Jedna buňka contribution mapy (den u terče).
    public struct ContributionCell: Identifiable, Equatable {
        public let date: Date
        public let seconds: TimeInterval
        /// 0 = nic, 1–4 intenzita.
        public let level: Int
        public var id: TimeInterval { date.timeIntervalSince1970 }
    }

    /// Týdenní sloupce contribution mapy (řádky Po–Ne).
    public struct ContributionWeek: Identifiable, Equatable {
        public let id: Int
        public let days: [ContributionCell]
    }

    public struct MonthLabel: Equatable {
        public var weekIndex: Int
        public var title: String
    }

    public struct ContributionGrid: Equatable {
        public var weeks: [ContributionWeek]
        public var monthLabels: [MonthLabel]
        public var activeDays: Int
    }

    /// GitHub-style mapa za posledních `weeks` týdnů (včetně prázdných dní).
    public func contributionGrid(ending end: Date = Date(), weeks: Int = 53, calendar: Calendar = .current) -> ContributionGrid {
        let last = calendar.startOfDay(for: end)
        // Zarovnat na neděli konce týdne (Calendar: 1 = neděle) → sloupec končí Ne, řádky Po…Ne.
        let weekday = calendar.component(.weekday, from: last) // 1…7
        let daysFromMonday = (weekday + 5) % 7 // Po=0 … Ne=6
        guard let gridEnd = calendar.date(byAdding: .day, value: 6 - daysFromMonday, to: last) else {
            return ContributionGrid(weeks: [], monthLabels: [], activeDays: 0)
        }
        let totalDays = weeks * 7
        guard let gridStart = calendar.date(byAdding: .day, value: -(totalDays - 1), to: gridEnd) else {
            return ContributionGrid(weeks: [], monthLabels: [], activeDays: 0)
        }

        var cells: [ContributionCell] = []
        cells.reserveCapacity(totalDays)
        var cursor = gridStart
        for _ in 0..<totalDays {
            let seconds = (daily[cursor] ?? [:]).values.reduce(0, +)
            cells.append(ContributionCell(date: cursor, seconds: seconds, level: Self.contributionLevel(seconds)))
            cursor = calendar.date(byAdding: .day, value: 1, to: cursor) ?? cursor
        }

        var weekModels: [ContributionWeek] = []
        weekModels.reserveCapacity(weeks)
        for w in 0..<weeks {
            let slice = Array(cells[(w * 7)..<((w + 1) * 7)])
            weekModels.append(ContributionWeek(id: w, days: slice))
        }

        let monthNames = ["led", "úno", "bře", "dub", "kvě", "čvn", "čvc", "srp", "zář", "říj", "lis", "pro"]
        var labels: [MonthLabel] = []
        var lastMonth = -1
        for (index, week) in weekModels.enumerated() {
            guard let first = week.days.first else { continue }
            let month = calendar.component(.month, from: first.date)
            if month != lastMonth, (1...12).contains(month) {
                labels.append(MonthLabel(weekIndex: index, title: monthNames[month - 1]))
                lastMonth = month
            }
        }

        let active = cells.filter { $0.seconds > 0 }.count
        return ContributionGrid(weeks: weekModels, monthLabels: labels, activeDays: active)
    }

    /// Prahy podle minut u terče.
    public static func contributionLevel(_ seconds: TimeInterval) -> Int {
        let minutes = seconds / 60
        if minutes <= 0 { return 0 }
        if minutes < 15 { return 1 }
        if minutes < 45 { return 2 }
        if minutes < 90 { return 3 }
        return 4
    }

    /// „2 h 15 min“, „45 min“, „<1 min“.
    public static func format(_ seconds: TimeInterval) -> String {
        let minutes = Int((seconds / 60).rounded())
        if minutes < 1 { return seconds > 0 ? "<1 min" : "0 min" }
        let hours = minutes / 60
        if hours == 0 { return "\(minutes) min" }
        return minutes % 60 == 0 ? "\(hours) h" : "\(hours) h \(minutes % 60) min"
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
    /// Zápasy proti jinému hráči/botovi (bez sóla a sám-proti-sobě).
    public var competitiveMatches = 0
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
    /// Návštěvy 80–99.
    public var n80 = 0
    public var n60 = 0
    /// Návštěvy 40–59.
    public var n40 = 0
    /// Návštěvy 20–39.
    public var n20 = 0
    /// Návštěvy pod 20 (včetně nuly / bustů s 0 body).
    public var nUnder20 = 0
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
    public var winRate: Double {
        competitiveMatches == 0 ? 0 : Double(wins) / Double(competitiveMatches) * 100
    }
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
            if match.countsForCompetitiveRecord {
                stats.competitiveMatches += 1
                if match.winner == p { stats.wins += 1 }
            }
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
                    case 80..<100: stats.n80 += 1
                    case 60..<80: stats.n60 += 1
                    case 40..<60: stats.n40 += 1
                    case 20..<40: stats.n20 += 1
                    default: stats.nUnder20 += 1
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
                    guard let winner = match.bullOffLegs?[leg] ?? match.visits.last(where: { $0.leg == leg && $0.checkout })?.player,
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
