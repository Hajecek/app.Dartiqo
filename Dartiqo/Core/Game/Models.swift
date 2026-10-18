import Foundation

public enum GameMode: String, Codable, CaseIterable, Identifiable {
    case x01, cricket, aroundClock, countUp
    public var id: String { rawValue }
    public var title: String {
        switch self { case .x01: return "X01"; case .cricket: return "Cricket"; case .aroundClock: return "Kolem hodin"; case .countUp: return "Count Up" }
    }
    public var shortTitle: String { self == .countUp ? "Count Up" : title }
    public var detail: String {
        switch self {
        case .x01: return "Klasika. Zvol si start a dostaň se přesně na nulu."
        case .cricket: return "Zavři 15–20 a bull. Nasbírej víc bodů."
        case .aroundClock: return "Postupně tref 1 až 20 a nakonec bull."
        case .countUp: return "Vyber délku tréninku a překonej vlastní maximum."
        }
    }
    public var symbol: String {
        switch self { case .x01: return "target"; case .cricket: return "line.3.horizontal.decrease.circle"; case .aroundClock: return "clock"; case .countUp: return "chart.bar.fill" }
    }
}
public enum OutRule: String, CaseIterable, Codable, Identifiable {
    case double, straight, master
    public var id: String { rawValue }
    public var title: String { switch self { case .double: return "Double out"; case .straight: return "Straight out"; case .master: return "Master out" } }
    public var shortTitle: String { switch self { case .double: return "Double"; case .straight: return "Straight"; case .master: return "Master" } }
    public var detail: String {
        switch self {
        case .double: return "Poslední šipka musí být double nebo bull 50."
        case .straight: return "Zavřít můžeš jakýmkoli platným zásahem."
        case .master: return "Zavírá double, triple nebo bull 50."
        }
    }
    public func allows(_ dart: Dart) -> Bool {
        dart.score > 0 && (self == .straight || dart.multiplier == 2 || (self == .master && dart.multiplier == 3))
    }
}
/// Úprava pravidel pro jednoho hráče. `nil` znamená stejně jako hra.
public struct Handicap: Codable, Equatable {
    public var startingScore: Int?
    public var outRule: OutRule?
    public var doubleIn: Bool?
    public init(startingScore: Int? = nil, outRule: OutRule? = nil, doubleIn: Bool? = nil) {
        self.startingScore = startingScore; self.outRule = outRule; self.doubleIn = doubleIn
    }
    public var isEmpty: Bool { startingScore == nil && outRule == nil && doubleIn == nil }
}
/// Best of hraje na většinu z daného počtu. First to končí, jakmile někdo počet získá.
public enum MatchFormat: String, Codable, CaseIterable, Identifiable {
    case firstTo, bestOf
    public var id: String { rawValue }
    public var title: String { self == .firstTo ? "First to" : "Best of" }
}
public struct Dart: Codable, Hashable, Identifiable {
    public let segment: Int
    public let multiplier: Int
    /// Normalised board coordinates (−1…1 relative to scoring radius). Used for exact placement / stats.
    public var x: Double?
    public var y: Double?
    public var id: String {
        if let x, let y { return "\(segment)-\(multiplier)-\(String(format: "%.4f", x))-\(String(format: "%.4f", y))" }
        return "\(segment)-\(multiplier)"
    }
    public init(_ segment: Int, _ multiplier: Int = 1, x: Double? = nil, y: Double? = nil) {
        self.segment = segment; self.multiplier = multiplier; self.x = x; self.y = y
    }
    public var isValid: Bool {
        if segment == 0 { return multiplier == 1 }
        if segment == 25 { return (1...2).contains(multiplier) }
        return (1...20).contains(segment) && (1...3).contains(multiplier)
    }
    public var score: Int { segment * multiplier }
    public var label: String {
        if segment == 0 { return "MISS" }; if segment == 25 { return multiplier == 2 ? "BULL" : "25" }
        return "\(multiplier == 3 ? "T" : multiplier == 2 ? "D" : "S")\(segment)"
    }
    /// Scoring identity ignores precise coordinates so geometry tests and game logic stay stable.
    public static func == (lhs: Dart, rhs: Dart) -> Bool {
        lhs.segment == rhs.segment && lhs.multiplier == rhs.multiplier
    }
    public func hash(into hasher: inout Hasher) {
        hasher.combine(segment); hasher.combine(multiplier)
    }
    public static let miss = Dart(0)
    public static var targets: [Dart] {
        (1...20).reversed().map { Dart($0, 3) } + (1...20).reversed().map { Dart($0) } + (1...20).reversed().map { Dart($0, 2) } + [Dart(25), Dart(25, 2)]
    }
}
public struct Player: Codable, Identifiable, Equatable {
    public var id: UUID
    public var name: String
    public var botLevel: Int?
    /// Herní styl. Chybí u člověka a u starších zápasů.
    public var botStyle: BotPlayingStyle?
    /// Úroveň se před zápasem zvolila podle hráče a v jeho průběhu se nemění.
    public var adaptiveBot: Bool?
    /// Vlastní tříšipkový průměr. Spolu s `botCheckout` přebije tabulku úrovní.
    public var botAverage: Double?
    /// Vlastní úspěšnost mířeného double, 0…1.
    public var botCheckout: Double?
    /// Vlastní stabilita, nervy a taktika, 0…1.
    public var botConsistency: Double?
    public var botPressure: Double?
    public var botIntelligence: Double?
    public init(id: UUID = UUID(), name: String, botLevel: Int? = nil, botStyle: BotPlayingStyle? = nil, adaptiveBot: Bool? = nil, botAverage: Double? = nil, botCheckout: Double? = nil, botConsistency: Double? = nil, botPressure: Double? = nil, botIntelligence: Double? = nil) {
        self.id = id
        self.name = name
        self.botLevel = botLevel
        self.botStyle = botStyle
        self.adaptiveBot = adaptiveBot
        self.botAverage = botAverage
        self.botCheckout = botCheckout
        self.botConsistency = botConsistency
        self.botPressure = botPressure
        self.botIntelligence = botIntelligence
    }
}
public struct GameConfig: Codable, Equatable {
    public static let minimumScore = 2
    public static let maximumScore = 1701

