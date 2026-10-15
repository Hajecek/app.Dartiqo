import Foundation

/// Skupina nabídek ve výběru ghosta.
public enum GhostCategory: String, CaseIterable, Identifiable {
    case day, form, record, smart, match
    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .day: return "Dnes a včera"
        case .form: return "Forma"
        case .record: return "Rekordy"
        case .smart: return "Chytrý ghost"
        case .match: return "Přesný zápas"
        }
    }
}

/// Zdroj ghosta v klasickém X01.
public enum GhostKind: String, Codable, CaseIterable, Identifiable {
    case best, last, yesterday, beatPB
    case today, weekBest, monthBest
    case mirror
    case pickMatch

    public var id: String { rawValue }

    public var category: GhostCategory {
        switch self {
        case .today, .yesterday: return .day
        case .last, .weekBest, .monthBest: return .form
        case .best, .beatPB: return .record
        case .mirror: return .smart
        case .pickMatch: return .match
        }
    }

    /// Varianty v katalogu (bez ručního výběru zápasu).
    public static var catalog: [GhostKind] {
        [.today, .yesterday, .last, .weekBest, .monthBest, .best, .beatPB, .mirror]
    }

    public var title: String {
        switch self {
        case .best: return "Nejlepší zápas"
        case .last: return "Poslední zápas"
        case .yesterday: return "Včerejší já"
        case .today: return "Dnešní já"
        case .weekBest: return "Nejlepší týden"
        case .monthBest: return "Nejlepší měsíc"
        case .beatPB: return "Překonej PB"
        case .mirror: return "Zrcadlo stylu"
        case .pickMatch: return "Vybraný zápas"
        }
    }

    public var detail: String {
        switch self {
        case .best: return "Tvoje nejvyšší průměr v X01"
        case .last: return "Nejnovější dohraný X01"
        case .yesterday: return "Poslední X01 ze včerejška"
        case .today: return "Poslední X01 z dneška"
        case .weekBest: return "Nejlepší průměr za posledních 7 dní"
        case .monthBest: return "Nejlepší průměr za posledních 30 dní"
        case .beatPB: return "Stejný ghost, sleduj průměr"
        case .mirror: return "Učí se tvůj styl a hraje podle vyhodnocení učení"
        case .pickMatch: return "Přesně jeden zápas z historie"
        }
    }

