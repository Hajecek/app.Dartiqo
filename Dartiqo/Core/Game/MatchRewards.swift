import Foundation

/// Jedna položka rozkladu XP za dohraný zápas.
public struct MatchXPLine: Codable, Identifiable, Equatable {
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
    public var reasons: [String]
    /// Součet složek před koeficientem režimu a ochrany.
    public var raw: Int
    public var coefficient: Double
    /// Interní značky k prověření. Samy o sobě odměnu nestrhávají.
    public var review: [String]

    public var total: Int { lines.reduce(0) { $0 + $1.amount } }
    public var hasAward: Bool { !lines.isEmpty || !reasons.isEmpty }

    public init(
        lines: [MatchXPLine] = [],
        reasons: [String] = [],
        raw: Int = 0,
        coefficient: Double = 0,
        review: [String] = []
    ) {
        self.lines = lines.filter { $0.amount != 0 }
        self.reasons = reasons
        self.raw = raw
        self.coefficient = coefficient
        self.review = review
    }

    public var explanation: String {
        var parts = ["Celkové XP jsou součet složek po koeficientu režimu a ochrany proti farmení, zaokrouhlený na celé XP. Prohra se odečítá."]
        if !reasons.isEmpty { parts.append(reasons.joined(separator: "\n")) }
        return parts.joined(separator: "\n\n")
    }
}

/// Pásmo od–do s pevnou odměnou XP. Horní mez je otevřená, pokud `upperInclusive` není zapnuté.
public struct MatchXPRange: Equatable {
    public var from: Double
    public var to: Double?
    public var xp: Int
    public var upperInclusive = false
    public var label: String

    public func contains(_ value: Double) -> Bool {
        guard value >= from else { return false }
        guard let to else { return true }
        return upperInclusive ? value <= to : value < to
    }
}

/// Všechna čísla zápasového XP na jednom místě.
public struct MatchXPConfig: Equatable {
    public var playedXP = 5
    public var completedXP = 15
    public var winXP = 30
    public var drawXP = 15
    public var lossXP = -10

    public var averageBands: [MatchXPRange] = [
        MatchXPRange(from: 0, to: 30, xp: 5, label: "Pod 30"),
        MatchXPRange(from: 30, to: 40, xp: 10, label: "30–39,99"),
        MatchXPRange(from: 40, to: 50, xp: 15, label: "40–49,99"),
        MatchXPRange(from: 50, to: 60, xp: 20, label: "50–59,99"),
        MatchXPRange(from: 60, to: 70, xp: 25, label: "60–69,99"),
        MatchXPRange(from: 70, to: 80, xp: 30, label: "70–79,99"),
        MatchXPRange(from: 80, to: 90, xp: 35, label: "80–89,99"),
        MatchXPRange(from: 90, to: 100, xp: 40, label: "90–99,99"),
        MatchXPRange(from: 100, to: 110, xp: 45, label: "100–109,99"),
        MatchXPRange(from: 110, to: nil, xp: 50, label: "110+")
    ]
    public var checkoutBands: [MatchXPRange] = [
        MatchXPRange(from: 0, to: 10, xp: 5, label: "Více než 0 % až pod 10 %"),
        MatchXPRange(from: 10, to: 20, xp: 10, label: "10–19,99 %"),
        MatchXPRange(from: 20, to: 30, xp: 15, label: "20–29,99 %"),
        MatchXPRange(from: 30, to: 40, xp: 20, label: "30–39,99 %"),
        MatchXPRange(from: 40, to: 50, xp: 25, label: "40–49,99 %"),
        MatchXPRange(from: 50, to: 60, xp: 30, label: "50–59,99 %"),
        MatchXPRange(from: 60, to: 70, xp: 35, label: "60–69,99 %"),
        MatchXPRange(from: 70, to: 80, xp: 40, label: "70–79,99 %"),
        MatchXPRange(from: 80, to: 90, xp: 45, label: "80–89,99 %"),
        MatchXPRange(from: 90, to: 100, xp: 50, upperInclusive: true, label: "90–100 %")
    ]

    public var oneEightyXP = 10
    public var oneEightyCap = 30
    public var highCheckoutXP = 15
    public var highCheckoutMinimum = 100
    public var highCheckoutCap = 30

    /// Plné bonusy až od tolika dokončených legů.
    public var fullAwardLegs = 3
    public var minimumCheckoutAttempts = 3
    public var minimumAverageDarts = 3