    public var mode: GameMode
    public var startingScore: Int
    public var outRule: OutRule
    public var doubleIn: Bool
    /// Počet legů, kterými se bere set. U zápasu bez setů se tím bere celý zápas.
    public var legsToWin: Int
    /// Počet setů, kterými se bere zápas. 1 znamená, že se hraje jen na legy.
    public var setsToWin: Int
    public var format: MatchFormat
    public var options: MatchOptions?
    /// Podle pořadí hráčů v zápase. Platí jen pro X01.
    public var handicaps: [Handicap]?
    public var settings: MatchOptions { options ?? MatchOptions() }

    private func handicap(_ player: Int) -> Handicap? {
        guard mode == .x01, let handicaps, handicaps.indices.contains(player) else { return nil }
        return handicaps[player]
    }
    public func startingScore(for player: Int) -> Int { handicap(player)?.startingScore ?? startingScore }
    public func outRule(for player: Int) -> OutRule { handicap(player)?.outRule ?? outRule }
    public func doubleIn(for player: Int) -> Bool { handicap(player)?.doubleIn ?? doubleIn }
    public var hasHandicap: Bool { mode == .x01 && (handicaps ?? []).contains { !$0.isEmpty } }
    /// Aspoň jeden hráč musí otevírat doublem. Součet kola pak nejde použít.
    public func anyDoubleIn(players: Int) -> Bool { (0..<max(players, 1)).contains { doubleIn(for: $0) } }
    public func ruleLine(for player: Int) -> String {
        var parts = ["\(startingScore(for: player))", outRule(for: player).shortTitle]
        if doubleIn(for: player) { parts.append("Double in") }
        return parts.joined(separator: " · ")
    }
    public init(mode: GameMode = .x01, startingScore: Int = 501, outRule: OutRule = .double, doubleIn: Bool = false, legsToWin: Int = 2, setsToWin: Int = 1, format: MatchFormat = .firstTo) {
        self.mode = mode; self.startingScore = startingScore; self.outRule = outRule; self.doubleIn = doubleIn; self.legsToWin = legsToWin; self.setsToWin = setsToWin; self.format = format
    }

