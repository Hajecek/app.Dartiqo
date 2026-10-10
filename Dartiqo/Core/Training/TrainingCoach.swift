import Foundation

enum TrainingCoach {
    static func recommend(matches: [Match], sessions: [TrainingSession], profileID: UUID?) -> TrainingRecommendation {
        let done = sessions.filter { $0.status == .completed && $0.result != nil }
        let darts = done.reduce(0) { $0 + ($1.result?.darts ?? 0) }
        let matchDarts = matches.reduce(0) { sum, match in
            sum + match.visits.filter { visit in
                visit.enteredAsTotal != true && (profileID == nil || match.players[visit.player].id == profileID)
            }.reduce(0) { $0 + $1.darts.count }
        }
        if darts + matchDarts < 30 {
            var config = TrainingConfig(level: .beginner)
            config.segments = nil
            return TrainingRecommendation(
                definitionID: "weak-spot",
                reason: "Zatím je jen \(darts + matchDarts) šipek. Diagnostika projde T20, D16, 20 a bull.",
                config: config
            )
        }
        let tallies = Dictionary(grouping: done.flatMap { $0.result?.tallies ?? [] }, by: \.key).mapValues { rows in
            (hits: rows.reduce(0) { $0 + $1.hits }, attempts: rows.reduce(0) { $0 + $1.attempts })
        }
        if let weak = tallies.filter({ $0.key.hasPrefix("D") && $0.value.attempts >= 6 && Double($0.value.hits) / Double($0.value.attempts) < 0.3 }).min(by: { lhs, rhs in
            Double(lhs.value.hits) / Double(lhs.value.attempts) < Double(rhs.value.hits) / Double(rhs.value.attempts)
        }) {
            let segment = Int(weak.key.dropFirst()) ?? 16
            var config = TrainingConfig(level: .advanced, segments: [segment])
            let rate = Int((Double(weak.value.hits) / Double(weak.value.attempts) * 100).rounded())
            return TrainingRecommendation(definitionID: "double-hunter", reason: "\(weak.key) vychází jen na \(rate) % z \(weak.value.attempts) pokusů.", config: config)
        }
        let averages = done.compactMap { $0.result?.average }
        if let average = averages.last, average < 45 {
            return TrainingRecommendation(definitionID: "darts-100-20", reason: "Poslední scoringový průměr je \(Int(average.rounded())). Sto šipek na 20 ho zvedne rychleji než další leg.", config: TrainingConfig())
        }
        let leaves = done.flatMap { $0.result?.checkoutLeaves ?? [] }
        let made = done.flatMap { $0.result?.checkoutMade ?? [] }
        let bandAttempts = leaves.filter { (61...100).contains($0) }.count
        let bandHits = made.filter { (61...100).contains($0) }.count
        if bandAttempts >= 4, Double(bandHits) / Double(bandAttempts) < 0.3 {
            let rate = Int((Double(bandHits) / Double(bandAttempts) * 100).rounded())
            return TrainingRecommendation(definitionID: "checkout-61-100", reason: "Checkouty 61–100 vycházejí na \(rate) % z \(bandAttempts) pokusů.", config: TrainingConfig())
        }
        if averages.count >= 3 {
            let spread = (averages.max() ?? 0) - (averages.min() ?? 0)
            if spread > 25 {
                return TrainingRecommendation(definitionID: "consistency", reason: "Průměr se mezi tréninky hýbe o \(Int(spread.rounded())) bodů. Konzistence to srovná.", config: TrainingConfig())
            }
        }
        if let treble = tallies["T20"], treble.attempts >= 8, Double(treble.hits) / Double(treble.attempts) < 0.15 {
            let rate = Int((Double(treble.hits) / Double(treble.attempts) * 100).rounded())
            return TrainingRecommendation(definitionID: "treble-20", reason: "T20 vychází na \(rate) % z \(treble.attempts) šipek.", config: TrainingConfig())
        }
        return TrainingRecommendation(definitionID: "around-clock", reason: "Základ drží. Around the Clock prověří, jestli ti neujíždí kraj terče.", config: TrainingConfig())
    }

    static func daily(on date: Date = Date(), profile: UUID, calendar: Calendar = .current) -> (definitionID: String, seed: UInt64) {
        let start = calendar.startOfDay(for: date)
        let day = UInt64(start.timeIntervalSince1970 / 86_400)
        let profileBits = UInt64(bitPattern: Int64(profile.hashValue))
        var rng = TrainingRNG(seed: day ^ profileBits)
        let pool = ["daily-9", "around-clock", "shanghai-20", "checkout-40", "treble-20", "high-score", "bobs-27", "bull-challenge"]
        return (rng.pick(pool), day == 0 ? 1 : day)
    }

    static func weekly(on date: Date = Date(), profile: UUID, calendar: Calendar = .current) -> (definitionID: String, seed: UInt64) {
        let week = calendar.component(.weekOfYear, from: date)
        let year = calendar.component(.yearForWeekOfYear, from: date)
        let seed = UInt64(year * 100 + week)
        let profileBits = UInt64(bitPattern: Int64(profile.hashValue))
        var rng = TrainingRNG(seed: seed ^ profileBits)
        let pool = ["checkout-ladder", "consistency", "practice-501", "cricket-practice", "world-tour", "double-hunter"]
        return (rng.pick(pool), seed == 0 ? 1 : seed)
    }

