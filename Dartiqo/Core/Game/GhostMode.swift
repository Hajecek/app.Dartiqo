import Foundation

/// Zdroj ghosta v klasickém X01.
public enum GhostKind: String, Codable, CaseIterable, Identifiable {
    case best, last, yesterday, beatPB
    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .best: return "Nejlepší zápas"
        case .last: return "Poslední zápas"
        case .yesterday: return "Včerejší já"
        case .beatPB: return "Překonej PB"
        }
    }

    public var detail: String {
        switch self {
        case .best: return "Tvoje nejvyšší průměr v X01"
        case .last: return "Nejnovější dohraný X01"
        case .yesterday: return "Poslední X01 ze včerejška"
        case .beatPB: return "Stejný ghost, sleduj průměr"
        }
    }

    public var symbol: String {
        switch self {
        case .best: return "trophy.fill"
        case .last: return "clock.arrow.circlepath"
        case .yesterday: return "calendar"
        case .beatPB: return "chart.line.uptrend.xyaxis"
        }
    }
}

/// Nabídka konkrétního ghosta z historie.
public struct GhostOffer: Identifiable, Equatable {
    public var kind: GhostKind
    public var sourceID: UUID
    public var playerIndex: Int
    public var average: Double
    public var finishedAt: Date
    public var visits: [[Dart]]
    public var id: String { kind.rawValue }

    public var displayName: String {
        "Ghost · \(String(format: "%.1f", average))"
    }

    public var averageText: String {
        String(format: "%.1f", average)
    }
}

/// Výběr a sestavení ghosta z dokončených X01 zápasů.
public enum GhostMode {
    private struct Row {
        var match: Match
        var playerIndex: Int
        var average: Double
        var finishedAt: Date { match.completedAt ?? match.createdAt }
    }

    /// Dokončené X01 se stejným startem a out, kde hráč hodil aspoň jednu šipku.
    private static func pool(
        matches: [Match],
        playerID: UUID,
        startingScore: Int,
        outRule: OutRule
    ) -> [Row] {
        matches.compactMap { match -> Row? in
            guard match.finished, match.config.mode == .x01 else { return nil }
            guard match.config.startingScore == startingScore, match.config.outRule == outRule else { return nil }
            guard let index = match.players.firstIndex(where: { $0.id == playerID }) else { return nil }
            let darts = match.visits.filter { $0.player == index }.reduce(0) { $0 + $1.darts.count }
            guard darts > 0 else { return nil }
            return Row(match: match, playerIndex: index, average: match.average(for: index))
        }
    }

    public static func offer(
        kind: GhostKind,
        matches: [Match],
        playerID: UUID,
        startingScore: Int,
        outRule: OutRule,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> GhostOffer? {
        let rows = pool(matches: matches, playerID: playerID, startingScore: startingScore, outRule: outRule)
        guard !rows.isEmpty else { return nil }
        let picked: Row?
        switch kind {
        case .best, .beatPB:
            picked = rows.max(by: { $0.average < $1.average })
        case .last:
            picked = rows.max(by: { $0.finishedAt < $1.finishedAt })
        case .yesterday:
            guard let yesterday = calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: now)) else { return nil }
            let day = rows.filter { calendar.isDate($0.finishedAt, inSameDayAs: yesterday) }
            picked = day.max(by: { $0.finishedAt < $1.finishedAt })
        }
        guard let row = picked else { return nil }
        return GhostOffer(
            kind: kind,
            sourceID: row.match.id,
            playerIndex: row.playerIndex,
            average: row.average,
            finishedAt: row.finishedAt,
            visits: script(from: row.match, playerIndex: row.playerIndex)
        )
    }

    public static func offers(
        matches: [Match],
        playerID: UUID,
        startingScore: Int,
        outRule: OutRule,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> [GhostOffer] {
        GhostKind.allCases.compactMap {
            offer(kind: $0, matches: matches, playerID: playerID, startingScore: startingScore, outRule: outRule, now: now, calendar: calendar)
        }
    }

    /// Návštěvy hráče v pořadí, jak padly v zápase.
    public static func script(from match: Match, playerIndex: Int) -> [[Dart]] {
        match.visits.filter { $0.player == playerIndex }.map(\.darts)
    }

    /// Další šipka ghosta. Po vyčerpání skriptu MISS.
    public static func nextDart(in match: Match) -> Dart {
        guard let player = match.ghostPlayerIndex,
              match.active == player,
              let visits = match.ghostVisits,
              !visits.isEmpty
        else { return .miss }
        let index = match.ghostVisitIndex ?? 0
        guard index < visits.count else { return .miss }
        let visit = visits[index]
        let dartIndex = match.currentDarts.count
        guard dartIndex < visit.count else { return .miss }
        return visit[dartIndex]
    }
}