    private enum CodingKeys: String, CodingKey {
        case mode, startingScore, outRule, doubleIn, legsToWin, setsToWin, format, options, handicaps
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        mode = try container.decode(GameMode.self, forKey: .mode)
        startingScore = try container.decode(Int.self, forKey: .startingScore)
        outRule = try container.decode(OutRule.self, forKey: .outRule)
        doubleIn = try container.decode(Bool.self, forKey: .doubleIn)
        legsToWin = try container.decode(Int.self, forKey: .legsToWin)
        setsToWin = try container.decodeIfPresent(Int.self, forKey: .setsToWin) ?? 1
        format = try container.decodeIfPresent(MatchFormat.self, forKey: .format) ?? .firstTo
        options = try container.decodeIfPresent(MatchOptions.self, forKey: .options)
        handicaps = try container.decodeIfPresent([Handicap].self, forKey: .handicaps)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(mode, forKey: .mode)
        try container.encode(startingScore, forKey: .startingScore)
        try container.encode(outRule, forKey: .outRule)
        try container.encode(doubleIn, forKey: .doubleIn)
        try container.encode(legsToWin, forKey: .legsToWin)
        try container.encode(setsToWin, forKey: .setsToWin)
        try container.encode(format, forKey: .format)
        try container.encodeIfPresent(options, forKey: .options)
        try container.encodeIfPresent(handicaps, forKey: .handicaps)
    }

    /// Číslo, které uživatel vidí u legů. Best of 5 je uvnitř first to 3.
    public var shownLegs: Int { format == .bestOf ? legsToWin * 2 - 1 : legsToWin }
    public var shownSets: Int { setsToWin <= 1 ? 1 : (format == .bestOf ? setsToWin * 2 - 1 : setsToWin) }
    public var playsSets: Bool { setsToWin > 1 }

    public mutating func apply(format: MatchFormat, setsShown: Int, legsShown: Int) {
        self.format = format
        let legs = Self.shownCount(legsShown, format: format, limit: format == .bestOf ? 15 : 11)
        let sets = Self.shownCount(setsShown, format: format, limit: 11)
        legsToWin = format == .bestOf ? legs / 2 + 1 : legs
        setsToWin = sets <= 1 ? 1 : (format == .bestOf ? sets / 2 + 1 : sets)
    }

    private static func shownCount(_ value: Int, format: MatchFormat, limit: Int) -> Int {
        var count = min(limit, max(1, value))
        if format == .bestOf, count % 2 == 0 { count = count < limit ? count + 1 : count - 1 }
        return count
    }

    public var lengthLine: String {
        let legs = Self.phrase(format, shownLegs, "leg", "legy", "legů")
        guard playsSets else { return legs }
        let sets = Self.phrase(format, shownSets, "set", "sety", "setů")
        return "\(sets) · \(legs) v setu"
    }

    public var lengthDetail: String {
        if !playsSets {
            return format == .bestOf
                ? "Hraje se nejvýš \(Self.count(shownLegs, "leg", "legy", "legů")). Vyhrává, kdo získá \(legsToWin)."
                : "Vyhrává, kdo první získá \(Self.count(legsToWin, "leg", "legy", "legů"))."
        }
        if format == .bestOf {
            return "Set má nejvýš \(Self.count(shownLegs, "leg", "legy", "legů")) a bere ho \(legsToWin). Zápas má nejvýš \(Self.count(shownSets, "set", "sety", "setů")) a bere ho \(setsToWin)."
        }
        return "Set bere, kdo první získá \(Self.count(legsToWin, "leg", "legy", "legů")). Zápas bere, kdo první získá \(Self.count(setsToWin, "set", "sety", "setů"))."
    }

    private static func phrase(_ format: MatchFormat, _ value: Int, _ one: String, _ few: String, _ many: String) -> String {
        "\(format.title) \(count(value, one, few, many))"
    }

