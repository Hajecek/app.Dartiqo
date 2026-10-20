import SwiftUI

func trainingDayCount(_ count: Int) -> String {
    switch count {
    case 1: return "1 den"
    case 2, 3, 4: return "\(count) dny"
    default: return "\(count) dní"
    }
}

/// Nahoře přehled progresu, pod ním samostatné hry jako dlaždice. Hry se přidávají do `TrainingCatalog.showcase`.
struct TrainingCenterView: View {
    @EnvironmentObject private var store: AppStore
    @State private var setupID: String?
    @State private var infoGame: TrainingDefinition?

    private let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]
    private var games: [TrainingDefinition] { TrainingCatalog.showcaseGames }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                progressCard
                gamesSection
            }
            .padding(16)
        }
        .screen()
        .navigationTitle("Trénink")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink { XPInfoView() } label: {
                    Image(systemName: "bolt.fill")
                }
                .accessibilityLabel("Za co dostávám XP")
            }
        }
        .navigationDestination(item: $setupID) { id in
            TrainingHomeView(gameIDs: [id])
        }
        .sheet(item: $infoGame) { game in
            TrainingInfoSheet(definition: game) {
                infoGame = nil
                setupID = game.id
            }
        }
    }

    // MARK: Progres

    private var progressCard: some View {
        let accuracy = store.trainingAccuracy.map { "\(Int(($0 * 100).rounded())) %" } ?? "—"
        return VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: "flame.fill")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(.black)
                    .frame(width: 48, height: 48)
                    .background(Theme.brand, in: Circle())
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(trainingDayCount(store.trainingStreak))
                        .font(.system(.title2, design: .rounded).weight(.bold))
                        .monospacedDigit()
                        .foregroundStyle(.white)
                    Text(store.trainingStreak > 0 ? "tréninku v řadě" : "Začni sérii prvním tréninkem")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.6))
                }
                Spacer(minLength: 8)
                Text("Level \(store.level)")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.black)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Theme.brand, in: Capsule())
            }
            HStack(spacing: 0) {
                stat(accuracy, "přesnost")
                divider
                VStack(alignment: .leading, spacing: 2) {
                    PlayTimeLabel(seconds: store.trainingPlayed, layout: .inline)
                        .foregroundStyle(.white)
                    Text("u terče")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.55))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 12)
                divider
                stat("\(store.trainingWeekXP)", "XP / týden")
                    .padding(.leading, 12)
            }
        }
        .padding(18)
        .background(Theme.heroWash, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(.white.opacity(0.08), lineWidth: 1))
    }

    private var divider: some View {
        Rectangle()
            .fill(.white.opacity(0.12))
            .frame(width: 1, height: 30)
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.system(.title3, design: .rounded).weight(.bold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .foregroundStyle(.white)
            Text(label)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.white.opacity(0.55))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Hry

    private var gamesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("Hry")
                    .font(.title3.weight(.bold))
                Spacer(minLength: 8)
                if !games.isEmpty {
                    Text("\(games.count)")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.secondary)
                }
            }
            if games.isEmpty {
                emptyGames
            } else {
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(games) { game in
                        Button { setupID = game.id } label: {
                            TrainingGameTile(game: game)
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button("Pravidla", systemImage: "info.circle") { infoGame = game }
                        }
                    }
                }
            }
        }
    }

    private var emptyGames: some View {
        VStack(spacing: 12) {
            Image(systemName: "scope")
                .font(.system(size: 34, weight: .semibold))
                .foregroundStyle(.black)
                .frame(width: 72, height: 72)
                .background(Theme.brand, in: Circle())
                .accessibilityHidden(true)
            Text("Hry se připravují")
                .font(.headline)
            Text("Tréninkové hry přidáváme postupně, jednu po druhé. Brzy tu najdeš první.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 36)
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(Theme.stroke, style: StrokeStyle(lineWidth: 1, dash: [6, 5]))
        )
        .accessibilityElement(children: .combine)
    }
}

