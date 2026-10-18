import Foundation

public enum EntryStyle: String, Codable, CaseIterable, Identifiable {
    case total, darts
    public var id: String { rawValue }
    public var title: String { self == .total ? "Součet kola" : "Každá šipka" }
}
public enum ClockStyle: String, Codable, CaseIterable, Identifiable {
    case any, doubles, triples
    public var id: String { rawValue }
    public var title: String { self == .any ? "Libovolný zásah" : self == .doubles ? "Pouze doubly" : "Pouze triply" }
    public func accepts(_ dart: Dart) -> Bool { self == .any || dart.multiplier == (self == .doubles ? 2 : 3) }
}
public struct MatchOptions: Codable, Equatable {
    public var entry = EntryStyle.darts
    public var countUpRounds = 10
    public var cricketNoScore = false
    /// Vybraná pole cricketu. `nil` je klasika 20–15 a bull.
    public var cricketNumbers: [Int]? = nil
    public var clockStyle = ClockStyle.any
    public var botDelay = 1.5
    public var checkoutHints = true
    public var keepAwake = true
    /// X01: když leg nikdo nezavře do tolika šipek na hráče, rozhodne rozhoz na střed. `nil` = bez limitu.
    public var dartLimit: Int?
    public static let dartLimitChoices = [30, 45, 60, 75, 90]
    /// Vlastní limit se volí po kolech, jedno kolo jsou tři šipky.
    public static let dartLimitRounds = 3...100
    /// Klasický cricket: od dvacítky k patnáctce a nakonec bull.
    public static let standardCricketNumbers = [20, 19, 18, 17, 16, 15, 25]
    public init() {}

    /// Pole, na která se opravdu hraje. Prázdný nebo neznámý výběr spadne na klasiku.
    public var activeCricketNumbers: [Int] {
        Self.orderedCricketNumbers(cricketNumbers ?? Self.standardCricketNumbers)
    }

    public static func orderedCricketNumbers(_ raw: [Int]) -> [Int] {
        let allowed = Set(1...20).union([25])
        var seen = Set<Int>()
        let unique = raw.filter { allowed.contains($0) && seen.insert($0).inserted }
        let pool = unique.isEmpty ? standardCricketNumbers : unique
        return pool.sorted { lhs, rhs in
            if lhs == 25 { return false }
            if rhs == 25 { return true }
            return lhs > rhs
        }
    }

    public static func cricketNumbersLine(_ numbers: [Int]) -> String {
        let ordered = orderedCricketNumbers(numbers)
        if ordered == standardCricketNumbers { return "20–15 a bull" }
        if ordered.count > 8 { return "\(ordered.count) čísel" }
        return ordered.map { $0 == 25 ? "bull" : "\($0)" }.joined(separator: ", ")
    }
}

/// Co se ve hře ukáže jako tříšipkový průměr. Chybějící hodnota znamená celý zápas.
public enum AverageScope: String, Codable, CaseIterable, Identifiable {
    case match, leg, both, perLeg, hidden
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .match: return "Celý zápas"
        case .leg: return "Jen tento leg"
        case .both: return "Zápas i leg"
        case .perLeg: return "Každý leg zvlášť"
        case .hidden: return "Skrýt průměr"
        }
    }
    public var detail: String {
        switch self {
        case .match: return "Jeden průměr za všechny legy dohromady."
        case .leg: return "Počítá se jen rozehraná hra. Nový leg začíná od nuly."
        case .both: return "Na kartě jsou obě čísla vedle sebe."
        case .perLeg: return "Na kartě hráče je průměr každé hry, v jednom řádku."
        case .hidden: return "Průměr z plochy zápasu zmizí."
        }
    }
    public var symbol: String {
        switch self {
        case .match: return "chart.line.uptrend.xyaxis"
        case .leg: return "flag.fill"
        case .both: return "square.split.2x1"
        case .perLeg: return "rectangle.split.3x1"
        case .hidden: return "eye.slash"
        }
    }
}

/// Volby zobrazení během zápasu. Volitelná pole, aby starší soubor dál šel načíst.
public struct MatchDisplay: Codable, Equatable {
    public var averageScope: AverageScope?
    public var showFirst9: Bool?
    public var showLastVisit: Bool?
    public var showBestVisit: Bool?
    public var showDartCount: Bool?

    public init() {}

