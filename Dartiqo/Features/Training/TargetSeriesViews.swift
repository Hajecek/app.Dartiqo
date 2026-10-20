import SwiftUI

/// Zápis série na jeden cíl: jen trefa nebo vedle, bez klávesnice.
struct HitMissPad: View {
    var target: String
    var onThrow: (Bool) -> Void

    var body: some View {
        HStack(spacing: 10) {
            button(hit: false)
            button(hit: true)
        }
        .frame(height: 190)
    }

    private func button(hit: Bool) -> some View {
        Button { onThrow(hit) } label: {
            VStack(spacing: 8) {
                Image(systemName: hit ? "checkmark" : "xmark")
                    .font(.system(size: 30, weight: .heavy))
                Text(hit ? "Trefa" : "Vedle")
                    .font(AppFont.title(22, weight: .bold))
                Text(hit ? target : "mimo \(target)")
                    .font(AppFont.caption(13, weight: .bold))
                    .opacity(0.7)
            }
            .foregroundStyle(hit ? ScoringChrome.ink : .white)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(
                hit ? ScoringChrome.green : Color.white.opacity(0.08),
                in: RoundedRectangle(cornerRadius: 22, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(.white.opacity(hit ? 0 : 0.14), lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(hit ? "Trefa \(target)" : "Vedle")
    }
}

/// Úspěšnost rozehrané série po klepnutí na skóre.
struct TargetSeriesStatsSheet: View {
    @Environment(\.dismiss) private var dismiss
    var stats: TargetSeriesStats
    /// Dosavadní výsledky na stejném doublu ze zápasů a starších tréninků.
    var history: DoubleInsight?

    private let background = Color(red: 0.055, green: 0.10, blue: 0.08)

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    hero
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                        chip("\(stats.hits)", "Zásahy")
                        chip("\(stats.thrown - stats.hits)", "Vedle")
                        chip("\(stats.left)", "Zbývá šipek")
                        chip("\(stats.currentStreak)", "V řadě teď")
                        chip("\(stats.bestStreak)", "Nejdelší řada")
                        chip("\(Int((stats.goal * 100).rounded())) %", "Cíl")
                    }
                    if !stats.visits.isEmpty { visitsSection }
                    if let history { historySection(history) }
                }
                .padding(20)
            }
            .scrollIndicators(.hidden)
            .background(background.ignoresSafeArea())
            .navigationTitle("Série \(stats.target.label)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(.white)
                            .frame(width: 30, height: 30)
                            .background(.white.opacity(0.14), in: Circle())
                    }
                    .accessibilityLabel("Zavřít")
                }
            }
            .toolbarBackground(.hidden, for: .navigationBar)
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationBackground(background)
        .presentationCornerRadius(28)
        .preferredColorScheme(.dark)
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(percent(stats.rate))
                    .font(AppFont.display(56, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(stats.goalReached ? ScoringChrome.green : .white)
                Spacer(minLength: 8)
                Text("\(stats.hits) / \(stats.thrown)")
                    .font(AppFont.title(22, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(.white.opacity(0.8))
            }
            Text("úspěšnost na \(stats.target.label)")
                .font(AppFont.caption(13, weight: .semibold))
                .foregroundStyle(.white.opacity(0.55))
            Text(goalLine)
                .font(AppFont.body(15, weight: .semibold))
                .foregroundStyle(stats.goalReached ? ScoringChrome.green : (stats.goalReachable ? .white : ScoringChrome.coral))
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 4)
        }
        .accessibilityElement(children: .combine)
    }

    private var goalLine: String {
        let goal = percent(stats.goal)
        if stats.goalReached { return "Cíl \(goal) je splněný." }
        if stats.goalReachable {
            return "Na cíl \(goal) chybí \(stats.hitsNeeded) \(hitWord(stats.hitsNeeded)) ze \(stats.left) šipek."
        }
        return "Cíl \(goal) už v této sérii nevyjde. Dohraj ji, statistiky se uloží."
    }

    private var visitsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("Po kolech")
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 5), spacing: 8) {
                ForEach(Array(stats.visits.enumerated()), id: \.offset) { index, visit in
                    VStack(spacing: 6) {
                        Text("\(index + 1)")
                            .font(AppFont.caption(10, weight: .bold))
                            .foregroundStyle(.white.opacity(0.45))
                        HStack(spacing: 4) {
                            ForEach(0..<3, id: \.self) { dart in
                                Circle()
                                    .fill(dartColor(visit, dart))
                                    .frame(width: 9, height: 9)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Kolo \(index + 1): \(visit.filter { $0 }.count) z \(visit.count)")
                }
            }
        }
    }

    private func dartColor(_ visit: [Bool], _ index: Int) -> Color {
        guard visit.indices.contains(index) else { return .white.opacity(0.15) }
        return visit[index] ? ScoringChrome.green : ScoringChrome.coral
    }

    private func historySection(_ history: DoubleInsight) -> some View {
        let delta = stats.thrown == 0 ? nil : Int(((stats.rate - history.rate) * 100).rounded())
        return VStack(alignment: .leading, spacing: 10) {
            sectionTitle("Dlouhodobě")
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(history.percentText)
                        .font(AppFont.title(22, weight: .bold))
                        .monospacedDigit()
                    Text("\(history.hits) z \(history.attempts) pokusů ze zápasů a tréninků")
                        .font(AppFont.caption(12, weight: .medium))
                        .foregroundStyle(.white.opacity(0.55))
                }
                Spacer(minLength: 8)
                if let delta {
                    Text(delta >= 0 ? "+\(delta) b." : "\(delta) b.")
                        .font(AppFont.caption(13, weight: .bold))
                        .monospacedDigit()
                        .foregroundStyle(delta >= 0 ? ScoringChrome.green : ScoringChrome.coral)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(.white.opacity(0.08), in: Capsule())
                        .accessibilityLabel(delta >= 0 ? "O \(delta) procentních bodů lépe" : "O \(-delta) procentních bodů hůř")
                }
            }
            .padding(14)
            .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
    }

    private func chip(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(AppFont.title(20, weight: .bold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label)
                .font(AppFont.caption(11, weight: .semibold))
                .foregroundStyle(.white.opacity(0.55))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title.uppercased())
            .font(AppFont.caption(11, weight: .heavy))
            .tracking(1.1)
            .foregroundStyle(.white.opacity(0.45))
    }

    private func percent(_ value: Double) -> String { "\(Int((value * 100).rounded())) %" }

    private func hitWord(_ count: Int) -> String {
        switch count {
        case 1: return "zásah"
        case 2, 3, 4: return "zásahy"
        default: return "zásahů"
        }
    }
}
