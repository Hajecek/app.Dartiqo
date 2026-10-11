import SwiftUI

func trainingDayCount(_ count: Int) -> String {
    switch count {
    case 1: return "1 den"
    case 2, 3, 4: return "\(count) dny"
    default: return "\(count) dní"
    }
}

/// Krátké centrum nahoře, pod ním hledání a všechny hry po kategoriích.
struct TrainingCenterView: View {
    @EnvironmentObject private var store: AppStore
    @State private var query = ""
    @State private var setupID: String?
    @State private var infoGame: TrainingDefinition?

    private var groups: [TrainingGameGroup] {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return TrainingCategory.allCases.compactMap { category in
            let games = TrainingCatalog.showcaseGames.filter { game in
                game.category == category && (text.isEmpty || game.title.localizedStandardContains(text) || game.summary.localizedStandardContains(text))
            }
            guard !games.isEmpty else { return nil }
            return TrainingGameGroup(category: category, games: games)
        }
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 8, pinnedViews: [.sectionHeaders]) {
                Section {
                    metrics
                    xpGuide
                    searchField
                        .padding(.top, 2)
                }
                if groups.isEmpty {
                    ContentUnavailableView.search(text: query)
                } else {
                    ForEach(groups) { group in
                        Section {
                            ForEach(group.games) { game in
                                ChoiceCard(
                                    title: game.title,
                                    detail: game.summary,
                                    symbol: game.category.symbol,
                                    selected: false,
                                    action: { setupID = game.id },
                                    info: { infoGame = game }
                                )
                            }
                        } header: {
                            categoryHeader(group)
                        }
                    }
                }
            }
            .padding(16)
        }
        .screen()
        .navigationTitle("Trénink")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: $setupID) { id in
            TrainingHomeView(gameIDs: [id])
        }
        .sheet(item: $infoGame) { game in
            TrainingInfoSheet(definition: game) {
                infoGame = nil
                setupID = game.id
            }
        }
        .scrollDismissesKeyboard(.immediately)
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.body.weight(.semibold))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            TextField("Najít hru", text: $query)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Smazat hledání")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func categoryHeader(_ group: TrainingGameGroup) -> some View {
        HStack(spacing: 8) {
            Image(systemName: group.category.symbol)
                .font(.caption.weight(.bold))
                .foregroundStyle(.black)
                .frame(width: 22, height: 22)
                .background(Theme.brand, in: Circle())
                .accessibilityHidden(true)
            Text(group.category.title)
                .font(.subheadline.weight(.bold))
            Spacer(minLength: 8)
            Text("\(group.games.count)")
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.background)
    }

    private var metrics: some View {
        let accuracy = store.trainingAccuracy.map { "\(Int(($0 * 100).rounded())) %" } ?? "—"
        let tasks = TrainingDaily.tasks(in: store.trainingHistory)
        let done = tasks.filter(\.done).count
        let next = tasks.first { !$0.done }
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Label {
                    Text(trainingDayCount(store.trainingStreak))
                        .font(.system(.title2, design: .rounded).weight(.bold))
                        .monospacedDigit()
                } icon: {
                    Image(systemName: "flame.fill")
                        .font(.title3.weight(.bold))
                }
                .labelStyle(.titleAndIcon)
                .foregroundStyle(.black)
                Spacer(minLength: 8)
                Text("Level \(store.level)")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.black.opacity(0.7))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(.black.opacity(0.08), in: Capsule())
            }
            HStack(spacing: 0) {
                compactStat(accuracy, "přesnost")
                compactStat(PlayTime.format(store.trainingPlayed), "u terče")
                compactStat("\(store.trainingWeekXP)", "XP / týden")
            }
            Group {
                if let next, done < tasks.count {
                    Button { setupID = next.gameID } label: {
                        dailyLine(done: done, total: tasks.count, doneAll: false)
                    }
                    .buttonStyle(.plain)
                } else {
                    dailyLine(done: done, total: tasks.count, doneAll: true)
                }
            }
        }
        .padding(14)
        .background(Theme.brand, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func dailyLine(done: Int, total: Int, doneAll: Bool) -> some View {
        HStack(spacing: 8) {
            Image(systemName: doneAll ? "checkmark.seal.fill" : "flag.fill")
                .font(.caption.weight(.bold))
                .accessibilityHidden(true)
            Text(doneAll ? "Denní výzva splněná" : "Denní výzva \(done)/\(total)")
                .font(.caption.weight(.semibold))
            Spacer(minLength: 0)
            if !doneAll {
                Text("+50 XP")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.black.opacity(0.55))
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.black.opacity(0.4))
                    .accessibilityHidden(true)
            }
        }
        .foregroundStyle(.black.opacity(0.72))
    }

    private func compactStat(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value)
                .font(.system(.title3, design: .rounded).weight(.bold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(label)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.black.opacity(0.55))
        }
        .foregroundStyle(.black)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var xpGuide: some View {
        NavigationLink {
            XPInfoView()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "bolt.fill")
                    .font(.body.weight(.bold))
                    .foregroundStyle(Theme.brand)
                    .frame(width: 36, height: 36)
                    .background(Theme.brand.opacity(0.14), in: Circle())
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Za co dostávám XP")
                        .font(.subheadline.weight(.bold))
                    Text("Základ, splnění, rekord a denní výzva")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
            .padding(12)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
    }

}

private struct TrainingGameGroup: Identifiable {
    var category: TrainingCategory
    var games: [TrainingDefinition]
    var id: String { category.id }
}

struct TrainingDailyTask: Identifiable {
    var title: String
    var gameID: String
    var done: Bool
    var id: String { gameID }
}

enum TrainingDaily {
    static func tasks(in sessions: [TrainingSession], now: Date = Date()) -> [TrainingDailyTask] {
        let start = Calendar.current.startOfDay(for: now)
        let today = sessions.filter { $0.status == .completed && ($0.finishedAt ?? $0.startedAt) >= start }
        let trebles = today.reduce(0) { sum, session in
            sum + (session.result?.tallies.first { $0.key == "T20" }?.hits ?? 0)
        }
        let closed40 = today.contains { $0.definitionID == "checkout-40" && $0.result?.success == true }
        let bull = today.contains { session in
            session.actions.contains { action in
                if case .dart(let dart) = action { return dart.segment == 25 }
                return false
            }
        }
        return [
            TrainingDailyTask(title: "5× T20", gameID: "treble-20", done: trebles >= 5),
            TrainingDailyTask(title: "zavři 40", gameID: "checkout-40", done: closed40),
            TrainingDailyTask(title: "tref bull", gameID: "bull-challenge", done: bull)
        ]
    }
}
