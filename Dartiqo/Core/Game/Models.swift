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
        case .x01: return "Klasika od 101 do 1001. Dostaň se přesně na nulu."
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
    public func allows(_ dart: Dart) -> Bool {
        dart.score > 0 && (self == .straight || dart.multiplier == 2 || (self == .master && dart.multiplier == 3))
    }
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
    public init(id: UUID = UUID(), name: String, botLevel: Int? = nil) { self.id = id; self.name = name; self.botLevel = botLevel }
}
public struct GameConfig: Codable, Equatable {
    public var mode: GameMode
    public var startingScore: Int
    public var outRule: OutRule
    public var doubleIn: Bool
    public var legsToWin: Int
    public var options: MatchOptions?
    public var settings: MatchOptions { options ?? MatchOptions() }
    public init(mode: GameMode = .x01, startingScore: Int = 501, outRule: OutRule = .double, doubleIn: Bool = false, legsToWin: Int = 2) {
        self.mode = mode; self.startingScore = startingScore; self.outRule = outRule; self.doubleIn = doubleIn; self.legsToWin = legsToWin
    }
    public var summary: String {
        switch mode {
        case .x01: return "\(startingScore) • \(outRule.title)\(doubleIn ? " • Double in" : "")"
        case .cricket: return "Cricket \(settings.cricketNoScore ? "bez bodů" : "s body") • 15–20 + bull"
        case .aroundClock: return "1–20 + bull • \(settings.clockStyle.title)"
        case .countUp: return "\(settings.countUpRounds) kol • nejvyšší skóre vyhrává"
        }
    }
}
public struct PlayerState: Codable, Equatable {
    public var remaining: Int
    public var opened: Bool
    public var legs = 0
    public var marks: [Int: Int] = [:]
    public var points = 0
    public var clockTarget = 1
    public var rounds = 0
    public init(config: GameConfig) { remaining = config.startingScore; opened = !config.doubleIn }
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
    public var leg = 1
    public var legWinner: Int?
    public var winner: Int?
    public var finished = false
    public var visits: [Visit] = []
    public var undoStack: [GameSnapshot] = []
    public var pendingDarts: [Dart]?
    public init(config: GameConfig, players: [Player], firstPlayer: Int = 0) {
        precondition((1...4).contains(players.count))
        self.config = config; self.players = players
        self.states = players.map { _ in PlayerState(config: config) }
        active = min(max(firstPlayer, 0), players.count - 1); starter = active
    }
    public var currentPlayer: Player { players[active] }
    public var currentState: PlayerState { states[active] }
    public func average(for player: Int) -> Double {
        let v = visits.filter { $0.player == player }; let darts = v.reduce(0) { $0 + $1.darts.count }
        return darts == 0 ? 0 : Double(v.reduce(0) { $0 + $1.credited }) / Double(darts) * 3
    }
    public func best(for player: Int) -> Int { visits.filter { $0.player == player }.map(\.credited).max() ?? 0 }
    public var snapshot: GameSnapshot { GameSnapshot(states: states, active: active, starter: starter, leg: leg, legWinner: legWinner, winner: winner, finished: finished, visitCount: visits.count) }
    public var isSane: Bool {
        guard (1...4).contains(players.count), states.count == players.count, states.indices.contains(active), states.indices.contains(starter), config.legsToWin > 0, [101,301,501,701,1001].contains(config.startingScore), (1...30).contains(config.settings.countUpRounds), config.settings.botDelay.isFinite, (0.3...5).contains(config.settings.botDelay) else { return false }
        guard players.allSatisfy({ $0.botLevel == nil || (1...10).contains($0.botLevel!) }), states.allSatisfy({ $0.remaining >= 0 && (1...22).contains($0.clockTarget) }), visits.allSatisfy({ players.indices.contains($0.player) && (1...3).contains($0.darts.count) && $0.darts.allSatisfy(\.isValid) }) else { return false }
        guard winner.map({ players.indices.contains($0) }) ?? true, legWinner.map({ players.indices.contains($0) }) ?? true else { return false }
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
