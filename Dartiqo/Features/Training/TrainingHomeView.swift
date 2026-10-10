import SwiftUI

/// Stejný průvodce jako nový zápas: výběr kartou, zpět šipkou a lišta Domů / Pokračovat.
struct TrainingHomeView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dismiss) private var dismiss
    private let onHome: (() -> Void)?

    @State private var selectedID = TrainingCatalog.showcase.first ?? "around-clock"
    @State private var step = 0
    @State private var playing: TrainingDefinition?
    @State private var info: TrainingDefinition?
    @State private var resume = false
    @State private var dartCount = 80
    @State private var limitCustom = false
    @State private var accuracy = 0.25
    @State private var showCheckouts = true
    @State private var numbers = Set(1...7)

    init(onHome: (() -> Void)? = nil) {
        self.onHome = onHome
    }

    private var games: [TrainingDefinition] { TrainingCatalog.showcaseGames }
    private var selected: TrainingDefinition? { games.first { $0.id == selectedID } ?? games.first }
    private let stepTitles = ["Hra", "Pravidla", "Souhrn"]
    private var stepCount: Int { stepTitles.count }
    private var isLastStep: Bool { step >= stepCount - 1 }
    private var motion: Animation? { reduceMotion ? nil : .smooth(duration: 0.38) }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    progress
                    VStack(alignment: .leading, spacing: 6) {
                        Text(headline)
                            .font(.system(size: 32, weight: .bold, design: .rounded))
                        Text(subtitle)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Group {
                        if step == 0 { gameStep }
                        else if step == 1 { rulesStep }
                        else { summaryStep }
                    }
                    .id(step)
                    .transition(.opacity.combined(with: .offset(y: 10)))
                }
                .id("setup-top")
                .padding(22)
                .frame(maxWidth: 760)
            }
            .onChange(of: step) { _, _ in
                proxy.scrollTo("setup-top", anchor: .top)
            }
        }
        .animation(motion, value: step)
        .safeAreaInset(edge: .bottom, spacing: 0) { setupBar }
        .toolbar(.hidden, for: .tabBar)
        .screen()
        .navigationTitle("Nový trénink")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(step > 0)
        .toolbar {
            if step > 0 {
                ToolbarItem(placement: .topBarLeading) {
                    Button { setStep(step - 1) } label: {
                        Image(systemName: "chevron.left")
                    }
                    .accessibilityLabel("Předchozí krok")
                }
            }
        }
        .sensoryFeedback(.selection, trigger: step)
        .sheet(item: $info) { definition in
            TrainingInfoSheet(definition: definition) {
                info = nil
                selectedID = definition.id
            }
        }
        .fullScreenCover(item: $playing) { definition in
            NavigationStack {
                TrainingPlayView(definition: definition, config: playConfig, resume: resume ? store.activeTrainingSession : nil)
            }
            .environmentObject(store)
        }
    }

    private var headline: String {
        switch step {
        case 0: return "Jaká hra?"
        case 1: return "Jak se hraje?"
        default: return "Všechno sedí?"
        }
    }

    private var subtitle: String {
        switch step {
        case 0: return "Vyber režim. Pravidla nastavíš v dalším kroku."
        case 1: return "Zapni, co se v téhle hře hraje."
        default: return "Kdo hraje a podle jakých pravidel."
        }
    }

    private var progress: some View {
        VStack(alignment: .leading, spacing: 10) {
            GeometryReader { geo in
                let fraction = CGFloat(step + 1) / CGFloat(stepCount)
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.primary.opacity(0.10))
                    Capsule()
                        .fill(Theme.brand)
                        .frame(width: max(18, geo.size.width * fraction))
                }
            }
            .frame(height: 6)
            .accessibilityHidden(true)
            HStack(spacing: 0) {
                ForEach(0..<stepCount, id: \.self) { index in
                    Button { if index < step { setStep(index) } } label: {
                        Text(stepTitles[index])
                            .font(.caption.weight(index == step ? .bold : .medium))
                            .foregroundStyle(index == step ? Theme.accent : (index < step ? .primary : .secondary))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.plain)
                    .disabled(index > step)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Krok \(step + 1) ze \(stepCount), \(stepTitles[min(step, stepTitles.count - 1)])")
    }

    private var gameStep: some View {
        VStack(spacing: 12) {
            ForEach(games) { definition in
                ChoiceCard(title: definition.title, detail: definition.summary, symbol: definition.category.symbol, selected: definition.id == selectedID, action: {
                    withAnimation(motion) { choose(definition.id) }
                }, info: { info = definition })
            }
            if let active = store.activeTrainingSession, active.status == .playing, let definition = TrainingCatalog.find(active.definitionID) {
                Button {
                    selectedID = definition.id
                    resume = true
                    playing = definition
                } label: {
                    Label("Pokračovat v rozehraném", systemImage: "clock.arrow.circlepath")
                        .font(.subheadline.bold())
                        .frame(maxWidth: .infinity)
                        .padding(16)
                }
                .foregroundStyle(Theme.action)
            }
        }
    }

    @ViewBuilder
    private var rulesStep: some View {
        switch selected?.id {
        case "around-clock":
            ruleCard("Limit šipek") {
                let presets = [40, 60, 80, 100]
                let custom = limitCustom || !presets.contains(dartCount)
                RuleTiles(
                    options: presets.map { (id: $0, title: "\($0)", detail: "\($0 / 3) kol") }
                        + [(id: 0, title: "Vlastní", detail: custom ? "\(dartCount) šipek" : "krok po 5")],
                    selection: custom ? 0 : dartCount,
                    columns: 3
                ) { value in
                    withAnimation(motion) {
                        if value == 0 {
                            limitCustom = true
                        } else {
                            limitCustom = false
                            dartCount = value
                        }
                    }
                }
                if custom {
                    CountStepper(
                        title: "Šipky",
                        value: dartCount,
                        caption: "Konec po \(dartCount) šipkách",
                        canDecrease: dartCount > 20,
                        canIncrease: dartCount < 120
                    ) { delta in
                        dartCount = min(120, max(20, dartCount + delta * 5))
                    }
                }
            }
        case "bobs-27":
            ruleCard("Cíle") {
                Text("D1 až D20, start 27, tři šipky na double.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        case "shanghai":
            ruleCard("Čísla") {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 5), spacing: 8) {
                    ForEach(1...20, id: \.self) { number in
                        let on = numbers.contains(number)
                        Button {
                            if on, numbers.count > 1 { numbers.remove(number) }
                            else { numbers.insert(number) }
                        } label: {
                            Text("\(number)")
                                .font(.system(.headline, design: .rounded, weight: .bold))
                                .frame(maxWidth: .infinity, minHeight: 44)
                                .foregroundStyle(on ? Color.black : Color.primary)
                                .background(on ? Theme.brand : Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(on ? .isSelected : [])
                    }
                }
            }
        case "checkout-40":
            ruleCard("Checkout") {
                Toggle("Nápověda checkoutu", isOn: $showCheckouts)
            }
        case "treble-20":
            ruleCard("Série") {
                Stepper("\(dartCount) šipek", value: $dartCount, in: 9...90, step: 3)
                VStack(alignment: .leading, spacing: 6) {
                    Text("Úspěšnost \(Int((accuracy * 100).rounded())) %")
                        .font(.subheadline.weight(.semibold))
                    Slider(value: $accuracy, in: 0.1...0.8, step: 0.05)
                }
            }
        case "practice-501":
            ruleCard("501") {
                Toggle("Nápověda checkoutu", isOn: $showCheckouts)
            }
        default:
            EmptyView()
        }
    }

    private func ruleCard<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title).font(.headline)
            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(Theme.stroke, lineWidth: 1))
    }

    private var summaryStep: some View {
        VStack(spacing: 12) {
            if let selected {
                summaryRow("Hra", selected.title, symbol: selected.category.symbol) { setStep(0) }
                summaryRow("Pravidla", rulesSummary, symbol: "slider.horizontal.3") { setStep(1) }
                summaryRow("Délka", "\(selected.listed.title) · \(selected.minutes) min", symbol: "clock") { setStep(0) }
            }
        }
    }

    private func summaryRow(_ title: String, _ value: String, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: symbol)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.action)
                    .frame(width: 38, height: 38)
                    .background(Theme.action.opacity(0.12), in: Circle())
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.caption).foregroundStyle(.secondary)
                    Text(value).font(.headline).lineLimit(2)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right").font(.footnote.weight(.bold)).foregroundStyle(.secondary)
            }
            .padding(16)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.primary)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(Theme.stroke, lineWidth: 1))
    }

    private var setupBar: some View {
        GlassEffectContainer(spacing: 10) {
            HStack(spacing: 10) {
                Button {
                    if let onHome { onHome() } else { dismiss() }
                } label: {
                    Image(systemName: "house.fill")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.primary)
                        .frame(width: 56, height: 56)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .glassEffect(.regular.interactive(), in: Circle())
                .accessibilityLabel("Domů")

                Button { advance() } label: {
                    HStack(spacing: 8) {
                        Text(isLastStep ? "Hrát" : "Pokračovat")
                            .font(.headline)
                            .contentTransition(.opacity)
                        Image(systemName: isLastStep ? "play.fill" : "arrow.right")
                            .font(.subheadline.weight(.bold))
                            .contentTransition(.symbolEffect(.replace))
                    }
                    .foregroundStyle(canAdvance ? Color.black : Color.secondary)
                    .frame(maxWidth: .infinity, minHeight: 56)
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .glassEffect(canAdvance ? .regular.tint(Theme.brand).interactive() : .regular, in: Capsule())
                .disabled(!canAdvance)
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 6)
    }

    private var canAdvance: Bool {
        if step == 1, selected?.id == "shanghai" { return !numbers.isEmpty }
        return true
    }

    private var rulesSummary: String {
        switch selected?.id {
        case "around-clock": return "Limit \(dartCount) šipek"
        case "bobs-27": return "D1–D20 · start 27"
        case "shanghai": return numbers.sorted().map(String.init).joined(separator: ", ")
        case "checkout-40": return showCheckouts ? "40 · s nápovědou" : "40 · bez nápovědy"
        case "treble-20": return "\(dartCount) šipek · \(Int((accuracy * 100).rounded())) %"
        case "practice-501": return showCheckouts ? "501 · s nápovědou" : "501 · bez nápovědy"
        default: return ""
        }
    }

    private var playConfig: TrainingConfig {
        var value = TrainingConfig()
        switch selected?.id {
        case "around-clock", "treble-20":
            value.dartCount = dartCount
            if selected?.id == "treble-20" { value.requiredAccuracy = accuracy }
        case "shanghai":
            value.segments = numbers.sorted()
        case "checkout-40", "practice-501":
            value.showCheckouts = showCheckouts
        default:
            break
        }
        return value
    }

    private func choose(_ id: String) {
        guard id != selectedID else { return }
        selectedID = id
        switch id {
        case "around-clock": dartCount = 80; limitCustom = false
        case "treble-20": dartCount = 30; accuracy = 0.25
        case "shanghai": numbers = Set(1...7)
        case "checkout-40", "practice-501": showCheckouts = true
        default: break
        }
    }

    private func setStep(_ value: Int) {
        resume = false
        withAnimation(motion) { step = value }
    }

    private func advance() {
        if isLastStep {
            resume = false
            playing = selected
        } else {
            setStep(step + 1)
        }
    }
}

/// Okno hry: terč přehraje cíle a pod ním je, co se má udělat.
private struct TrainingInfoSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var definition: TrainingDefinition
    var onSelect: () -> Void

    @State private var beat = 0

    private var beats: [TrainingDemoBeat] { TrainingDemoBeat.script(definition.id) }
    private var shown: TrainingDemoBeat { beats[beat % beats.count] }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    TouchDartboard(marks: shown.darts, interactive: false, showMarkNumbers: shown.darts.count > 1) { _ in }
                        .frame(maxWidth: 320)
                        .frame(maxWidth: .infinity)
                    Text(shown.caption)
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .multilineTextAlignment(.center)
                    VStack(alignment: .leading, spacing: 8) {
                        Text("O co jde")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.secondary)
                        Text(definition.summary)
                            .font(.body)
                        Text("Co udělat")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.secondary)
                            .padding(.top, 4)
                        Text(definition.rules)
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.card, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                    Button("Vybrat tuhle hru", action: onSelect)
                        .buttonStyle(PrimaryButton())
                }
                .padding(20)
                .animation(reduceMotion ? nil : .spring(response: 0.45, dampingFraction: 0.82), value: beat)
            }
            .screen()
            .navigationTitle(definition.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Zavřít") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .task(id: definition.id) {
            guard !reduceMotion, beats.count > 1 else { return }
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 2_800_000_000)
                guard !Task.isCancelled else { return }
                beat = (beat + 1) % beats.count
            }
        }
    }
}