    /// První tolik zápasů proti stejnému soupeři v okně má 100 %.
    public var repeatFullCount = 3
    /// Zápas s pořadím `repeatFullCount + 1` … `repeatHalfUntil` má 50 %. Další má 0 %.
    public var repeatHalfUntil = 5
    public var repeatWindow: TimeInterval = 24 * 60 * 60

    public var botCoefficient = 0.5
    public var botDailyCap = 10
    public var modeCoefficients: [GameMode: Double] = Dictionary(uniqueKeysWithValues: GameMode.allCases.map { ($0, 1) })

    /// Krátký čas je jen signál. Sám odměnu nestrhává.
    public var shortDartFloor = 12
    public var minimumSecondsPerDart = 1.2
    public var outlierSample = 5
    public var outlierMinimumDarts = 9
    public var outlierAverageFloor = 100.0
    public var outlierGap = 35.0
    public var repeatWinFlagCount = 5
    public var giveawayFlagCount = 3
    public var signalsToWithhold = 2

    public static let standard = MatchXPConfig()
}

/// Uložená odměna. Stejné `id` jde zapsat jen jednou.
public struct MatchXPAward: Codable, Equatable, Identifiable {
    public var id: String
    public var owner: UUID
    public var matchID: UUID
    public var amount: Int
    public var raw: Int
    public var coefficient: Double
    public var lines: [MatchXPLine]
    public var reasons: [String]
    public var review: [String]
    public var createdAt: Date

    public static func key(owner: UUID, match: UUID) -> String {
        "\(owner.uuidString)|\(match.uuidString)"
    }

    public init(owner: UUID, matchID: UUID, breakdown: MatchXPBreakdown, createdAt: Date = Date()) {
        id = Self.key(owner: owner, match: matchID)
        self.owner = owner
        self.matchID = matchID
        amount = breakdown.total
        raw = breakdown.raw
        coefficient = breakdown.coefficient
        lines = breakdown.lines
        reasons = breakdown.reasons
        review = breakdown.review
        self.createdAt = createdAt
    }

    public var breakdown: MatchXPBreakdown {
        MatchXPBreakdown(lines: lines, reasons: reasons, raw: raw, coefficient: coefficient, review: review)
    }
}

public enum MatchXPBook {
    /// Zapíše odměnu, pokud pro hráče a zápas ještě neexistuje.
    public static func insert(_ award: MatchXPAward, into awards: inout [MatchXPAward]) -> Bool {
        if awards.contains(where: { $0.id == award.id }) { return false }
        awards.append(award)
        return true
    }
}

/// XP za zápasy. Obrazovka tuhle částku nepočítá znovu jiným vzorcem.
///
/// Ověřený online zápas (`Match.verifiedOnline`) má koeficient 1. Bez serveru ho nic v aplikaci nenastavuje,
/// takže zápas dvou lidí na jednom zařízení má koeficient 0 a zápas proti botovi 50 %.
public enum MatchRewards {
    public static var averageBands: [MatchXPRange] { MatchXPConfig.standard.averageBands }
    public static var checkoutBands: [MatchXPRange] { MatchXPConfig.standard.checkoutBands }

    public static func rounded(_ raw: Int, coefficient: Double) -> Int {
        guard coefficient > 0 else { return 0 }
        return Int((Double(raw) * coefficient).rounded(.toNearestOrAwayFromZero))
    }

    public static func averageXP(_ average: Double, legs: Int, darts: Int, config: MatchXPConfig = .standard) -> Int {
        guard legs >= config.fullAwardLegs, darts >= config.minimumAverageDarts else { return 0 }
        return config.averageBands.first { $0.contains(average) }?.xp ?? 0
    }

    public static func checkoutXP(rate: Double, attempts: Int, legs: Int, config: MatchXPConfig = .standard) -> Int {
        guard legs >= config.fullAwardLegs, attempts >= config.minimumCheckoutAttempts, rate > 0 else { return 0 }
        let clamped = min(100, rate)
        return config.checkoutBands.first { $0.contains(clamped) }?.xp ?? 0
    }

