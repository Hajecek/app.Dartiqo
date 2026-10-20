import Foundation

/// Otevření hry z obrazovky Trénink. `segment` předvybere cíl (double, triple, číslo série).
struct TrainingLaunch: Hashable, Identifiable {
    var gameID: String
    var segment: Int?
    var id: String { "\(gameID)-\(segment ?? 0)" }
}

/// Doporučený trénink podle statistik hráče.
struct TrainingSuggestion: Identifiable, Equatable {
    var launch: TrainingLaunch
    var title: String
    var reason: String
    var symbol: String
    var id: String { launch.id }
}

enum TrainingSuggestions {
    static let trebleSegments = [20, 19, 18]
    static let minimumTrebleDarts = 9
    static let minimumCheckoutAttempts = 20
    static let minimumScoringDarts = 60

    /// Nejvýš jedno doporučení na typ slabiny, jen pro hry viditelné v tréninku.
    static func make(matches: [Match], sessions: [TrainingSession], profileID: UUID?) -> [TrainingSuggestion] {
        var items: [TrainingSuggestion] = []
        let mine = sessions.filter { $0.status == .completed && (profileID == nil || $0.owner == profileID) }

        let doubles = DoubleTraining.insights(matches: matches, sessions: mine, profileID: profileID)
        if let weak = DoubleTraining.weakest(in: doubles, count: 1).first {
            items.append(TrainingSuggestion(
                launch: TrainingLaunch(gameID: DoubleTraining.definitionID, segment: weak.segment),
                title: "Trénink \(weak.label)",
                reason: "Nejslabší double: \(weak.percentText) z \(weak.attempts) pokusů.",
                symbol: "circle.circle"
            ))
        }

        let x01 = profileID.map { PlayerStats.make(matches: matches, playerID: $0, mode: .x01, range: nil) }
        if let checkout = x01?.checkout, checkout.attempts >= minimumCheckoutAttempts, let rate = checkout.percentage, rate < 25 {
            items.append(TrainingSuggestion(
                launch: TrainingLaunch(gameID: "bobs-27"),
                title: "Bob's 27",
                reason: "Na double zavíráš \(Int(rate.rounded())) %. Bob's 27 projde všechny doubly.",
                symbol: "flag.checkered"
            ))
        }

        if let treble = weakestTreble(in: mine) {
            items.append(TrainingSuggestion(
                launch: TrainingLaunch(gameID: "treble-20", segment: treble.segment),
                title: "Série na T\(treble.segment)",
                reason: "T\(treble.segment) trefuješ na \(treble.percentText) z \(treble.attempts) šipek.",
                symbol: "chart.bar.fill"
            ))
        } else if let stats = x01, stats.darts >= minimumScoringDarts {
            let average = String(format: "%.1f", stats.average).replacingOccurrences(of: ".", with: ",")
            if stats.average < 55 {
                items.append(TrainingSuggestion(
                    launch: TrainingLaunch(gameID: "darts-100-20", segment: 20),
                    title: "Série na 20",
                    reason: "Průměr v X01 je \(average). Stálá dvacítka ho zvedne nejrychleji.",
                    symbol: "chart.bar.fill"
                ))
            } else {
                items.append(TrainingSuggestion(
                    launch: TrainingLaunch(gameID: "treble-20", segment: 20),
                    title: "Série na T20",
                    reason: "Průměr v X01 je \(average). Další posun přinese víc T20.",
                    symbol: "chart.bar.fill"
                ))
            }
        }

        let visible = Set(TrainingCatalog.showcase)
        return items.filter { visible.contains($0.launch.gameID) }
    }

    /// Nejhorší z T20, T19 a T18 v trénincích, pokud je pod 30 %.
    static func weakestTreble(in sessions: [TrainingSession]) -> DoubleInsight? {
        var slots: [Int: DoubleInsight] = [:]
        for session in sessions {
            for tally in session.result?.tallies ?? [] {
                guard tally.key.hasPrefix("T"), let number = Int(tally.key.dropFirst()), trebleSegments.contains(number) else { continue }
                var slot = slots[number] ?? DoubleInsight(segment: number)
                slot.hits += tally.hits
                slot.attempts += tally.attempts
                slots[number] = slot
            }
        }
        return slots.values
            .filter { $0.attempts >= minimumTrebleDarts && $0.rate < 0.3 }
            .min { lhs, rhs in lhs.rate == rhs.rate ? lhs.attempts > rhs.attempts : lhs.rate < rhs.rate }
    }
}
