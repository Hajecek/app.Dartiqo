import SwiftUI

/// Co jde u klasické hry nastavit. Jen volby, které `TrainingKind.tuned` u dané hry opravdu použije.
struct ClassicTrainingSpec {
    enum Setting: Hashable {
        case target, darts, rounds, accuracy, level, checkoutHint, descent
    }

    var settings: [Setting] = []
    var targets: [Int] = []
    var targetMultiplier: Int?
    var darts: [Int] = []
    var rounds: [Int] = []
    var accuracies: [Double] = []
    var defaults = TrainingConfig()

    static func spec(for id: String) -> ClassicTrainingSpec {
        switch id {
        case "darts-100-20":
            return ClassicTrainingSpec(
                settings: [.target, .darts, .accuracy],
                targets: [20, 19, 18, 25], darts: [30, 60, 100], accuracies: [0.25, 0.4, 0.55],
                defaults: config(segment: 20, darts: 100, accuracy: 0.4)
            )
        case "treble-20":
            return ClassicTrainingSpec(
                settings: [.target, .darts, .accuracy],
                targets: [20, 19, 18], targetMultiplier: 3, darts: [30, 45, 60, 90], accuracies: [0.15, 0.25, 0.35, 0.5],
                defaults: config(segment: 20, darts: 30, accuracy: 0.25)
            )
        case "high-score":
            return ClassicTrainingSpec(settings: [.rounds], rounds: [5, 8, 10, 15], defaults: config(rounds: 8))
        case "ton":
            return ClassicTrainingSpec(settings: [.rounds, .level], rounds: [10, 15, 20], defaults: config(rounds: 10))
        case "practice-501", "double-trouble":
            return ClassicTrainingSpec(settings: id == "double-trouble" ? [.level, .checkoutHint] : [.checkoutHint])
        case "around-clock-doubles":
            return ClassicTrainingSpec(settings: [.darts], darts: [60, 90, 120, 150], defaults: config(darts: 120))
        case "checkout-descent":
            var defaults = config(darts: 9, rounds: 50)
            defaults.targetScore = 141
            defaults.floorScore = 100
            return ClassicTrainingSpec(settings: [.descent, .darts, .rounds, .checkoutHint], darts: [3, 6, 9, 12, 15], rounds: [20, 50, 100, 0], defaults: defaults)
        default:
            return ClassicTrainingSpec()
        }
    }

    private static func config(segment: Int? = nil, darts: Int? = nil, rounds: Int? = nil, accuracy: Double? = nil) -> TrainingConfig {
        var value = TrainingConfig()
        value.segments = segment.map { [$0] }
        value.dartCount = darts
        value.rounds = rounds
        value.requiredAccuracy = accuracy
        return value
    }

    func targetLabel(_ segment: Int) -> String {
        if segment == 25 { return "Bull" }
        if targetMultiplier == 3 { return "T\(segment)" }
        return "\(segment)"
    }
}

/// Nastavení klasické tréninkové hry: přehled, volby podle hry a start.
struct ClassicTrainingSetupView: View {
    @EnvironmentObject private var store: AppStore
    let definition: TrainingDefinition
    private let spec: ClassicTrainingSpec

    @State private var config: TrainingConfig
    @State private var playing = false
    @State private var showInfo = false

