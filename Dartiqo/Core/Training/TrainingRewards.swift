import Foundation

enum TrainingRewards {
    /// XP za dokončenou hru. Restart ani prázdný záznam nic nedají. Čtvrté a další dokončení stejné hry v jednom dni nechá jen 10 % základu.
    static func award(definition: TrainingDefinition, config: TrainingConfig, result: TrainingResult, completionsToday: Int, isRecord: Bool, isDaily: Bool, isWeekly: Bool) -> Int {
        guard result.darts > 0 else { return 0 }
        let level = config.level == .adaptive ? .advanced : config.level
        let base: Int
        switch level {
        case .beginner: base = 20
        case .pro: base = 70
        case .advanced, .adaptive: base = 40
        }
        if completionsToday >= 3 { return max(1, base / 10) }
        var amount = base
        if result.success { amount += 30 }
        amount += Int((min(1, max(0, result.accuracy)) * 20).rounded())
        if isRecord { amount += 40 }
        if result.accuracy >= 0.5 || result.bestStreak >= 3 { amount += 15 }
        if isDaily { amount += 50 }
        if isWeekly { amount += 40 }
        return amount
    }
}

enum TrainingAchievements {
    static let keys = [
        "first-training", "doubles-100", "checkouts-50", "first-180",
        "streak-7", "trainings-30", "tower", "bosses"
    ]

    static func title(_ key: String) -> String {
        switch key {
        case "first-training": return "První trénink"
        case "doubles-100": return "100 doublů"
        case "checkouts-50": return "50 checkoutů"
        case "first-180": return "První 180"
        case "streak-7": return "Sedm dní v řadě"
        case "trainings-30": return "30 tréninků"
        case "tower": return "Celá věž"
        case "bosses": return "Všichni bossové"
        default: return key
        }
    }

    static func symbol(_ key: String) -> String {
        switch key {
        case "first-training": return "figure.walk"
        case "doubles-100": return "circle.circle"
        case "checkouts-50": return "flag.checkered"
        case "first-180": return "flame.fill"
        case "streak-7": return "calendar"
        case "trainings-30": return "medal.fill"
        case "tower": return "building.2.fill"
        case "bosses": return "crown.fill"
        default: return "star.fill"
        }
    }

    static func earned(sessions: [TrainingSession], matchOneEighties: Int, streak: Int) -> Set<String> {
        let done = sessions.filter { $0.status == .completed }
        var keys = Set<String>()
        if !done.isEmpty { keys.insert("first-training") }
        let doubles = done.flatMap { $0.result?.tallies ?? [] }.filter { $0.key.hasPrefix("D") || $0.key == "Libovolný double" }.reduce(0) { $0 + $1.hits }
        if doubles >= 100 { keys.insert("doubles-100") }
        let checkouts = done.reduce(0) { $0 + ($1.result?.checkoutHits ?? 0) }
        if checkouts >= 50 { keys.insert("checkouts-50") }
        let trained180 = done.reduce(0) { $0 + ($1.result?.oneEighties ?? 0) }
        if matchOneEighties + trained180 > 0 { keys.insert("first-180") }
        if streak >= 7 { keys.insert("streak-7") }
        if done.count >= 30 { keys.insert("trainings-30") }
        if done.contains(where: { $0.definitionID == "tower" && $0.result?.success == true }) { keys.insert("tower") }
        if done.contains(where: { $0.definitionID == "boss" && $0.result?.success == true }) { keys.insert("bosses") }
        return keys
    }
}

enum TrainingStreaks {
    static func daily(sessions: [TrainingSession], now: Date = Date(), calendar: Calendar = .current) -> Int {
        let days = Set(sessions.compactMap { session -> Date? in
            guard session.status == .completed, let date = session.finishedAt else { return nil }
            return calendar.startOfDay(for: date)
        })
        guard !days.isEmpty else { return 0 }
        var cursor = calendar.startOfDay(for: now)
        if !days.contains(cursor) {
            guard let yesterday = calendar.date(byAdding: .day, value: -1, to: cursor), days.contains(yesterday) else { return 0 }
            cursor = yesterday
        }
        var count = 0
        while days.contains(cursor) {
            count += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = previous
        }
        return count
    }

    static func weekly(sessions: [TrainingSession], now: Date = Date(), calendar: Calendar = .current) -> Int {
        let weeks = Set(sessions.compactMap { session -> DateComponents? in
            guard session.status == .completed, let date = session.finishedAt else { return nil }
            return calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
        })
        var cursor = now
        var count = 0
        while true {
            let key = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: cursor)
            guard weeks.contains(key) else { break }
            count += 1
            guard let previous = calendar.date(byAdding: .weekOfYear, value: -1, to: cursor) else { break }
            cursor = previous
        }
        return count
    }
}