    public static func award(
        match: Match,
        playerID: UUID,
        history: [Match] = [],
        config: MatchXPConfig = .standard,
        calendar: Calendar = .current
    ) -> MatchXPBreakdown {
        guard match.finished else { return MatchXPBreakdown() }
        guard let player = match.players.firstIndex(where: { $0.id == playerID }) else { return MatchXPBreakdown() }
        let mine = match.visits.filter { $0.player == player }
        let darts = mine.reduce(0) { $0 + $1.darts.count }
        guard darts > 0 else {
            return MatchXPBreakdown(reasons: ["Bez tvé šipky se XP nepřiděluje."])
        }
        if ledgerBreaks(match) {
            return MatchXPBreakdown(
                reasons: ["XP je pozastavené k prověření. Zapsané hody nesedí na skóre nebo výsledek."],
                review: ["ledger"]
            )
        }

        let legs = completedLegCount(match)
        let full = legs >= config.fullAwardLegs
        var lines: [MatchXPLine] = [
            MatchXPLine(id: "played", title: "Odehraný zápas", detail: "Základ za účast · \(match.config.mode.shortTitle)", symbol: "flag.checkered", amount: config.playedXP),
            MatchXPLine(id: "completed", title: "Dokončený zápas", detail: "Zápas doběhl do výsledku", symbol: "checkmark.circle.fill", amount: config.completedXP)
        ]
        if let result = resultLine(match: match, player: player, config: config) {
            lines.append(result)
        }
        if full, match.config.mode == .x01 {
            lines += performance(match: match, player: player, visits: mine, darts: darts, legs: legs, config: config)
        }

        let raw = lines.reduce(0) { $0 + $1.amount }
        let earlier = earlierMatches(history, than: match, playerID: playerID)
        let venue = venue(of: match, playerID: playerID)
        let keys = opponentKeys(match, playerID: playerID)
        let repeatPrior = repeatCount(keys: keys, earlier: earlier, stamp: stamp(of: match), playerID: playerID, config: config)
        let botToday = earlier.filter { Self.venue(of: $0, playerID: playerID) == .bot && calendar.isDate(stamp(of: $0), inSameDayAs: stamp(of: match)) }.count
        let botDarts = opponentDartCount(match, playerID: playerID, botsOnly: true)

        var zero: [String] = []
        var cuts: [String] = []
        switch venue {
        case .solo:
            zero.append("Zápas bez soupeře XP nepřiděluje.")
        case .ghost:
            zero.append("Ghost není ověřený soupeř, takže zápas XP nepřiděluje.")
        case .local:
            zero.append("Lokální zápas na jednom zařízení XP nepřiděluje. Plné XP jsou jen za ověřený online zápas.")
        case .bot:
            if botDarts == 0 {
                zero.append("Proti botovi se XP počítá, jen když bot taky hodil.")
            } else if botToday >= config.botDailyCap {
                zero.append("Dnešní limit \(config.botDailyCap) zápasů proti botovi je vyčerpaný. Další zápas proti botovi XP nepřiděluje.")
            } else if config.botCoefficient < 1 {
                cuts.append("Proti botovi se počítá \(percent(config.botCoefficient)) XP.")
            }
        case .online:
            break
        }

        let modeCoefficient = config.modeCoefficients[match.config.mode] ?? 1
        if venue == .online || venue == .bot, modeCoefficient != 1 {
            let text = "Režim \(match.config.mode.shortTitle) má koeficient \(percent(modeCoefficient))."
            if modeCoefficient <= 0 { zero.append(text) } else { cuts.append(text) }
        }
        if venue == .online || venue == .bot {
            let order = repeatPrior + 1
            let hours = max(1, Int((config.repeatWindow / 3600).rounded()))
            if repeatPrior >= config.repeatHalfUntil {
                zero.append("Tohle je \(order). zápas proti stejnému soupeři za posledních \(hours) hodin, takže XP nepřiděluje.")
            } else if repeatPrior >= config.repeatFullCount {
                cuts.append("Tohle je \(order). zápas proti stejnému soupeři za posledních \(hours) hodin, takže se počítá 50 % XP.")
            }
        }

        var reasons: [String]
        var coefficient: Double
        if !zero.isEmpty {
            reasons = zero
            coefficient = 0
        } else {
            let repeatFactor = repeatPrior >= config.repeatHalfUntil ? 0 : (repeatPrior >= config.repeatFullCount ? 0.5 : 1)
            let venueFactor = venue == .bot ? config.botCoefficient : 1
            coefficient = modeCoefficient * venueFactor * repeatFactor
            reasons = cuts
        }

        var review = reviewFlags(match: match, player: player, earlier: earlier, config: config)
        if coefficient > 0, let hold = withholdReason(review: review, config: config) {
            coefficient = 0
            reasons = [hold]
        }
        if coefficient > 0, legs < config.fullAwardLegs {
            reasons.append("Míň než \(config.fullAwardLegs) dokončené legy: jen odehrání, dokončení a výsledek.")
        }

        let final = rounded(raw, coefficient: coefficient)
        if final != raw {
            lines.append(MatchXPLine(
                id: "adjustment",
                title: "Úprava odměny",
                detail: reasons.joined(separator: " "),
                symbol: "shield.lefthalf.filled",
                amount: final - raw
            ))
        }
        if !review.isEmpty, coefficient == 0, !reasons.contains(where: { $0.contains("prověření") }) {
            review.append("held-by-rule")
        }
        return MatchXPBreakdown(lines: lines, reasons: reasons, raw: raw, coefficient: coefficient, review: review)
    }

