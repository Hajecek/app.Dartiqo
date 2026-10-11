import Foundation

/// Identita soupeře napříč zápasy (boti mají pokaždé nové UUID).
public struct RivalKey: Hashable, Codable, Identifiable {
    public enum Kind: Hashable, Codable {
        case person(UUID)
        case bot(Int)
        case ghost(String)
    }

    public var kind: Kind
    public var id: String {
        switch kind {
        case .person(let id): return "p-\(id.uuidString)"
        case .bot(let level): return "b-\(level)"
        case .ghost(let raw): return "g-\(raw)"
        }
    }

    public static func of(opponent: Player, in match: Match) -> RivalKey {
        if let level = opponent.botLevel { return RivalKey(kind: .bot(level)) }
        if let idx = match.ghostPlayerIndex,
           match.players.indices.contains(idx),
           match.players[idx].id == opponent.id {
            return RivalKey(kind: .ghost(match.ghostKind?.rawValue ?? "ghost"))
        }
        return RivalKey(kind: .person(opponent.id))
    }

    /// Identita soupeře ze sestavy před startem zápasu.
    public static func from(seat: SeatDraft, ghostKind: GhostKind?) -> RivalKey? {
        if seat.isBot { return RivalKey(kind: .bot(seat.level)) }
        if seat.ghostSeat { return RivalKey(kind: .ghost(ghostKind?.rawValue ?? "ghost")) }
        if let id = seat.friendID { return RivalKey(kind: .person(id)) }
        return nil
    }
}

public enum H2HOutcome: String, CaseIterable, Identifiable {
    case win, loss, draw
    public var id: String { rawValue }
    public var short: String {
        switch self { case .win: return "V"; case .loss: return "P"; case .draw: return "R" }
    }
    public var title: String {
        switch self { case .win: return "Výhra"; case .loss: return "Prohra"; case .draw: return "Remíza" }
    }
}

/// Bod křivky kumulativních výher (od nejstaršího zápasu).
public struct H2HFormPoint: Identifiable, Equatable {
    public var id: Int
    public var game: Int
    public var myWins: Int
    public var theirWins: Int
}

/// Bilance tebe proti jednomu soupeři.
public struct HeadToHead: Identifiable {
    public var key: RivalKey
    public var opponentName: String
    public var opponentBotLevel: Int?
    public var isGhost: Bool
    /// Nejnovější první.
    public var matches: [Match]
    public var myWins: Int
    public var theirWins: Int
    public var draws: Int

    public var id: String { key.id }
    public var played: Int { matches.count }
    public var lastMatch: Match? { matches.first }

    public var myWinRate: Double {
        let decided = myWins + theirWins
        return decided == 0 ? 0 : Double(myWins) / Double(decided)
    }

    public var recordLine: String {
        "\(myWins) : \(theirWins)"
    }

    public var standingTitle: String {
        if played == 0 { return "První vzájemný zápas" }
        if myWins > theirWins { return "Vedeš" }
        if myWins < theirWins { return "Prohráváš" }
        return "Vyrovnáno"
    }

    public static func empty(key: RivalKey, name: String, botLevel: Int? = nil, isGhost: Bool = false) -> HeadToHead {
        HeadToHead(
            key: key,
            opponentName: name,
            opponentBotLevel: botLevel,
            isGhost: isGhost,
            matches: [],
            myWins: 0,
            theirWins: 0,
            draws: 0
        )
    }

    public func outcome(of match: Match, me: UUID) -> H2HOutcome {
        guard let mine = match.players.firstIndex(where: { $0.id == me }),
              let theirs = match.players.indices.first(where: {
                  $0 != mine && Self.matchesKey(key, opponent: match.players[$0], match: match)
              })
        else { return .draw }
        if let winner = match.winner {
            if winner == mine { return .win }
            if winner == theirs { return .loss }
        }
        return .draw
    }

    /// Od nejstaršího po nejnovější.
    public func outcomesChronological(me: UUID) -> [H2HOutcome] {
        matches.reversed().map { outcome(of: $0, me: me) }
    }

    public func formPoints(me: UUID) -> [H2HFormPoint] {
        var mine = 0, theirs = 0
        return outcomesChronological(me: me).enumerated().map { index, outcome in
            switch outcome {
            case .win: mine += 1
            case .loss: theirs += 1
            case .draw: break
            }
            return H2HFormPoint(id: index, game: index + 1, myWins: mine, theirWins: theirs)
        }
    }

    public func scoreLine(of match: Match, me: UUID) -> String {
        guard let mine = match.players.firstIndex(where: { $0.id == me }),
              let theirs = match.players.indices.first(where: {
                  $0 != mine && Self.matchesKey(key, opponent: match.players[$0], match: match)
              })
        else { return match.config.summary }
        let myUnits = match.config.playsSets ? match.states[mine].sets : match.states[mine].legs
        let theirUnits = match.config.playsSets ? match.states[theirs].sets : match.states[theirs].legs
        return "\(myUnits) : \(theirUnits)"
    }

