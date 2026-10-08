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
    public var clockStyle = ClockStyle.any
    public var botDelay = 1.5
    public var checkoutHints = true
    public var keepAwake = true
    public init() {}
}
public struct SeatDraft: Codable, Identifiable, Equatable {
    public var id = UUID()
    public var name: String
    public var isBot: Bool
    public var level: Int
    public var handicap: Handicap?
    /// Přítel nebo profil z tohoto telefonu. Zápas se pak započítá pod stejné ID.
    public var friendID: UUID?
    public init(name: String, isBot: Bool = false, level: Int = 3, friendID: UUID? = nil) {
        self.name = name; self.isBot = isBot; self.level = level; self.friendID = friendID
    }
}
public struct SetupDraft: Codable, Equatable {
    public var config = GameConfig()
    public var seats = [SeatDraft(name: "Já"), SeatDraft(name: "Bot", isBot: true)]
    public var starter = 0 // -1 means random; otherwise explicit roster position
    /// `true` znamená, že první místo nepatří vlastníkovi profilu.
    public var withoutMe: Bool?
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
        guard legWinner == nil else { throw GameError.legEnded }
        guard (0...180).contains(score) else { throw ScoreEntryError.impossible }
        let remaining = currentState.remaining
        let rule = config.outRule(for: active)
        if score > remaining || (remaining - score == 1 && rule != .straight) { throw ScoreEntryError.useBust }
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
        guard legWinner == nil else { throw GameError.legEnded }
        guard (1...3).contains(darts) else { throw GameError.invalidDarts }
        guard canBust(remaining: currentState.remaining, darts: darts) else { throw ScoreEntryError.invalidBust }
        undoStack.append(snapshot)
        states[active].rounds += 1
        visits.append(Visit(player: active, leg: leg, darts: Array(repeating: .miss, count: darts), credited: 0, bust: true, checkout: false, remaining: currentState.remaining, enteredAsTotal: true))
        active = (active + 1) % players.count
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