    // MARK: - Složky

    private static func resultLine(match: Match, player: Int, config: MatchXPConfig) -> MatchXPLine? {
        let opponents = match.players.indices.filter { $0 != player }
        guard !opponents.isEmpty else { return nil }
        if match.winner == player {
            return MatchXPLine(id: "win", title: "Výhra", detail: scoreDetail(match, player: player), symbol: "trophy.fill", amount: config.winXP)
        }
        if match.winner == nil {
            return MatchXPLine(id: "draw", title: "Remíza", detail: scoreDetail(match, player: player), symbol: "equal.circle.fill", amount: config.drawXP)
        }
        return MatchXPLine(id: "loss", title: "Prohra", detail: "\(scoreDetail(match, player: player)) · odečítá se od ostatních XP", symbol: "xmark.circle.fill", amount: config.lossXP)
    }

    private static func performance(match: Match, player: Int, visits: [Visit], darts: Int, legs: Int, config: MatchXPConfig) -> [MatchXPLine] {
        var lines: [MatchXPLine] = []
        let average = match.average(for: player)
        let averageAmount = averageXP(average, legs: legs, darts: darts, config: config)
        if averageAmount > 0, let band = config.averageBands.first(where: { $0.contains(average) }) {
            lines.append(MatchXPLine(
                id: "average",
                title: "Průměr \(decimal(average))",
                detail: "Pásmo \(band.label) = \(band.xp) XP",
                symbol: "chart.line.uptrend.xyaxis",
                amount: averageAmount
            ))
        }

        let finish = CheckoutStats.make(from: match, player: player)
        if let rate = finish.percentage {
            let amount = checkoutXP(rate: rate, attempts: finish.attempts, legs: legs, config: config)
            if amount > 0, let band = config.checkoutBands.first(where: { $0.contains(min(100, rate)) }) {
                lines.append(MatchXPLine(
                    id: "checkout",
                    title: "Zavírání \(Int(rate.rounded())) %",
                    detail: "Pásmo \(band.label) = \(band.xp) XP · \(finish.hits)/\(finish.attempts)",
                    symbol: "percent",
                    amount: amount
                ))
            }
        }

        let oneEighties = visits.filter { $0.credited == 180 && !$0.bust }.count
        let oneEightyAmount = min(config.oneEightyCap, oneEighties * config.oneEightyXP)
        if oneEightyAmount > 0 {
            lines.append(MatchXPLine(
                id: "one-eighty",
                title: oneEighties == 1 ? "1× 180" : "\(oneEighties)× 180",
                detail: "+\(config.oneEightyXP) XP za 180 · max \(config.oneEightyCap)",
                symbol: "flame.fill",
                amount: oneEightyAmount
            ))
        }

        let high = visits.filter { $0.checkout && !$0.bust && $0.credited >= config.highCheckoutMinimum }.count
        let highAmount = min(config.highCheckoutCap, high * config.highCheckoutXP)
        if highAmount > 0 {
            lines.append(MatchXPLine(
                id: "high-checkout",
                title: high == 1 ? "Zavření \(config.highCheckoutMinimum)+" : "\(high)× zavření \(config.highCheckoutMinimum)+",
                detail: "+\(config.highCheckoutXP) XP za zavření · max \(config.highCheckoutCap)",
                symbol: "flag.fill",
                amount: highAmount
            ))
        }
        return lines
    }