    static func context(matches: [Match], sessions: [TrainingSession], profileID: UUID?) -> TrainingContext {
        var counts: [Int: Int] = [:]
        var tallies: [String: (hits: Int, attempts: Int)] = [:]
        for session in sessions where session.status == .completed {
            for tally in session.result?.tallies ?? [] {
                var slot = tallies[tally.key] ?? (0, 0)
                slot.hits += tally.hits
                slot.attempts += tally.attempts
                tallies[tally.key] = slot
            }
            for action in session.actions {
                if case .dart(let dart) = action, (1...20).contains(dart.segment) {
                    counts[dart.segment, default: 0] += 1
                }
            }
        }
        for match in matches {
            for visit in match.visits where visit.enteredAsTotal != true {
                guard profileID == nil || match.players[visit.player].id == profileID else { continue }
                for dart in visit.darts where (1...20).contains(dart.segment) {
                    counts[dart.segment, default: 0] += 1
                }
            }
        }
        let rare = (1...20).sorted { counts[$0, default: 0] < counts[$1, default: 0] }.prefix(6)
        let weak = tallies.filter { $0.value.attempts >= 4 }.sorted {
            Double($0.value.hits) / Double($0.value.attempts) < Double($1.value.hits) / Double($1.value.attempts)
        }.prefix(4).compactMap { key, _ in aim(from: key) }
        let averages = sessions.compactMap { $0.result?.average }
        let accuracy = sessions.compactMap(\.result).filter { $0.darts > 0 }.map(\.accuracy)
        return TrainingContext(
            weakAims: Array(weak),
            rareSegments: Array(rare),
            recentAccuracy: accuracy.isEmpty ? nil : accuracy.suffix(5).reduce(0, +) / Double(min(5, accuracy.count)),
            recentAverage: averages.isEmpty ? nil : averages.suffix(5).reduce(0, +) / Double(min(5, averages.count))
        )
    }

    private static func aim(from key: String) -> Aim? {
        if key == "Bull" || key == "BULL" { return .bull }
        if key == "25" { return .outerBull }
        guard let prefix = key.first, let number = Int(key.dropFirst()), (1...20).contains(number) else { return nil }
        switch prefix {
        case "T": return .segment(number, 3)
        case "D": return .segment(number, 2)
        case "S": return .segment(number, 1)
        default: return nil
        }
    }
}

enum TrainingPlans {
    static func make(goal: TrainingGoal, span: Int, daysPerWeek: Int, minutes: Int, level: TrainingLevel, owner: UUID, now: Date = Date()) -> TrainingPlan {
        let filtered = ids(for: goal).filter { definition in
            guard let item = TrainingCatalog.find(definition) else { return false }
            return item.minutes <= max(minutes, 5) || minutes >= 20
        }
        let source = filtered.isEmpty ? ids(for: goal) : filtered
        let weeks = max(1, span / 7)
        let perWeek = min(7, max(1, daysPerWeek))
        var items: [TrainingPlanItem] = []
        var cursor = 0
        for week in 0..<weeks {
            for day in 0..<perWeek {
                let id = source[cursor % source.count]
                items.append(TrainingPlanItem(day: week * 7 + day, definitionID: id))
                cursor += 1
            }
        }
        if span > weeks * 7 {
            let id = source[cursor % source.count]
            items.append(TrainingPlanItem(day: span - 1, definitionID: id))
        }
        return TrainingPlan(owner: owner, goal: goal, span: span, daysPerWeek: perWeek, minutes: minutes, level: level, createdAt: now, items: items)
    }

    static func ids(for goal: TrainingGoal) -> [String] {
        switch goal {
        case .scoring: return ["darts-100-20", "treble-20", "ton", "high-score", "average-builder", "practice-501"]
        case .doubles: return ["doubles-practice", "bobs-27", "around-clock-doubles", "double-hunter", "double-trouble"]
        case .checkouts: return ["checkout-40", "checkout-32", "checkout-61-100", "checkout-121", "pressure", "escape"]
        case .average: return ["average-builder", "practice-501", "consistency", "ton", "adaptive-501"]
        case .tournament: return ["practice-501", "checkout-101-170", "challenge-30", "pressure", "comeback"]
        case .consistency: return ["consistency", "singles-accuracy", "around-clock", "shanghai-20", "streak"]
        case .complete: return ["weak-spot", "around-clock", "bobs-27", "checkout-random", "practice-501", "marathon"]
        }
    }

    /// Příští položku posune na těžší nebo lehčí hru stejného cíle podle posledních výsledků.
    static func react(_ plan: inout TrainingPlan, sessions: [TrainingSession]) {
        let recent = sessions.filter { $0.status == .completed }.suffix(3).compactMap { $0.result?.success }
        guard recent.count >= 2, let index = plan.items.firstIndex(where: { $0.sessionID == nil }) else { return }
        let pool = ids(for: plan.goal)
        guard let current = pool.firstIndex(of: plan.items[index].definitionID) else { return }
        if recent.allSatisfy({ $0 }) {
            plan.items[index].definitionID = pool[min(pool.count - 1, current + 1)]
        } else if recent.allSatisfy({ !$0 }) {
            plan.items[index].definitionID = pool[max(0, current - 1)]
        }
    }
}