    public func myAverage(me: UUID) -> Double? {
        let x01 = matches.filter { $0.config.mode == .x01 }
        guard !x01.isEmpty else { return nil }
        var points = 0, darts = 0
        for match in x01 {
            guard let i = match.players.firstIndex(where: { $0.id == me }) else { continue }
            let visits = match.visits.filter { $0.player == i }
            points += visits.reduce(0) { $0 + $1.credited }
            darts += visits.reduce(0) { $0 + $1.darts.count }
        }
        return darts == 0 ? nil : Double(points) * 3 / Double(darts)
    }

    public func theirAverage(me: UUID) -> Double? {
        let x01 = matches.filter { $0.config.mode == .x01 }
        guard !x01.isEmpty else { return nil }
        var points = 0, darts = 0
        for match in x01 {
            guard let mine = match.players.firstIndex(where: { $0.id == me }),
                  let theirs = match.players.indices.first(where: { $0 != mine && Self.matchesKey(key, opponent: match.players[$0], match: match) })
            else { continue }
            let visits = match.visits.filter { $0.player == theirs }
            points += visits.reduce(0) { $0 + $1.credited }
            darts += visits.reduce(0) { $0 + $1.darts.count }
        }
        return darts == 0 ? nil : Double(points) * 3 / Double(darts)
    }

    public func myCheckout(me: UUID) -> CheckoutStats {
        var stats = CheckoutStats()
        for match in matches where match.config.mode == .x01 {
            guard let i = match.players.firstIndex(where: { $0.id == me }) else { continue }
            stats.merge(CheckoutStats.make(from: match, player: i))
        }
        return stats
    }

    public func theirCheckout(me: UUID) -> CheckoutStats {
        var stats = CheckoutStats()
        for match in matches where match.config.mode == .x01 {
            guard let mine = match.players.firstIndex(where: { $0.id == me }),
                  let theirs = match.players.indices.first(where: {
                      $0 != mine && Self.matchesKey(key, opponent: match.players[$0], match: match)
                  })
            else { continue }
            stats.merge(CheckoutStats.make(from: match, player: theirs))
        }
        return stats
    }

    public static func rivals(from all: [Match], me: UUID) -> [HeadToHead] {
        var keys: [RivalKey] = []
        var seen = Set<RivalKey>()
        for match in all where match.finished && match.players.contains(where: { $0.id == me }) {
            for player in match.players where player.id != me {
                let key = RivalKey.of(opponent: player, in: match)
                guard !seen.contains(key) else { continue }
                seen.insert(key)
                keys.append(key)
            }
        }
        return keys.compactMap { series(from: all, me: me, key: $0) }
            .sorted { ($0.lastMatch?.completedAt ?? .distantPast) > ($1.lastMatch?.completedAt ?? .distantPast) }
    }

    public static func series(from all: [Match], me: UUID, key: RivalKey) -> HeadToHead? {
        let games = all
            .filter { match in
                guard match.finished, match.players.contains(where: { $0.id == me }) else { return false }
                return match.players.contains { $0.id != me && matchesKey(key, opponent: $0, match: match) }
            }
            .sorted { ($0.completedAt ?? $0.createdAt) > ($1.completedAt ?? $1.createdAt) }
        guard let latest = games.first,
              let opp = latest.players.first(where: { $0.id != me && matchesKey(key, opponent: $0, match: latest) })
        else { return nil }

        var mine = 0, theirs = 0, draws = 0
        for match in games {
            guard let myIndex = match.players.firstIndex(where: { $0.id == me }),
                  let theirIndex = match.players.indices.first(where: { $0 != myIndex && matchesKey(key, opponent: match.players[$0], match: match) })
            else { continue }
            if let winner = match.winner {
                if winner == myIndex { mine += 1 }
                else if winner == theirIndex { theirs += 1 }
                else { draws += 1 } // výhra třetího hráče
            } else {
                draws += 1
            }
        }

        return HeadToHead(
            key: key,
            opponentName: opp.name,
            opponentBotLevel: opp.botLevel,
            isGhost: matchIsGhostOpponent(opp, match: latest),
            matches: games,
            myWins: mine,
            theirWins: theirs,
            draws: draws
        )
    }

    public static func key(forOpponentIn match: Match, me: UUID) -> RivalKey? {
        guard let opp = match.players.first(where: { $0.id != me }) else { return nil }
        // U 3+ hráčů vezmi prvního jiného — detail si uživatel otevře ze seznamu.
        return RivalKey.of(opponent: opp, in: match)
    }

    private static func matchesKey(_ key: RivalKey, opponent: Player, match: Match) -> Bool {
        RivalKey.of(opponent: opponent, in: match) == key
    }

    private static func matchIsGhostOpponent(_ opponent: Player, match: Match) -> Bool {
        match.ghostPlayerIndex.map { match.players.indices.contains($0) && match.players[$0].id == opponent.id } == true
    }
}
