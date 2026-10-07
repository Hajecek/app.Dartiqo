import Foundation

public struct BotLevel: Identifiable {
    public let id: Int
    public let name: String
    public let precision: Double
    public static let all: [BotLevel] = [
        .init(id: 1, name: "První šipky", precision: 0.035), .init(id: 2, name: "Začátečník", precision: 0.07),
        .init(id: 3, name: "Hospodský hráč", precision: 0.12), .init(id: 4, name: "Pravidelný hráč", precision: 0.18),
        .init(id: 5, name: "Klubový hráč", precision: 0.25), .init(id: 6, name: "Ligový hráč", precision: 0.32),
        .init(id: 7, name: "Expert", precision: 0.39), .init(id: 8, name: "Mistr", precision: 0.46),
        .init(id: 9, name: "Profesionál", precision: 0.53), .init(id: 10, name: "Legenda", precision: 0.60)
    ]
    public static func get(_ level: Int) -> BotLevel { all[min(9, max(0, level - 1))] }
}
public enum Bot {
    private static let board = [20,1,18,4,13,6,10,15,2,17,3,19,7,16,8,11,14,9,12,5]
    public static func target(in game: Match, dartsLeft: Int) -> Dart {
        let state = game.currentState
        switch game.config.mode {
        case .x01:
            if !state.opened { return Dart(20, 2) }
            if let route = Checkout.route(for: state.remaining, rule: game.config.outRule, darts: dartsLeft) { return route[0] }
            if state.remaining > 60 { return Dart(20,3) }
            // Leave a familiar double; never deliberately strand one.
            let safe = state.remaining - 32
            if (1...20).contains(safe) { return Dart(safe) }
            return Dart(state.remaining > 40 ? 20 : max(1, state.remaining - 2))
        case .cricket:
            let numbers = [20,19,18,17,16,15,25]
            if let open = numbers.first(where: { state.marks[$0, default: 0] < 3 }) { return Dart(open, open == 25 ? 2 : 3) }
            if let scoring = numbers.first(where: { n in game.states.indices.contains { $0 != game.active && game.states[$0].marks[n, default: 0] < 3 } }) { return Dart(scoring, scoring == 25 ? 2 : 3) }
            return Dart(25,2)
        case .aroundClock:
            if state.clockTarget == 21 { return Dart(25, game.config.settings.clockStyle == .any ? 1 : 2) }
            return Dart(min(20,state.clockTarget), game.config.settings.clockStyle == .any ? 1 : game.config.settings.clockStyle == .doubles ? 2 : 3)
        case .countUp: return Dart(20,3)
        }
    }
    public static func throwDart<R: RandomNumberGenerator>(at target: Dart, level: Int, using rng: inout R) -> Dart {
        let p = BotLevel.get(level).precision
        let exact = target.multiplier == 1 ? min(0.98, p + 0.25) : target.multiplier == 2 ? p * 0.9 + 0.05 : p
        if Double.random(in: 0..<1, using: &rng) < exact { return target }
        let miss = Double.random(in: 0..<1, using: &rng)
        if miss < 0.38 - p * 0.40 { return .miss }
        if target.segment == 25 { return miss < 0.58 ? Dart(25) : Dart(Int.random(in: 1...20, using: &rng)) }
        if miss < 0.64 { return Dart(target.segment) }
        let index = board.firstIndex(of: target.segment) ?? 0
        let offset = Bool.random(using: &rng) ? 1 : 19
        return Dart(board[(index + offset) % 20], miss > 0.94 ? target.multiplier : 1)
    }
    public static func visit<R: RandomNumberGenerator>(in game: Match, using rng: inout R) -> [Dart] {
        var darts: [Dart] = []
        for _ in 0..<3 {
            var simulated = game
            if !darts.isEmpty {
                try? simulated.submit(darts, allowPartial: true)
                if simulated.visits.last?.bust == true || simulated.legWinner != nil { break }
                simulated.active = game.active
            }
            darts.append(throwDart(at: target(in: simulated, dartsLeft: 3 - darts.count), level: game.currentPlayer.botLevel ?? 1, using: &rng))
        }
        return darts
    }
}
