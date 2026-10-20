import Foundation

/// Úspěšnost na jednom doublu spojená ze zápasů X01 a tréninků (bull = 25).
struct DoubleInsight: Identifiable, Equatable {
    var segment: Int
    var hits = 0
    var attempts = 0

    var id: Int { segment }
    var label: String { segment == 25 ? "Bull" : "D\(segment)" }
    var rate: Double { attempts == 0 ? 0 : Double(hits) / Double(attempts) }
    var percentText: String { "\(Int((rate * 100).rounded())) %" }
}

enum DoubleTraining {
    static let definitionID = "double-focus"
    static let segments = Array(1...20) + [25]
    /// Méně pokusů je náhoda, takový double se do doporučení nedostane.
    static let minimumAttempts = CheckoutStats.comparableAttempts

    /// Pokusy na double ze zápasů (šipky hozené na zavření) a z tréninků (šipky mířené na konkrétní double).
    static func insights(matches: [Match], sessions: [TrainingSession], profileID: UUID?) -> [Int: DoubleInsight] {
        var result: [Int: DoubleInsight] = [:]
        func add(_ segment: Int, hits: Int, attempts: Int) {
            guard attempts > 0, segments.contains(segment) else { return }
            var slot = result[segment] ?? DoubleInsight(segment: segment)
            slot.hits += hits
            slot.attempts += attempts
            result[segment] = slot
        }
        if let profileID {
            for match in matches where match.config.mode == .x01 {
                guard let player = match.players.firstIndex(where: { $0.id == profileID }) else { continue }
                for stat in CheckoutStats.make(from: match, player: player).doubles.values {
                    add(stat.segment, hits: stat.hits, attempts: stat.attempts)
                }
            }
        }
        for session in sessions where session.status == .completed {
            guard profileID == nil || session.owner == profileID else { continue }
            for tally in session.result?.tallies ?? [] {
                guard let segment = segment(fromTally: tally.key) else { continue }
                add(segment, hits: tally.hits, attempts: tally.attempts)
            }
        }
        return result
    }

    /// Nejslabší doubly s dostatkem pokusů, od nejhoršího.
    static func weakest(in insights: [Int: DoubleInsight], count: Int = 3) -> [DoubleInsight] {
        let ranked = insights.values
            .filter { $0.attempts >= minimumAttempts }
            .sorted { lhs, rhs in
                if lhs.rate != rhs.rate { return lhs.rate < rhs.rate }
                if lhs.attempts != rhs.attempts { return lhs.attempts > rhs.attempts }
                return lhs.segment > rhs.segment
            }
        return Array(ranked.prefix(count))
    }

    /// Klíč z `AimTally` („D16“, „BULL“) na číslo doublu.
    static func segment(fromTally key: String) -> Int? {
        if key == "BULL" { return 25 }
        guard key.hasPrefix("D"), let number = Int(key.dropFirst()), (1...20).contains(number) else { return nil }
        return number
    }

    static func config(segment: Int, darts: Int, accuracy: Double) -> TrainingConfig {
        var config = TrainingConfig()
        config.segments = [segment]
        config.dartCount = darts
        config.requiredAccuracy = accuracy
        return config
    }
}