    public var scope: AverageScope { averageScope ?? .match }
    public var first9: Bool { showFirst9 == true }
    public var lastVisit: Bool { showLastVisit == true }
    public var bestVisit: Bool { showBestVisit == true }
    public var dartCount: Bool { showDartCount == true }
    public var showsExtraNumbers: Bool { first9 || lastVisit || bestVisit || dartCount }
}
public struct SeatDraft: Codable, Identifiable, Equatable {
    public var id = UUID()
    public var name: String
    public var isBot: Bool
    public var level: Int
    public var handicap: Handicap?
    /// Přítel nebo profil z tohoto telefonu. Zápas se pak započítá pod stejné ID.
    public var friendID: UUID?
    /// Ghost Mode soupeř. Volitelné kvůli starším předvolbám.
    public var isGhost: Bool?
    /// Styl bota. `nil` znamená vyrovnaný.
    public var botStyle: BotPlayingStyle?
    /// Adaptive AI. Úroveň v `level` je záloha, když je adaptace vypnutá.
    public var adaptiveBot: Bool?
    /// Vlastní tříšipkový průměr. Spolu s `customCheckout` jde o vlastního bota.
    public var customAverage: Double?
    /// Vlastní úspěšnost mířeného double, 0…1. Může být až 1.
    public var customCheckout: Double?
    /// Vlastní stabilita, nervy a taktika, 0…1. `nil` nechá odvození z průměru a stylu.
    public var customConsistency: Double?
    public var customPressure: Double?
    public var customIntelligence: Double?
    public init(name: String, isBot: Bool = false, level: Int = 3, friendID: UUID? = nil, isGhost: Bool = false, botStyle: BotPlayingStyle? = nil, adaptiveBot: Bool = false) {
        self.name = name; self.isBot = isBot; self.level = level; self.friendID = friendID
        self.isGhost = isGhost ? true : nil
        self.botStyle = botStyle
        self.adaptiveBot = adaptiveBot ? true : nil
    }
    public var ghostSeat: Bool { isGhost == true }

    /// Prázdné jméno a zástupný název „Bot“ se u vlastního soupeře ukážou jako Vlastní.
    public static func customBotName(_ raw: String?) -> String {
        let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if trimmed.isEmpty || trimmed.compare("Bot", options: .caseInsensitive) == .orderedSame {
            return "Vlastní"
        }
        return String(trimmed.prefix(24))
    }

    public func resolve(adaptiveAllowed: Bool, suggestedLevel: Int) -> ResolvedBot {
        let style = botStyle ?? .balanced
        if let customAverage, let customCheckout {
            let average = min(BotDifficulty.maximumAverage, max(BotDifficulty.minimumAverage, customAverage))
            let checkout = min(BotDifficulty.maximumCheckout, max(BotDifficulty.minimumCheckout, customCheckout))
            return ResolvedBot(
                level: BotDifficulty.nearestLevel(forAverage: average),
                adaptive: false,
                style: style,
                average: average,
                checkout: checkout,
                consistency: customConsistency.map { min(1, max(0, $0)) },
                pressure: customPressure.map { min(1, max(0, $0)) },
                intelligence: customIntelligence.map { min(1, max(0, $0)) }
            )
        }
        let adaptive = adaptiveBot == true && adaptiveAllowed
        let resolvedLevel = adaptive
            ? min(BotDifficulty.count, max(1, suggestedLevel))
            : min(BotDifficulty.count, max(1, level))
        return ResolvedBot(level: resolvedLevel, adaptive: adaptive, style: style, average: nil, checkout: nil)
    }