/// Dlaždice jedné tréninkové hry. Barva a ikona vychází z kategorie.
private struct TrainingGameTile: View {
    var game: TrainingDefinition

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 20, style: .continuous)
        let colors = game.category.tileColors
        VStack(alignment: .leading, spacing: 4) {
            Image(systemName: game.category.symbol)
                .font(.headline.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: 38, height: 38)
                .background(.white.opacity(0.18), in: Circle())
                .accessibilityHidden(true)
            Spacer(minLength: 14)
            Text(game.title)
                .font(.headline)
                .foregroundStyle(.white)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
            Text(game.summary)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.85))
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            Label("\(game.minutes) min", systemImage: "clock")
                .font(.caption2.weight(.bold))
                .foregroundStyle(.white.opacity(0.75))
                .padding(.top, 4)
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 170, alignment: .topLeading)
        .background {
            ZStack(alignment: .bottomTrailing) {
                LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
                Image(systemName: game.category.symbol)
                    .font(.system(size: 90, weight: .bold))
                    .foregroundStyle(.white.opacity(0.12))
                    .rotationEffect(.degrees(-12))
                    .offset(x: 26, y: 26)
                    .accessibilityHidden(true)
            }
        }
        .clipShape(shape)
        .overlay(shape.stroke(.white.opacity(0.12), lineWidth: 1))
        .contentShape(shape)
        .accessibilityElement(children: .combine)
    }
}

private extension TrainingCategory {
    var tileColors: [Color] {
        switch self {
        case .accuracy: return [Color(red: 1.0, green: 0.72, blue: 0.20), Color(red: 0.95, green: 0.48, blue: 0.08)]
        case .doubles: return [Color(red: 1.0, green: 0.42, blue: 0.29), Color(red: 0.86, green: 0.20, blue: 0.20)]
        case .checkout: return [Color(red: 0.18, green: 0.78, blue: 0.48), Color(red: 0.05, green: 0.50, blue: 0.32)]
        case .scoring: return [Color(red: 0.18, green: 0.48, blue: 0.98), Color(red: 0.08, green: 0.22, blue: 0.72)]
        case .endurance: return [Color(red: 0.20, green: 0.74, blue: 0.86), Color(red: 0.06, green: 0.42, blue: 0.62)]
        case .original: return [Color(red: 0.58, green: 0.28, blue: 0.96), Color(red: 0.34, green: 0.12, blue: 0.70)]
        case .adaptive: return [Color(red: 0.96, green: 0.36, blue: 0.62), Color(red: 0.70, green: 0.14, blue: 0.42)]
        case .daily: return [Color(red: 0.36, green: 0.36, blue: 0.40), Color(red: 0.14, green: 0.14, blue: 0.16)]
        }
    }
}

struct TrainingDailyTask: Identifiable {
    var title: String
    var detail: String
    var symbol: String
    var gameID: String
    var done: Bool
    var id: String { gameID }
}

enum TrainingDaily {
    /// Trojice her podle dne a profilu. Stejný den drží stejné úkoly, zítra přijde nová sada.
    static func tasks(
        in sessions: [TrainingSession],
        profile: UUID? = nil,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> [TrainingDailyTask] {
        let start = calendar.startOfDay(for: now)
        let today = sessions.filter { $0.status == .completed && ($0.finishedAt ?? $0.startedAt) >= start }
        return TrainingCoach.dailyGameIDs(on: now, profile: profile, calendar: calendar).compactMap { gameID in
            guard let game = TrainingCatalog.find(gameID) else { return nil }
            let done = today.contains { $0.definitionID == gameID && $0.result?.success == true }
            return TrainingDailyTask(
                title: game.title,
                detail: game.summary,
                symbol: game.category.symbol,
                gameID: gameID,
                done: done
            )
        }
    }
}

#if DEBUG
#Preview {
    NavigationStack { TrainingCenterView() }.dartiqoPreview(PreviewSupport.store(activeMatch: false))
}
#endif