    // MARK: - Soupeř a historie

    private enum Venue: Equatable {
        case online, bot, local, solo, ghost
    }

    private static func venue(of match: Match, playerID: UUID) -> Venue {
        guard let me = match.players.firstIndex(where: { $0.id == playerID }) else { return .local }
        let others = match.players.indices.filter { $0 != me }
        if others.isEmpty { return .solo }
        let ghosts = others.filter { match.isGhost($0) }
        let bots = others.filter { match.players[$0].botLevel != nil }
        let humans = others.filter { match.players[$0].botLevel == nil && !match.isGhost($0) }
        if !humans.isEmpty {
            return match.verifiedOnline == true ? .online : .local
        }
        if !bots.isEmpty { return .bot }
        if ghosts.count == others.count { return .ghost }
        return .local
    }

    private static func opponentKeys(_ match: Match, playerID: UUID) -> [RivalKey] {
        match.players.indices
            .filter { match.players[$0].id != playerID }
            .map { RivalKey.of(opponent: match.players[$0], in: match) }
    }

    private static func stamp(of match: Match) -> Date {
        match.completedAt ?? match.createdAt
    }

    private static func earlierMatches(_ history: [Match], than match: Match, playerID: UUID) -> [Match] {
        let end = stamp(of: match)
        return history.filter { prior in
            guard prior.id != match.id, prior.finished, prior.players.contains(where: { $0.id == playerID }) else { return false }
            let time = stamp(of: prior)
            if time < end { return true }
            if time > end { return false }
            return prior.id.uuidString < match.id.uuidString
        }
    }

    private static func repeatCount(keys: [RivalKey], earlier: [Match], stamp: Date, playerID: UUID, config: MatchXPConfig) -> Int {
        guard !keys.isEmpty else { return 0 }
        let window = earlier.filter { stamp.timeIntervalSince(self.stamp(of: $0)) <= config.repeatWindow }
        return keys.map { key in window.filter { opponentKeys($0, playerID: playerID).contains(key) }.count }.max() ?? 0
    }

    private static func opponentDartCount(_ match: Match, playerID: UUID, botsOnly: Bool) -> Int {
        guard let me = match.players.firstIndex(where: { $0.id == playerID }) else { return 0 }
        return match.visits.reduce(0) { sum, visit in
            guard visit.player != me else { return sum }
            if botsOnly, match.players[visit.player].botLevel == nil { return sum }
            return sum + visit.darts.count
        }
    }

    static func completedLegCount(_ match: Match) -> Int {
        var legs = Set(match.visits.filter(\.checkout).map(\.leg))
        if let bull = match.bullOffLegs { legs.formUnion(bull.keys) }
        return legs.count
    }

    // MARK: - Prověření

    private static func reviewFlags(match: Match, player: Int, earlier: [Match], config: MatchXPConfig) -> [String] {
        var flags: [String] = []
        let darts = match.visits.reduce(0) { $0 + $1.darts.count }
        let duration = match.playedDuration
        if darts >= config.shortDartFloor, duration > 0, duration < Double(darts) * config.minimumSecondsPerDart {
            flags.append("short-time")
        }
        if outlier(match: match, player: player, earlier: earlier, config: config) {
            flags.append("outlier")
        }
        let wins = repeatWins(match: match, player: player, earlier: earlier, config: config)
        if wins >= config.repeatWinFlagCount { flags.append("repeat-wins") }
        if giveaways(match: match, player: player, earlier: earlier, config: config) >= config.giveawayFlagCount {
            flags.append("giveaways")
        }
        return flags
    }

    private static func withholdReason(review: [String], config: MatchXPConfig) -> String? {
        if review.contains("giveaways") {
            return "XP je pozastavené k prověření. Opakované výhry bez hodu soupeře."
        }
        let soft = review.filter { $0 == "short-time" || $0 == "outlier" || $0 == "repeat-wins" }
        guard soft.count >= config.signalsToWithhold else { return nil }
        return "XP je pozastavené k prověření. Zápas se vymyká běžnému průběhu."
    }