    public var symbol: String {
        switch self {
        case .best: return "trophy.fill"
        case .last: return "clock.arrow.circlepath"
        case .yesterday: return "calendar"
        case .today: return "sun.max.fill"
        case .weekBest: return "calendar.badge.clock"
        case .monthBest: return "calendar.circle.fill"
        case .beatPB: return "chart.line.uptrend.xyaxis"
        case .mirror: return "person.and.background.dotted"
        case .pickMatch: return "list.bullet.rectangle"
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
    public var locked = false
    public var unlockHint: String?
    public var styleNote: String?

    public var id: String {
        kind == .pickMatch ? "\(kind.rawValue)-\(sourceID.uuidString)" : kind.rawValue
    }

    public var displayName: String {
        switch kind {
        case .mirror: return "Zrcadlo · \(averageText)"
        case .pickMatch: return "Zápas · \(averageText)"
        default: return "Ghost · \(averageText)"
        }
    }

    public var averageText: String {
        String(format: "%.1f", average)
    }
}

/// Profil stylu hráče pro chytrého ghosta.
public struct GhostStyleProfile: Equatable {
    public var matchCount: Int
    public var averageOfAverages: Double
    public var checkoutRate: Double
    public var favoriteDoubles: [Int]
    public var scoringVisits: [[Dart]]
    public var setupVisits: [[Dart]]
    public var learningConfidence: Double = 0
    public var learningLabel: String = ""

    public var styleNote: String {
        let doubles = favoriteDoubles.prefix(3).map { $0 == 25 ? "Bull" : "D\($0)" }.joined(separator: " · ")
        let rate = Int((checkoutRate * 100).rounded())
        let base = doubles.isEmpty ? "Checkout \(rate) %" : "\(doubles) · checkout \(rate) %"
        if learningLabel.isEmpty { return base }
        return "\(base) · \(learningLabel)"
    }
}

/// Trvalé učení Zrcadla stylu — EMA průměru, doubly, checkouty a typické návštěvy.
public struct GhostStyleMemory: Codable, Equatable {
    public var owner: UUID
    public var startingScore: Int
    public var outRule: OutRule
    public var samplesSeen = 0
    public var averageEMA = 0.0
    public var checkoutHits = 0
    public var checkoutAttempts = 0
    public var doubleCounts: [String: Int] = [:]
    public var scoringVisits: [[Dart]] = []
    public var setupVisits: [[Dart]] = []
    public var lastTrainedAt: Date?

    public static func key(owner: UUID, startingScore: Int, outRule: OutRule) -> String {
        "\(owner.uuidString)|\(startingScore)|\(outRule.rawValue)"
    }

    public var storageKey: String { Self.key(owner: owner, startingScore: startingScore, outRule: outRule) }

    /// 0…1 — čím víc zápasů, tím jistější hra zrcadla.
    public var confidence: Double { min(1, Double(samplesSeen) / 12) }

    public var checkoutRate: Double {
        guard checkoutAttempts > 0 else { return 0.35 }
        return min(0.85, max(0.12, Double(checkoutHits) / Double(checkoutAttempts)))
    }

    public var favoriteDoubles: [Int] {
        doubleCounts
            .compactMap { key, value -> (Int, Int)? in
                guard let seg = Int(key) else { return nil }
                return (seg, value)
            }
            .sorted { lhs, rhs in
                if lhs.1 != rhs.1 { return lhs.1 > rhs.1 }
                return lhs.0 > rhs.0
            }
            .prefix(5)
            .map(\.0)
    }

    public var evaluationLabel: String {
        let pct = Int((confidence * 100).rounded())
        if samplesSeen < 3 { return "učení \(pct) % · start" }
        if confidence < 0.45 { return "učení \(pct) % · sbírá styl" }
        if confidence < 0.75 { return "učení \(pct) % · stabilní" }
        return "učení \(pct) % · jistý styl"
    }

    public mutating func learn(from match: Match, playerIndex: Int) {
        let avg = match.average(for: playerIndex)
        if samplesSeen == 0 { averageEMA = avg }
        else { averageEMA = averageEMA * 0.82 + avg * 0.18 }
        samplesSeen += 1

        let mine = match.visits.filter { $0.player == playerIndex }
        for (offset, visit) in mine.enumerated() {
            let before = offset == 0
                ? match.config.startingScore(for: playerIndex)
                : mine[offset - 1].remaining
            if before <= 170 && before > 1 {
                checkoutAttempts += 1
                if visit.checkout {
                    checkoutHits += 1
                    if let last = visit.darts.last, last.multiplier == 2,
                       (1...20).contains(last.segment) || last.segment == 25 {
                        let key = String(last.segment == 25 ? 25 : last.segment)
                        doubleCounts[key, default: 0] += 1
                    }
                }
            }
            if visit.checkout == false, visit.credited >= 40 {
                scoringVisits.append(visit.darts)
            }
            let leave = visit.remaining
            if !visit.checkout, leave > 1, leave <= 40, leave % 2 == 0 {
                setupVisits.append(visit.darts)
            }
        }
        if scoringVisits.count > 48 { scoringVisits = Array(scoringVisits.suffix(48)) }
        if setupVisits.count > 32 { setupVisits = Array(setupVisits.suffix(32)) }
        lastTrainedAt = Date()
    }

    /// Spojí trvalé učení s aktuálním snímkem historie — podle confidence víc věří paměti.
    public func evaluatedProfile(blending snapshot: GhostStyleProfile) -> GhostStyleProfile {
        let w = confidence
        let avg = averageEMA * w + snapshot.averageOfAverages * (1 - w)
        let rate = checkoutRate * w + snapshot.checkoutRate * (1 - w)
        let doubles = favoriteDoubles.isEmpty ? snapshot.favoriteDoubles : favoriteDoubles
        let scoring = scoringVisits.isEmpty ? snapshot.scoringVisits : scoringVisits
        let setups = setupVisits.isEmpty ? snapshot.setupVisits : setupVisits
        return GhostStyleProfile(
            matchCount: max(snapshot.matchCount, samplesSeen),
            averageOfAverages: avg,
            checkoutRate: min(0.85, max(0.12, rate)),
            favoriteDoubles: doubles,
            scoringVisits: scoring,
            setupVisits: setups,
            learningConfidence: confidence,
            learningLabel: evaluationLabel
        )
    }
}

/// Výběr a sestavení ghosta z dokončených X01 zápasů.
public enum GhostMode {
    /// Po tolika dohraných X01 se stejným startem/out se odemkne Zrcadlo stylu.
    public static let mirrorUnlockCount = 5

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

    public static func mirrorUnlocked(
        matches: [Match],
        playerID: UUID,
        startingScore: Int,
        outRule: OutRule
    ) -> Bool {
        pool(matches: matches, playerID: playerID, startingScore: startingScore, outRule: outRule).count >= mirrorUnlockCount
    }

    public static func offer(
        kind: GhostKind,
        matches: [Match],
        playerID: UUID,
        startingScore: Int,
        outRule: OutRule,
        matchID: UUID? = nil,
        memory: GhostStyleMemory? = nil,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> GhostOffer? {
        if kind == .mirror {
            return mirrorOffer(
                matches: matches,
                playerID: playerID,
                startingScore: startingScore,
                outRule: outRule,
                memory: memory
            )
        }
        if kind == .pickMatch {
            guard let matchID else { return nil }
            return pickMatchOffer(
                matchID: matchID,
                matches: matches,
                playerID: playerID,
                startingScore: startingScore,
                outRule: outRule
            )
        }

        let rows = pool(matches: matches, playerID: playerID, startingScore: startingScore, outRule: outRule)
        guard !rows.isEmpty else { return nil }
        let picked: Row?
        switch kind {
        case .best, .beatPB:
            picked = rows.max(by: { $0.average < $1.average })
        case .last:
            picked = rows.max(by: { $0.finishedAt < $1.finishedAt })
        case .today:
            let day = rows.filter { calendar.isDate($0.finishedAt, inSameDayAs: now) }
            picked = day.max(by: { $0.finishedAt < $1.finishedAt })
        case .yesterday:
            guard let yesterday = calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: now)) else { return nil }
            let day = rows.filter { calendar.isDate($0.finishedAt, inSameDayAs: yesterday) }
            picked = day.max(by: { $0.finishedAt < $1.finishedAt })
        case .weekBest:
            guard let from = calendar.date(byAdding: .day, value: -7, to: now) else { return nil }
            let week = rows.filter { $0.finishedAt >= from }
            picked = week.max(by: { $0.average < $1.average })
        case .monthBest:
            guard let from = calendar.date(byAdding: .day, value: -30, to: now) else { return nil }
            let month = rows.filter { $0.finishedAt >= from }
            picked = month.max(by: { $0.average < $1.average })
        case .mirror, .pickMatch:
            picked = nil
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
        memory: GhostStyleMemory? = nil,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> [GhostOffer] {
        var result: [GhostOffer] = []
        for kind in GhostKind.catalog {
            if let offer = offer(
                kind: kind,
                matches: matches,
                playerID: playerID,
                startingScore: startingScore,
                outRule: outRule,
                memory: memory,
                now: now,
                calendar: calendar
            ) {
                result.append(offer)
            } else if kind == .mirror {
                let count = pool(matches: matches, playerID: playerID, startingScore: startingScore, outRule: outRule).count
                let learned = memory.map { " Učení: \($0.evaluationLabel)." } ?? ""
                result.append(
                    GhostOffer(
                        kind: .mirror,
                        sourceID: UUID(),
                        playerIndex: 0,
                        average: 0,
                        finishedAt: now,
                        visits: [],
                        locked: true,
                        unlockHint: "Odemkne se po \(mirrorUnlockCount) X01 se stejným startem. Máš \(count)/\(mirrorUnlockCount).\(learned)"
                    )
                )
            }
        }
        return result
    }

    /// Poslední zápasy pro přesný výběr.
    public static func matchCandidates(
        matches: [Match],
        playerID: UUID,
        startingScore: Int,
        outRule: OutRule,
        limit: Int = 12
    ) -> [GhostOffer] {
        pool(matches: matches, playerID: playerID, startingScore: startingScore, outRule: outRule)
            .sorted { $0.finishedAt > $1.finishedAt }
            .prefix(limit)
            .map { row in
                GhostOffer(
                    kind: .pickMatch,
                    sourceID: row.match.id,
                    playerIndex: row.playerIndex,
                    average: row.average,
                    finishedAt: row.finishedAt,
                    visits: script(from: row.match, playerIndex: row.playerIndex),
                    styleNote: row.finishedAt.formatted(date: .abbreviated, time: .shortened)
                )
            }
    }

    private static func pickMatchOffer(
        matchID: UUID,
        matches: [Match],
        playerID: UUID,
        startingScore: Int,
        outRule: OutRule
    ) -> GhostOffer? {
        matchCandidates(matches: matches, playerID: playerID, startingScore: startingScore, outRule: outRule, limit: 80)
            .first { $0.sourceID == matchID }
    }

    private static func mirrorOffer(
        matches: [Match],
        playerID: UUID,
        startingScore: Int,
        outRule: OutRule,
        memory: GhostStyleMemory?
    ) -> GhostOffer? {
        let rows = pool(matches: matches, playerID: playerID, startingScore: startingScore, outRule: outRule)
        guard rows.count >= mirrorUnlockCount else { return nil }
        let snapshot = styleProfile(rows: rows)
        let profile = memory?.evaluatedProfile(blending: snapshot) ?? snapshot
        let seedBase: Int
        if let memory {
            seedBase = memory.samplesSeen * 97 &+ Int(memory.averageEMA * 10)
        } else {
            seedBase = rows.count
        }
        var rng = SplitMix64(seed: UInt64(bitPattern: Int64(seedBase * 31 &+ startingScore)))
        let visits = synthesizeMirror(
            profile: profile,
            startingScore: startingScore,
            outRule: outRule,
            rng: &rng
        )
        return GhostOffer(
            kind: .mirror,
            sourceID: rows.map(\.match.id).sorted { $0.uuidString < $1.uuidString }.first ?? UUID(),
            playerIndex: rows[0].playerIndex,
            average: profile.averageOfAverages,
            finishedAt: rows.map(\.finishedAt).max() ?? Date(),
            visits: visits,
            styleNote: profile.styleNote
        )
    }

    public static func styleProfile(
        matches: [Match],
        playerID: UUID,
        startingScore: Int,
        outRule: OutRule
    ) -> GhostStyleProfile? {
        let rows = pool(matches: matches, playerID: playerID, startingScore: startingScore, outRule: outRule)
        guard !rows.isEmpty else { return nil }
        return styleProfile(rows: rows)
    }

    private static func styleProfile(rows: [Row]) -> GhostStyleProfile {
        let averages = rows.map(\.average)
        let averageOfAverages = averages.reduce(0, +) / Double(averages.count)

        var doubleCounts: [Int: Int] = [:]
        var checkoutHits = 0
        var checkoutAttempts = 0
        var scoring: [[Dart]] = []
        var setups: [[Dart]] = []

        for row in rows {
            let mine = row.match.visits.filter { $0.player == row.playerIndex }
            for (offset, visit) in mine.enumerated() {
                let before = offset == 0
                    ? row.match.config.startingScore(for: row.playerIndex)
                    : mine[offset - 1].remaining
                if before <= 170 && before > 1 {
                    checkoutAttempts += 1
                    if visit.checkout {
                        checkoutHits += 1
                        if let last = visit.darts.last, last.multiplier == 2, (1...20).contains(last.segment) || last.segment == 25 {
                            doubleCounts[last.segment == 25 ? 25 : last.segment, default: 0] += 1
                        }
                    }
                }
                if visit.checkout == false, visit.credited >= 40 {
                    scoring.append(visit.darts)
                }
                let leave = visit.remaining
                if !visit.checkout, leave > 1, leave <= 40, leave % 2 == 0 {
                    setups.append(visit.darts)
                }
            }
        }

        let favorites = doubleCounts
            .sorted { lhs, rhs in
                if lhs.value != rhs.value { return lhs.value > rhs.value }
                return lhs.key > rhs.key
            }
            .prefix(5)
            .map(\.key)

        let rate = checkoutAttempts == 0 ? 0.35 : Double(checkoutHits) / Double(checkoutAttempts)
        return GhostStyleProfile(
            matchCount: rows.count,
            averageOfAverages: averageOfAverages,
            checkoutRate: min(0.85, max(0.12, rate)),
            favoriteDoubles: Array(favorites),
            scoringVisits: Array(scoring.suffix(40)),
            setupVisits: Array(setups.suffix(24))
        )
    }

    /// Syntetický průběh legů podle stylu hráče.
    public static func synthesizeMirror(
        profile: GhostStyleProfile,
        startingScore: Int,
        outRule: OutRule,
        rng: inout some RandomNumberGenerator
    ) -> [[Dart]] {
        var remaining = startingScore
        var visits: [[Dart]] = []
        let targetVisit = max(18, min(100, profile.averageOfAverages))
        var guardCounter = 0

        while remaining > 0 && visits.count < 90 && guardCounter < 120 {
            guardCounter += 1
            if remaining <= 170,
               Double.random(in: 0..<1, using: &rng) < profile.checkoutRate,
               let finish = preferredCheckout(remaining: remaining, rule: outRule, favorites: profile.favoriteDoubles) {
                let outcome = ScoringRules.applyVisit(
                    remaining: remaining, opened: true, darts: finish, rule: outRule, doubleIn: false
                )
                visits.append(outcome.used)
                remaining = outcome.remaining
                if outcome.won { break }
                continue
            }

            if remaining > 60,
               let setup = preferredSetup(
                remaining: remaining,
                rule: outRule,
                favorites: profile.favoriteDoubles,
                samples: profile.setupVisits
               ) {
                let outcome = ScoringRules.applyVisit(
                    remaining: remaining, opened: true, darts: setup, rule: outRule, doubleIn: false
                )
                visits.append(outcome.used)
                remaining = outcome.remaining
                continue
            }

            let visit = scoringVisit(
                remaining: remaining,
                target: targetVisit,
                samples: profile.scoringVisits,
                rule: outRule,
                rng: &rng
            )
            let outcome = ScoringRules.applyVisit(
                remaining: remaining, opened: true, darts: visit, rule: outRule, doubleIn: false
            )
            visits.append(outcome.used)
            remaining = outcome.remaining
            if outcome.won { break }
        }

        if remaining > 0 {
            visits.append([.miss, .miss, .miss])
        }
        return visits
    }

    private static func preferredCheckout(remaining: Int, rule: OutRule, favorites: [Int]) -> [Dart]? {
        let routes = Checkout.alternatives(for: remaining, rule: rule)
        guard !routes.isEmpty else { return Checkout.route(for: remaining, rule: rule) }
        if let hit = routes.first(where: { route in
            guard let last = route.last, last.multiplier == 2 else { return false }
            let seg = last.segment == 25 ? 25 : last.segment
            return favorites.contains(seg)
        }) {
            return hit
        }
        return routes.first
    }

    private static func preferredSetup(
        remaining: Int,
        rule: OutRule,
        favorites: [Int],
        samples: [[Dart]]
    ) -> [Dart]? {
        if let setup = Checkout.setup(for: remaining, rule: rule, darts: 3) {
            let leave = setup.leaves
            let leaveSeg = leave == 50 ? 25 : leave / 2
            if favorites.contains(leaveSeg) || favorites.contains(where: { $0 * 2 == leave || ($0 == 25 && leave == 50) }) {
                return setup.darts
            }
        }
        if let sample = samples.last(where: { visit in
            let scored = visit.reduce(0) { $0 + $1.score }
            let leave = remaining - scored
            return leave > 1 && leave <= 40 && leave % 2 == 0 && !visit.contains(where: { ScoringRules.isBust(remaining: remaining, dart: $0, rule: rule) })
        }) {
            return sample
        }
        return nil
    }

    private static func scoringVisit(
        remaining: Int,
        target: Double,
        samples: [[Dart]],
        rule: OutRule,
        rng: inout some RandomNumberGenerator
    ) -> [Dart] {
        let usable = samples.filter { visit in
            let scored = visit.reduce(0) { $0 + $1.score }
            return scored > 0
                && scored < remaining
                && !visit.contains(where: { ScoringRules.isBust(remaining: remaining, dart: $0, rule: rule) })
        }
        if let pick = usable.min(by: {
            abs(Double($0.reduce(0) { $0 + $1.score }) - target) < abs(Double($1.reduce(0) { $0 + $1.score }) - target)
        }) {
            return pick
        }
        if remaining > 60 {
            return [Dart(20, 3), Dart(20, 3), Dart(20, 3)].map { dart in
                ScoringRules.isBust(remaining: remaining, dart: dart, rule: rule) ? Dart(20) : dart
            }
        }
        if let route = Checkout.route(for: remaining, rule: rule, darts: 3) { return route }
        let aim = min(20, max(1, remaining / 3))
        return [Dart(aim), Dart(aim), Dart(aim)]
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

/// Jednoduchý deterministický RNG pro syntézu ghosta.
private struct SplitMix64: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed == 0 ? 0xDEAD_BEEF : seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