    private static func count(_ value: Int, _ one: String, _ few: String, _ many: String) -> String {
        let word = value == 1 ? one : (2...4).contains(value) ? few : many
        return "\(value) \(word)"
    }

    public var summary: String {
        switch mode {
        case .x01: return "\(startingScore) • \(outRule.title)\(doubleIn ? " • Double in" : "")\(hasHandicap ? " • Handicap" : "")\(settings.dartLimit.map { " • \($0) šipek" } ?? "") • \(lengthLine)"
        case .cricket: return "Cricket \(settings.cricketNoScore ? "bez bodů" : "s body") · \(MatchOptions.cricketNumbersLine(settings.activeCricketNumbers)) • \(lengthLine)"
        case .aroundClock: return "1–20 + bull • \(settings.clockStyle.title)"
        case .countUp: return "\(settings.countUpRounds) kol • nejvyšší skóre vyhrává"
        }
    }
}
public struct PlayerState: Codable, Equatable {
    public var remaining: Int
    public var opened: Bool
    public var legs = 0
    public var sets = 0
    public var marks: [Int: Int] = [:]
    public var points = 0
    public var clockTarget = 1
    public var rounds = 0
    public init(config: GameConfig, player: Int = 0) {
        remaining = config.startingScore(for: player)
        opened = !config.doubleIn(for: player)
    }

    private enum CodingKeys: String, CodingKey {
        case remaining, opened, legs, sets, marks, points, clockTarget, rounds
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        remaining = try container.decode(Int.self, forKey: .remaining)
        opened = try container.decode(Bool.self, forKey: .opened)
        legs = try container.decodeIfPresent(Int.self, forKey: .legs) ?? 0
        sets = try container.decodeIfPresent(Int.self, forKey: .sets) ?? 0
        marks = try container.decodeIfPresent([Int: Int].self, forKey: .marks) ?? [:]
        points = try container.decodeIfPresent(Int.self, forKey: .points) ?? 0
        clockTarget = try container.decodeIfPresent(Int.self, forKey: .clockTarget) ?? 1
        rounds = try container.decodeIfPresent(Int.self, forKey: .rounds) ?? 0
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(remaining, forKey: .remaining)
        try container.encode(opened, forKey: .opened)
        try container.encode(legs, forKey: .legs)
        try container.encode(sets, forKey: .sets)
        try container.encode(marks, forKey: .marks)
        try container.encode(points, forKey: .points)
        try container.encode(clockTarget, forKey: .clockTarget)
        try container.encode(rounds, forKey: .rounds)
    }
}
public struct Visit: Codable, Identifiable, Equatable {
    public var id = UUID()
    public var player: Int
    public var leg: Int
    public var darts: [Dart]
    public var credited: Int
    public var bust: Bool
    public var checkout: Bool
    public var remaining: Int
    public var enteredAsTotal: Bool? = nil
}
public struct GameSnapshot: Codable, Equatable {
    public var states: [PlayerState]
    public var active: Int
    public var starter: Int
    public var leg: Int
    public var legWinner: Int?
    public var winner: Int?
    public var finished: Bool
    public var visitCount: Int
    public var awaitingBullOff: Bool? = nil
    public var bullOffLegs: [Int: Int]? = nil
    public var continuedPastLimitLegs: Set<Int>? = nil
    public var awaitingDecidingStarter: Bool? = nil
    public var ghostVisitIndex: Int? = nil
}
public enum GameError: Error, LocalizedError {
    case finished, invalidDarts, legEnded, unfinishedVisit
    public var errorDescription: String? {
        switch self { case .unfinishedVisit: return "Nejprve dokonči nebo vrať rozehranou návštěvu."; case .finished: return "Zápas už skončil."; case .invalidDarts: return "Zadej tři platné šipky, nebo kratší návštěvu ukončenou zavřením či přehozem."; case .legEnded: return "Nejprve zahaj další leg." }
    }
}
public struct Match: Codable, Identifiable {
    public var id = UUID()
    public var createdAt = Date()
    public var completedAt: Date?
    public var config: GameConfig
    public var players: [Player]
    public var states: [PlayerState]
    public var active = 0
    public var starter = 0
    /// Kdo házel první v 1. legu. Nemění se při střídání ani při výběru v rozhodujícím legu.
    public var openingStarter: Int? = nil
    public var leg = 1
    public var legWinner: Int?
    public var winner: Int?
    public var finished = false
    public var visits: [Visit] = []
    public var undoStack: [GameSnapshot] = []
    public var pendingDarts: [Dart]?
    /// Limit šipek vypršel a leg čeká na rozhoz na střed.
    public var awaitingBullOff: Bool?
    /// Legy rozhodnuté rozhozem: číslo legu → vítěz.
    public var bullOffLegs: [Int: Int]?
    /// Legy, které hráči po vypršení limitu zvolili dohrát bez dalšího omezení.
    public var continuedPastLimitLegs: Set<Int>?
    /// Rozhodující leg čeká na výběr, kdo hází první.
    public var awaitingDecidingStarter: Bool?
    public var needsBullOff: Bool { awaitingBullOff == true }
    public var needsDecidingStarter: Bool { awaitingDecidingStarter == true }
    /// Čas s otevřenou hrou. Pauza, odchod ze hry ani appka na pozadí se nepočítají.
    public var playSeconds: Double?
    /// Ghost Mode: typ zdroje, popisek, průměr a fronta návštěv. Volitelná pole pro JSON v1.
    public var ghostKind: GhostKind?
    public var ghostLabel: String?
    public var ghostAverage: Double?
    public var ghostVisits: [[Dart]]?
    public var ghostVisitIndex: Int?
    public var ghostPlayerIndex: Int?
    /// Plné XP jen pro zápas, který ověřil server. Rozhraní zápasu to nenastavuje.
    public var verifiedOnline: Bool?