private struct TrainingDemoBeat {
    var darts: [Dart]
    var caption: String

    static func script(_ id: String) -> [TrainingDemoBeat] {
        switch id {
        case "around-clock":
            return (1...5).map { TrainingDemoBeat(darts: [Dart($0)], caption: "Tref \($0). Další číslo přijde až po zásahu.") }
        case "bobs-27":
            return [
                TrainingDemoBeat(darts: [Dart(1, 2)], caption: "D1 přičte 2 body."),
                TrainingDemoBeat(darts: [Dart(16, 2)], caption: "D16 přičte 32. Tři minuly stejnou hodnotu odečtou."),
                TrainingDemoBeat(darts: [Dart(20, 2)], caption: "Po D20 vyhrává skóre nad nulou.")
            ]
        case "shanghai":
            return [
                TrainingDemoBeat(darts: [Dart(1)], caption: "Na čísle kola nejdřív single."),
                TrainingDemoBeat(darts: [Dart(1), Dart(1, 2)], caption: "Pak double stejného čísla."),
                TrainingDemoBeat(darts: [Dart(1), Dart(1, 2), Dart(1, 3)], caption: "Single, double i triple v jedné návštěvě je výhra.")
            ]
        case "checkout-40":
            return [
                TrainingDemoBeat(darts: [Dart(20, 2)], caption: "40 zavřeš doublem. Nejjistší je D20."),
                TrainingDemoBeat(darts: [Dart(10, 2), Dart(10, 2)], caption: "Dvě D10 platí taky. Přehoz vrací čtyřicítku.")
            ]
        case "treble-20":
            return [
                TrainingDemoBeat(darts: [Dart(20, 3)], caption: "Platí jen T20."),
                TrainingDemoBeat(darts: [Dart(20)], caption: "Single 20 je minuta, i když dá dvacet bodů."),
                TrainingDemoBeat(darts: [Dart(20, 3), Dart(20, 3)], caption: "Série roste jen z dalších trojitých dvacítek.")
            ]
        case "practice-501":
            return [
                TrainingDemoBeat(darts: [Dart(20, 3), Dart(20, 3), Dart(20, 3)], caption: "Body se sbírají po třech šipkách. 180 je T20, T20, T20."),
                TrainingDemoBeat(darts: [Dart(20, 2)], caption: "Leg končí doublem. D20 zavře zbylých 40.")
            ]
        default:
            return [TrainingDemoBeat(darts: [Dart(20)], caption: "Tref zvýrazněný segment.")]
        }
    }
}