    init(definition: TrainingDefinition, segment: Int? = nil) {
        self.definition = definition
        let spec = ClassicTrainingSpec.spec(for: definition.id)
        self.spec = spec
        var initial = spec.defaults
        if let segment, spec.targets.contains(segment) { initial.segments = [segment] }
        _config = State(initialValue: initial)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                hero
                if spec.settings.isEmpty {
                    Label("Hraje se podle klasických pravidel, bez nastavení.", systemImage: "checkmark.seal")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .padding(16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Theme.card, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                } else {
                    ForEach(spec.settings, id: \.self) { setting(for: $0) }
                }
            }
            .padding(20)
            .frame(maxWidth: 760)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            TrainingStartBar(title: "Hrát") { playing = true }
        }
        .toolbar(.hidden, for: .tabBar)
        .screen()
        .navigationTitle(definition.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showInfo = true } label: { Image(systemName: "info.circle") }
                    .accessibilityLabel("Pravidla")
            }
        }
        .sheet(isPresented: $showInfo) {
            TrainingInfoSheet(definition: definition) { showInfo = false }
        }
        .fullScreenCover(isPresented: $playing) {
            NavigationStack {
                TrainingPlayView(definition: definition, config: config)
            }
            .environmentObject(store)
        }
    }

    private var hero: some View {
        let colors = definition.category.tileColors
        let best = store.bestTrainingResult(for: definition.id)
        return VStack(alignment: .leading, spacing: 10) {
            Image(systemName: definition.category.symbol)
                .font(.title3.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .background(.white.opacity(0.18), in: Circle())
                .accessibilityHidden(true)
            Text(definition.title)
                .font(.title2.weight(.bold))
                .foregroundStyle(.white)
            Text(definition.rules)
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.88))
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 14) {
                Label("\(definition.minutes) min", systemImage: "clock")
                if let best, !best.summary.isEmpty {
                    Label("Rekord: \(best.summary)", systemImage: "trophy.fill")
                        .lineLimit(1)
                }
            }
            .font(.caption.weight(.bold))
            .foregroundStyle(.white.opacity(0.8))
            .padding(.top, 2)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func setting(for setting: ClassicTrainingSpec.Setting) -> some View {
        switch setting {
        case .target:
            TrainingSettingCard(title: "Cíl") {
                RuleTiles(
                    options: spec.targets.map { (id: $0, title: spec.targetLabel($0), detail: nil) },
                    selection: config.segments?.first ?? spec.targets.first ?? 20,
                    columns: spec.targets.count
                ) { config.segments = [$0] }
            }
        case .darts:
            TrainingSettingCard(title: descent ? "Zavřít do šipek" : "Počet šipek") {
                RuleTiles(
                    options: spec.darts.map { (id: $0, title: "\($0)", detail: descent ? visitCount($0 / 3) : "\($0 / 3) kol") },
                    selection: config.dartCount ?? spec.darts.first ?? 30,
                    columns: spec.darts.count
                ) { config.dartCount = $0 }
            }
        case .rounds:
            TrainingSettingCard(title: descent ? "Počet pokusů" : "Počet kol") {
                RuleTiles(
                    options: spec.rounds.map { value -> (id: Int, title: String, detail: String?) in
                        if descent { return (id: value, title: value == 0 ? "∞" : "\(value)", detail: value == 0 ? "bez limitu" : "pokusů") }
                        return (id: value, title: "\(value)", detail: "\(value * 3) šipek")
                    },
                    selection: config.rounds ?? spec.rounds.first ?? 8,
                    columns: spec.rounds.count
                ) { config.rounds = $0 }
            }
        case .descent:
            TrainingSettingCard(title: "Čísla") {
                let start = config.targetScore ?? 141
                let floor = min(start, config.floorScore ?? 100)
                CountStepper(
                    title: "Začátek",
                    value: start,
                    caption: "Odsud začínáš",
                    canDecrease: start > 2,
                    canIncrease: start < 170
                ) { delta in
                    let next = min(170, max(2, start + delta))
                    config.targetScore = next
                    if floor > next { config.floorScore = next }
                }
                RuleTiles(
                    options: [170, 141, 121, 100].map { (id: $0, title: "\($0)", detail: nil) },
                    selection: start,
                    columns: 4
                ) { value in
                    config.targetScore = value
                    if floor > value { config.floorScore = value }
                }
                Divider()
                CountStepper(
                    title: "Spodní hranice",
                    value: floor,
                    caption: "Zavřením hra končí",
                    canDecrease: floor > 2,
                    canIncrease: floor < start
                ) { delta in
                    config.floorScore = min(start, max(2, floor + delta))
                }
                RuleTiles(
                    options: [40, 61, 81, 100].map { (id: $0, title: "\($0)", detail: nil) },
                    selection: floor,
                    columns: 4
                ) { config.floorScore = min(start, $0) }
            }
        case .accuracy:
            TrainingSettingCard(title: "Cíl úspěšnosti") {
                RuleTiles(
                    options: spec.accuracies.map { (id: $0, title: "\(Int(($0 * 100).rounded())) %", detail: nil) },
                    selection: config.requiredAccuracy ?? spec.accuracies.first ?? 0.25,
                    columns: spec.accuracies.count
                ) { config.requiredAccuracy = $0 }
            }
        case .level:
            TrainingSettingCard(title: "Obtížnost") {
                RuleTiles(
                    options: [TrainingLevel.beginner, .advanced, .pro].map { (id: $0, title: $0.title, detail: nil) },
                    selection: config.level,
                    columns: 3
                ) { config.level = $0 }
            }
        case .checkoutHint:
            TrainingSettingCard(title: "Checkout") {
                Toggle("Nápověda checkoutu", isOn: $config.showCheckouts)
            }
        }
    }

    private var descent: Bool { spec.settings.contains(.descent) }

    private func visitCount(_ count: Int) -> String {
        switch count {
        case 1: return "1 návštěva"
        case 2, 3, 4: return "\(count) návštěvy"
        default: return "\(count) návštěv"
        }
    }
}

struct TrainingSettingCard<Content: View>: View {
    var title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title).font(.headline)
            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(Theme.stroke, lineWidth: 1))
    }
}

struct TrainingStartBar: View {
    var title: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Text(title)
                    .font(.headline)
                    .contentTransition(.opacity)
                Image(systemName: "play.fill")
                    .font(.subheadline.weight(.bold))
            }
            .foregroundStyle(.black)
            .frame(maxWidth: .infinity, minHeight: 56)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.tint(Theme.brand).interactive(), in: Capsule())
        .padding(.horizontal, 20)
        .padding(.bottom, 6)
    }
}

/// Správná obrazovka nastavení pro hru z obrazovky Trénink.
struct TrainingSetupDestination: View {
    var launch: TrainingLaunch

    var body: some View {
        if launch.gameID == DoubleTraining.definitionID {
            DoubleTrainingSetupView(segment: launch.segment)
        } else if let definition = TrainingCatalog.find(launch.gameID) {
            ClassicTrainingSetupView(definition: definition, segment: launch.segment)
        } else {
            ContentUnavailableView("Hra není dostupná", systemImage: "questionmark.circle")
        }
    }
}

#if DEBUG
#Preview {
    NavigationStack {
        ClassicTrainingSetupView(definition: TrainingCatalog.find("treble-20")!)
    }
    .dartiqoPreview(PreviewSupport.store(activeMatch: false))
}
#endif
