import Foundation

/// Online zápas stažený z webu. Stejné id jako místní archiv po odchodu ze hry.
struct OnlineHistoryRecord: Decodable {
    struct Person: Decodable {
        var id: String
        var name: String
        var you: Bool
        var legs: Int
        var sets: Int
        var remaining: Int
    }

    struct Turn: Decodable {
        var player: Int
        var leg: Int
        var darts: [String]
        var score: Int
        var bust: Bool
        var checkout: Bool
        var remaining: Int
    }

    var id: String
    var forfeit: Bool
    var finished: Bool
    var playSeconds: Int
    var startedAt: String
    var finishedAt: String?
    var startingScore: Int
    var outRule: String
    var doubleIn: Bool
    var legsToWin: Int
    var setsToWin: Int
    var format: String
    var winner: Int?
    var players: [Person]
    var visits: [Turn]

    func match(owner: UUID) -> Match? {
        guard (2...4).contains(players.count) else { return nil }
        let config = GameConfig(
            mode: .x01,
            startingScore: startingScore,
            outRule: OutRule(rawValue: outRule) ?? .double,
            doubleIn: doubleIn,
            legsToWin: max(1, legsToWin),
            setsToWin: max(1, setsToWin),
            format: MatchFormat(rawValue: format) ?? .firstTo
        )
        let seats = players.enumerated().map { index, person in
            let seat: UUID
            if person.you {
                seat = owner
            } else if let parsed = UUID(uuidString: person.id) {
                seat = parsed
            } else {
                seat = AppStore.stableID(forOnlineMatch: person.id.isEmpty ? "seat-\(index)" : person.id)
            }
            return Player(id: seat, name: person.name)
        }
        var game = Match(config: config, players: seats)
        game.id = AppStore.stableID(forOnlineMatch: id)
        game.createdAt = Self.date(startedAt) ?? Date()
        game.completedAt = finishedAt.flatMap(Self.date) ?? game.createdAt
        game.finished = true
        game.playedOnline = true
        game.onlineForfeit = forfeit || winner == nil
        game.playSeconds = Double(max(0, playSeconds))
        game.winner = winner.flatMap { seats.indices.contains($0) ? $0 : nil }
        if game.winner == nil { game.onlineForfeit = true }
        for (index, person) in players.enumerated() {
            game.states[index].remaining = person.remaining
            game.states[index].legs = person.legs
            game.states[index].sets = person.sets
        }
        game.visits = visits.compactMap { turn in
            guard seats.indices.contains(turn.player) else { return nil }
            return Visit(
                player: turn.player,
                leg: max(1, turn.leg),
                darts: turn.darts.map(Self.dart),
                credited: turn.score,
                bust: turn.bust,
                checkout: turn.checkout,
                remaining: turn.remaining
            )
        }
        game.undoStack = []
        return game
    }

    private static func date(_ text: String) -> Date? {
        let parser = ISO8601DateFormatter()
        parser.formatOptions = [.withInternetDateTime]
        return parser.date(from: text)
    }

    private static func dart(_ label: String) -> Dart {
        switch label {
        case "MISS": return .miss
        case "BULL": return Dart(25, 2)
        case "25": return Dart(25)
        default:
            guard let mark = label.first, let segment = Int(label.dropFirst()), (1...20).contains(segment) else { return .miss }
            let multiplier = mark == "T" ? 3 : mark == "D" ? 2 : 1
            return Dart(segment, multiplier)
        }
    }
}
