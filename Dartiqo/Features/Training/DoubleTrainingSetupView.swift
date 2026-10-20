import SwiftUI

/// Nastavení tréninku doublů: výběr jednoho doublu, délka série a cíl úspěšnosti.
struct DoubleTrainingSetupView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var segment: Int
    @State private var darts = 30
    @State private var accuracy = 0.25
    @State private var insights: [Int: DoubleInsight] = [:]
    @State private var loaded = false
    @State private var playing = false
    @State private var showInfo = false

    init(segment: Int? = nil) {
        let preset = segment.flatMap { DoubleTraining.segments.contains($0) ? $0 : nil }
        _segment = State(initialValue: preset ?? 16)
    }

    private var definition: TrainingDefinition? { TrainingCatalog.find(DoubleTraining.definitionID) }
    private var motion: Animation? { reduceMotion ? nil : .smooth(duration: 0.3) }
    private var label: String { DoubleInsight(segment: segment).label }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                hero
                TrainingSettingCard(title: "Vyber double") {
                    RuleTiles(
                        options: DoubleTraining.segments.map { value in
                            (id: value, title: DoubleInsight(segment: value).label, detail: insights[value]?.percentText ?? "—")
                        },
                        selection: segment,
                        columns: 4
                    ) { value in
                        withAnimation(motion) { segment = value }
                    }
                    Text("Pod doublem je tvoje úspěšnost ze zápasů X01 a tréninků.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                TrainingSettingCard(title: "Počet šipek") {
                    RuleTiles(
                        options: [30, 45, 60, 90].map { (id: $0, title: "\($0)", detail: "\($0 / 3) kol") },
                        selection: darts,
                        columns: 4
                    ) { darts = $0 }
                }
                TrainingSettingCard(title: "Cíl úspěšnosti") {
                    RuleTiles(
                        options: [0.15, 0.25, 0.35, 0.5].map { (id: $0, title: "\(Int(($0 * 100).rounded())) %", detail: nil) },
                        selection: accuracy,
                        columns: 4
                    ) { accuracy = $0 }
                }
            }
            .padding(20)
            .frame(maxWidth: 760)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            TrainingStartBar(title: "Hrát \(label)") { playing = true }
                .disabled(definition == nil)
        }
        .toolbar(.hidden, for: .tabBar)
        .screen()
        .navigationTitle("Trénink doublů")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showInfo = true } label: { Image(systemName: "info.circle") }
                    .accessibilityLabel("Pravidla")
            }
        }
        .onAppear(perform: load)
        .sheet(isPresented: $showInfo) {
            if let definition {
                TrainingInfoSheet(definition: definition) { showInfo = false }
            }
        }
        .fullScreenCover(isPresented: $playing) {
            if let definition {
                NavigationStack {
                    TrainingPlayView(definition: definition, config: DoubleTraining.config(segment: segment, darts: darts, accuracy: accuracy))
                }
                .environmentObject(store)
            }
        }
    }

    private func load() {
        guard !loaded else { return }
        loaded = true
        insights = DoubleTraining.insights(matches: store.matches, sessions: store.trainingHistory, profileID: store.profile?.id)
    }

    private var hero: some View {
        let stat = insights[segment]
        return HStack(spacing: 16) {
            Text(label)
                .font(.system(size: segment == 25 ? 22 : 28, weight: .heavy, design: .rounded))
                .foregroundStyle(.black)
                .minimumScaleFactor(0.6)
                .frame(width: 76, height: 76)
                .background(Theme.brand, in: Circle())
                .contentTransition(.numericText())
            VStack(alignment: .leading, spacing: 4) {
                Text("Cíl tréninku")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.6))
                Text(segment == 25 ? "Bull 50" : "Double \(segment)")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(.white)
                Text(stat.map { "\($0.percentText) · \($0.hits) z \($0.attempts) pokusů" } ?? "Zatím bez pokusů")
                    .font(.subheadline)
                    .monospacedDigit()
                    .foregroundStyle(.white.opacity(0.75))
            }
            Spacer(minLength: 0)
        }
        .padding(18)
        .background(Theme.heroWash, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(.white.opacity(0.08), lineWidth: 1))
        .animation(motion, value: segment)
        .accessibilityElement(children: .combine)
    }
}

#if DEBUG
#Preview {
    NavigationStack { DoubleTrainingSetupView(segment: 7) }.dartiqoPreview(PreviewSupport.store(activeMatch: false))
}
#endif