    private static func outlier(match: Match, player: Int, earlier: [Match], config: MatchXPConfig) -> Bool {
        guard match.config.mode == .x01 else { return false }
        let current = match.average(for: player)
        guard current >= config.outlierAverageFloor else { return false }
        let samples = earlier.filter { prior in
            prior.config.mode == .x01 && dartCount(prior, playerID: match.players[player].id) >= config.outlierMinimumDarts
        }.map { $0.average(for: index(of: match.players[player].id, in: $0) ?? 0) }
        guard samples.count >= config.outlierSample else { return false }
        return current >= median(samples) + config.outlierGap
    }

    private static func repeatWins(match: Match, player: Int, earlier: [Match], config: MatchXPConfig) -> Int {
        guard match.winner == player else { return 0 }
        let keys = opponentKeys(match, playerID: match.players[player].id)
        let end = stamp(of: match)
        let wins = earlier.filter { prior in
            end.timeIntervalSince(stamp(of: prior)) <= config.repeatWindow
                && !Set(opponentKeys(prior, playerID: match.players[player].id)).isDisjoint(with: keys)
                && prior.winner == index(of: match.players[player].id, in: prior)
        }.count
        return wins + 1
    }

    private static func giveaways(match: Match, player: Int, earlier: [Match], config: MatchXPConfig) -> Int {
        let end = stamp(of: match)
        let past = earlier.filter { prior in
            end.timeIntervalSince(stamp(of: prior)) <= config.repeatWindow
                && isGiveaway(prior, playerID: match.players[player].id)
        }.count
        return past + (isGiveaway(match, player: player) ? 1 : 0)
    }

    private static func isGiveaway(_ match: Match, playerID: UUID) -> Bool {
        guard let player = index(of: playerID, in: match) else { return false }
        return isGiveaway(match, player: player)
    }

    private static func isGiveaway(_ match: Match, player: Int) -> Bool {
        guard match.finished, match.winner == player else { return false }
        let mine = match.visits.filter { $0.player == player }.reduce(0) { $0 + $1.darts.count }
        let theirs = opponentDartCount(match, playerID: match.players[player].id, botsOnly: false)
        return mine > 0 && theirs == 0
    }

    private static func ledgerBreaks(_ match: Match) -> Bool {
        guard match.winner.map({ match.players.indices.contains($0) }) ?? true else { return true }
        if match.config.mode == .x01, match.config.setsToWin <= 1, (match.bullOffLegs ?? [:]).isEmpty, let winner = match.winner, match.states.indices.contains(winner), match.states[winner].legs < match.config.legsToWin {
            return true
        }
        for visit in match.visits {
            guard match.players.indices.contains(visit.player) else { return true }
            guard (1...3).contains(visit.darts.count), visit.darts.allSatisfy(\.isValid) else { return true }
            if visit.credited > 180 || visit.credited < 0 { return true }
            if visit.checkout && visit.remaining != 0 { return true }
            if visit.bust && visit.credited != 0 { return true }
            let thrown = visit.darts.reduce(0) { $0 + $1.score }
            if !visit.bust && visit.enteredAsTotal != true && visit.credited > thrown { return true }
            if visit.credited == 180 && !visit.bust && visit.enteredAsTotal != true && thrown != 180 { return true }
        }
        return false
    }

    private static func dartCount(_ match: Match, playerID: UUID) -> Int {
        guard let player = index(of: playerID, in: match) else { return 0 }
        return match.visits.filter { $0.player == player }.reduce(0) { $0 + $1.darts.count }
    }

    private static func index(of playerID: UUID, in match: Match) -> Int? {
        match.players.firstIndex { $0.id == playerID }
    }

    private static func median(_ values: [Double]) -> Double {
        let sorted = values.sorted()
        let mid = sorted.count / 2
        if sorted.count.isMultiple(of: 2) { return (sorted[mid - 1] + sorted[mid]) / 2 }
        return sorted[mid]
    }

    private static func scoreDetail(_ match: Match, player: Int) -> String {
        let legs = match.states.map(\.legs)
        let mine = legs.indices.contains(player) ? legs[player] : 0
        let theirs = legs.enumerated().filter { $0.offset != player }.map(\.element).max() ?? 0
        return "\(mine):\(theirs) · \(match.config.lengthLine)"
    }

    private static func decimal(_ value: Double) -> String {
        String(format: "%.1f", value).replacingOccurrences(of: ".", with: ",")
    }

    private static func percent(_ value: Double) -> String {
        "\(Int((value * 100).rounded())) %"
    }
}