    public mutating func addPlayTime(from start: Date, to end: Date) {
        let span = end.timeIntervalSince(start)
        guard span > 0, span.isFinite else { return }
        playSeconds = (playSeconds ?? 0) + span
    }
    /// Změřený čas, u starších zápasů odhad z začátku a konce.
    public var playedDuration: TimeInterval {
        if let playSeconds { return playSeconds }
        guard let completedAt else { return 0 }
        return min(max(0, completedAt.timeIntervalSince(createdAt)), 2 * 3600)
    }
    /// Sólo / sám proti sobě nepatří do bilance výher a proher.
    public var countsForCompetitiveRecord: Bool {
        Set(players.map(\.id)).count >= 2
    }
    public init(config: GameConfig, players: [Player], firstPlayer: Int = 0) {
        precondition((1...4).contains(players.count))
        self.config = config; self.players = players
        self.states = players.indices.map { PlayerState(config: config, player: $0) }
        active = min(max(firstPlayer, 0), players.count - 1); starter = active
        openingStarter = active
    }
    /// Kdo otevřel zápas. U starších uložených her se dopočítá z aktuálního střídání.
    public var resolvedOpeningStarter: Int {
        if let openingStarter, players.indices.contains(openingStarter) { return openingStarter }
        let count = max(players.count, 1)
        let steps = max(leg - 1, 0)
        return ((starter - steps) % count + count) % count
    }
    public var currentPlayer: Player { players[active] }
    public var currentState: PlayerState { states[active] }
    public func isGhost(_ player: Int) -> Bool {
        ghostVisits != nil && ghostPlayerIndex == player
    }
    public var isGhostTurn: Bool { isGhost(active) }
    /// Člověk u stolu. Bot ani ghost nemají vlastní statistiky.
    public func isClassicPlayer(_ player: Int) -> Bool {
        players.indices.contains(player) && players[player].botLevel == nil && !isGhost(player)
    }
    public var tracksGhostAverage: Bool { ghostKind == .beatPB || ghostKind == .mirror }
    /// Tříšipkový průměr. Bez `leg` je to celý zápas, jinak jen jedna hra.
    public func average(for player: Int, leg: Int? = nil) -> Double {
        let darts = thrownDarts(for: player, leg: leg)
        guard darts > 0 else { return 0 }
        let points = visits.filter { $0.player == player && (leg == nil || $0.leg == leg) }.reduce(0) { $0 + $1.credited }
        return Double(points) / Double(darts) * 3
    }
    public func thrownDarts(for player: Int, leg: Int? = nil) -> Int {
        visits.filter { $0.player == player && (leg == nil || $0.leg == leg) }.reduce(0) { $0 + $1.darts.count }
    }
    /// Průměr úvodních tří kol v jednom legu. Rozjeté kolo se počítá hned.
    public func first9Average(for player: Int, leg: Int) -> Double {
        let opening = visits.filter { $0.player == player && $0.leg == leg }.prefix(3)
        let darts = opening.reduce(0) { $0 + $1.darts.count }
        guard darts > 0 else { return 0 }
        return Double(opening.reduce(0) { $0 + $1.credited }) * 3 / Double(darts)
    }
    /// Poslední dokončené kolo. Rozhozené šipky uprostřed návštěvy se neberou.
    public func lastTurnScore(for player: Int) -> Int? {
        visits.last { $0.player == player && Self.visitIsComplete($0) }?.credited
    }
    public func bestTurn(for player: Int) -> Int {
        visits.filter { $0.player == player && Self.visitIsComplete($0) }.map(\.credited).max() ?? 0
    }
    private static func visitIsComplete(_ visit: Visit) -> Bool {
        visit.darts.count >= 3 || visit.bust || visit.checkout
    }
    public func best(for player: Int) -> Int { visits.filter { $0.player == player }.map(\.credited).max() ?? 0 }
    public var snapshot: GameSnapshot {
        GameSnapshot(
            states: states, active: active, starter: starter, leg: leg, legWinner: legWinner, winner: winner,
            finished: finished, visitCount: visits.count, awaitingBullOff: awaitingBullOff, bullOffLegs: bullOffLegs,
            continuedPastLimitLegs: continuedPastLimitLegs, awaitingDecidingStarter: awaitingDecidingStarter,
            ghostVisitIndex: ghostVisitIndex
        )
    }
    public var isSane: Bool {
        guard (1...4).contains(players.count), states.count == players.count, states.indices.contains(active), states.indices.contains(starter), (1...15).contains(config.legsToWin), (1...11).contains(config.setsToWin), (GameConfig.minimumScore...GameConfig.maximumScore).contains(config.startingScore), players.indices.allSatisfy({ (GameConfig.minimumScore...GameConfig.maximumScore).contains(config.startingScore(for: $0)) }), (1...30).contains(config.settings.countUpRounds), config.settings.botDelay.isFinite, (0.3...5).contains(config.settings.botDelay) else { return false }
        guard players.allSatisfy({ $0.botLevel == nil || (1...BotDifficulty.count).contains($0.botLevel!) }), states.allSatisfy({ $0.remaining >= 0 && (1...22).contains($0.clockTarget) && (0...config.setsToWin).contains($0.sets) }), visits.allSatisfy({ players.indices.contains($0.player) && (1...3).contains($0.darts.count) && $0.darts.allSatisfy(\.isValid) }) else { return false }
        guard winner.map({ players.indices.contains($0) }) ?? true, legWinner.map({ players.indices.contains($0) }) ?? true else { return false }
        guard continuedPastLimitLegs?.allSatisfy({ $0 >= 1 }) ?? true else { return false }
        guard currentDarts.count <= 2, currentDarts.allSatisfy(\.isValid) else { return false }
        if !currentDarts.isEmpty {
            guard !finished, legWinner == nil else { return false }
            var projected = self
            projected.pendingDarts = nil
            do { try projected.submit(currentDarts, allowPartial: true) } catch { return false }
            guard projected.visits.last?.checkout == false, projected.visits.last?.bust == false else { return false }
        }
        return undoStack.allSatisfy { $0.states.count == players.count && players.indices.contains($0.active) && players.indices.contains($0.starter) && $0.visitCount <= visits.count && $0.visitCount >= 0 }
    }
}