    public func botTitle(earlier: ArraySlice<SeatDraft>, adaptiveAllowed: Bool, suggestedLevel: Int) -> String {
        let mine = resolve(adaptiveAllowed: adaptiveAllowed, suggestedLevel: suggestedLevel)
        if mine.isCustom {
            let base = Self.customBotName(name)
            let copies = earlier.filter { other in
                guard other.isBot else { return false }
                let resolved = other.resolve(adaptiveAllowed: adaptiveAllowed, suggestedLevel: suggestedLevel)
                return resolved.isCustom && Self.customBotName(other.name) == base
            }.count
            return copies == 0 ? base : "\(base) \(copies + 1)"
        }
        let persona = BotLevel.get(mine.level).persona
        let copies = earlier.filter { other in
            guard other.isBot else { return false }
            let resolved = other.resolve(adaptiveAllowed: adaptiveAllowed, suggestedLevel: suggestedLevel)
            return !resolved.isCustom && resolved.level == mine.level
        }.count
        return copies == 0 ? persona : "\(persona) \(copies + 1)"
    }
}
public struct SetupDraft: Codable, Equatable {
    public var config = GameConfig()
    public var seats = [SeatDraft(name: "Já")]
    public var starter = 0 // -1 means random; otherwise explicit roster position
    /// `true` znamená, že první místo nepatří vlastníkovi profilu.
    public var withoutMe: Bool?
    /// Zvolená varianta Ghost Mode. Volitelné pole JSON v1.
    public var ghostKind: GhostKind?
    /// U `pickMatch` odkaz na konkrétní zápas. Volitelné pole JSON v1.
    public var ghostMatchID: UUID?
    public var includesMe: Bool { withoutMe != true }
    public init(mode: GameMode = .x01) { config.mode = mode; config.options = MatchOptions() }
}
public struct GamePreset: Codable, Identifiable {
    public var id = UUID()
    public var owner: UUID
    public var name: String
    public var setup: SetupDraft
    public init(owner: UUID, name: String, setup: SetupDraft) { self.owner = owner; self.name = name; self.setup = setup }
}
public enum ScoreEntryError: Error, LocalizedError {
    case unsupported, impossible, finish, useBust, invalidBust
    public var errorDescription: String? {
        switch self {
        case .unsupported: return "V tomto režimu zapisuj jednotlivé šipky."
        case .impossible: return "Takové skóre nejde hodit třemi šipkami. Zkontroluj zápis."
        case .finish: return "Toto zavření není možné zvoleným počtem šipek a pravidlem out."
        case .invalidBust: return "S tímto zůstatkem a počtem šipek není přehoz možný."
        case .useBust: return "To je přehoz. Použij BUST a potvrď počet skutečně hozených šipek."
        }
    }
}
extension Match {
    /// Sum entry stores inferred darts only for rule validation, visibly marked in history.
    public mutating func submitTotal(_ score: Int, checkoutDarts: Int = 3) throws {
        guard config.mode == .x01, currentState.opened else { throw ScoreEntryError.unsupported }
        guard !finished else { throw GameError.finished }
        guard legWinner == nil, !needsBullOff, !needsDecidingStarter else { throw GameError.legEnded }
        guard (0...180).contains(score) else { throw ScoreEntryError.impossible }
        let remaining = currentState.remaining
        let rule = config.outRule(for: active)
        if score > remaining || (remaining - score == 1 && rule != .straight) {
            guard let route = Self.scoringRoute(score), !route.isEmpty else { throw ScoreEntryError.impossible }
            try recordBust(darts: route.count)
            return
        }
        var darts: [Dart]
        if score == remaining {
            guard (1...3).contains(checkoutDarts), let route = Checkout.route(for: score, rule: rule, darts: checkoutDarts) else { throw ScoreEntryError.finish }
            darts = Array(repeating: .miss, count: checkoutDarts - route.count) + route
        } else {
            guard let route = Self.scoringRoute(score) else { throw ScoreEntryError.impossible }
            darts = Array(repeating: .miss, count: 3 - route.count) + route
        }
        try submit(darts)
        visits[visits.count - 1].enteredAsTotal = true
    }
    public mutating func recordBust(darts: Int) throws {
        guard currentDarts.isEmpty else { throw GameError.unfinishedVisit }
        guard config.mode == .x01, currentState.opened else { throw ScoreEntryError.unsupported }
        guard !finished else { throw GameError.finished }
        guard legWinner == nil, !needsBullOff, !needsDecidingStarter else { throw GameError.legEnded }
        guard (1...3).contains(darts) else { throw GameError.invalidDarts }
        guard canBust(remaining: currentState.remaining, darts: darts) else { throw ScoreEntryError.invalidBust }
        undoStack.append(snapshot)
        states[active].rounds += 1
        visits.append(Visit(player: active, leg: leg, darts: Array(repeating: .miss, count: darts), credited: 0, bust: true, checkout: false, remaining: currentState.remaining, enteredAsTotal: true))
        active = (active + 1) % players.count
        checkDartLimit()
    }
    private func canBust(remaining: Int, darts: Int) -> Bool {
        if remaining > darts * 60 + 1 { return false }
        let rule = config.outRule(for: active)
        for dart in Dart.targets + [.miss] {
            let next = remaining - dart.score
            let bust = next < 0 || (next == 1 && rule != .straight) || (next == 0 && !rule.allows(dart))
            if bust { if darts == 1 { return true }; continue }
            if next > 0 && darts > 1 && canBust(remaining: next, darts: darts - 1) { return true }
        }
        return false
    }
    public static func scoringRoute(_ total: Int) -> [Dart]? {
        guard (0...180).contains(total) else { return nil }
        if total == 0 { return [] }
        let targets = Dart.targets
        if let one = targets.first(where: { $0.score == total }) { return [one] }
        for a in targets { if let b = targets.first(where: { a.score + $0.score == total }) { return [a,b] } }
        for a in targets { for b in targets { if let c = targets.first(where: { a.score + b.score + $0.score == total }) { return [a,b,c] } } }
        return nil
    }
}
extension Visit {
    public var inputDescription: String {
        enteredAsTotal == true ? (bust ? "Přehoz · \(darts.count) šipky" : "Součet \(credited) · \(darts.count) šipky") : darts.map(\.label).joined(separator: " · ")
    }
}
