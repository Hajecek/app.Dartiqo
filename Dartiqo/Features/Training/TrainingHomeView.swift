import SwiftUI
import AVKit

/// Stejný průvodce jako nový zápas: výběr kartou, zpět šipkou a lišta Domů / Pokračovat.
struct TrainingHomeView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dismiss) private var dismiss
    private let onHome: (() -> Void)?
    private let gameIDs: [String]?
    private let marksDaily: Bool

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

    init(gameIDs: [String]? = nil, marksDaily: Bool = false, onHome: (() -> Void)? = nil) {
        self.gameIDs = gameIDs
        self.marksDaily = marksDaily
        self.onHome = onHome
    }

    private var games: [TrainingDefinition] {
        let ids = gameIDs ?? TrainingCatalog.showcase
        return ids.compactMap(TrainingCatalog.find)
    }
    private var selected: TrainingDefinition? { games.first { $0.id == selectedID } ?? games.first }
    /// Jen hry, kde `rulesStep` opravdu nabízí nastavení (ne jen text / prázdno).
    private var selectedIsCricket: Bool {
        if case .cricket = selected?.kind { return true }
        return false
    }
    private var hasRulesStep: Bool {
        switch selected?.id {
        case "around-clock", "shanghai", "checkout-40", "treble-20", "practice-501":
            return true
        default:
            return selectedIsCricket
        }
    }
    private var stepTitles: [String] {
        hasRulesStep ? ["Hra", "Pravidla", "Souhrn"] : ["Hra", "Souhrn"]
    }
    private var stepCount: Int { stepTitles.count }
    private var isLastStep: Bool { step >= stepCount - 1 }
    private var rulesStepIndex: Int? { hasRulesStep ? 1 : nil }
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
                        else if step == rulesStepIndex { rulesStep }
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
        .animation(motion, value: hasRulesStep)
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
        .onAppear {
            guard let first = games.first?.id, !games.contains(where: { $0.id == selectedID }) else { return }
            choose(first)
        }
        .onChange(of: hasRulesStep) { _, _ in
            if step >= stepCount { setStep(stepCount - 1) }
        }
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
        if step == 0 { return "Jaká hra?" }
        if step == rulesStepIndex { return "Jak se hraje?" }
        return "Všechno sedí?"
    }

    private var subtitle: String {
        if step == 0 {
            return hasRulesStep
                ? "Vyber režim. Pravidla nastavíš v dalším kroku."
                : "Vyber režim. Na souhrnu zkontroluješ start."
        }
        if step == rulesStepIndex { return "Zapni, co se v téhle hře hraje." }
        return hasRulesStep ? "Kdo hraje a podle jakých pravidel." : "Zkontroluj výběr a spusť hru."
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
        case "shanghai":
            ruleCard("Čísla") {
                numberGrid(values: Array(1...20))
            }
        case _ where selectedIsCricket:
            ruleCard("Čísla") {
                numberGrid(values: Array(1...20) + [25])
                Text("Ve hře se ukážou jen zapnutá čísla, bez celé klávesnice.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
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

    private func numberGrid(values: [Int]) -> some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 5), spacing: 8) {
            ForEach(values, id: \.self) { number in
                let on = numbers.contains(number)
                let last = on && numbers.count == 1
                Button {
                    if on, numbers.count > 1 { numbers.remove(number) }
                    else if !on { numbers.insert(number) }
                } label: {
                    Text(number == 25 ? "B" : "\(number)")
                        .font(.system(.headline, design: .rounded, weight: .bold))
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .foregroundStyle(on ? Color.black : Color.primary)
                        .background(on ? Theme.brand : Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(last)
                .accessibilityLabel(number == 25 ? "Bull" : "\(number)")
                .accessibilityAddTraits(on ? .isSelected : [])
            }
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
                if let rulesStepIndex {
                    summaryRow("Pravidla", rulesSummary, symbol: "slider.horizontal.3") { setStep(rulesStepIndex) }
                }
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
        if step == rulesStepIndex, selected?.id == "shanghai" || selectedIsCricket { return !numbers.isEmpty }
        return true
    }

    private var rulesSummary: String {
        switch selected?.id {
        case "around-clock": return "Limit \(dartCount) šipek"
        case "bobs-27": return "D1–D20 · start 27"
        case "shanghai": return numbers.sorted().map(String.init).joined(separator: ", ")
        case _ where selectedIsCricket: return MatchOptions.cricketNumbersLine(Array(numbers))
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
        case _ where selectedIsCricket:
            value.segments = MatchOptions.orderedCricketNumbers(Array(numbers))
        case "checkout-40", "practice-501":
            value.showCheckouts = showCheckouts
        default:
            break
        }
        value.isDaily = marksDaily
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
        if case .cricket(let picked, _) = TrainingCatalog.find(id)?.kind {
            numbers = Set(picked)
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

/// Okno hry: animace terče, švihnutím video a pod tím přesný postup.
struct TrainingInfoSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var definition: TrainingDefinition
    var onSelect: () -> Void

    @State private var beat = 0
    @State private var page = 0

    private var lesson: TrainingLesson { TrainingLesson.load(definition.id) }
    private var shown: TrainingDemoBeat { lesson.beats[beat % lesson.beats.count] }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    TabView(selection: $page) {
                        animationPage.tag(0)
                        TrainingClipPage(gameID: definition.id).tag(1)
                    }
                    .tabViewStyle(.page(indexDisplayMode: .always))
                    .frame(height: 430)
                    Text(page == 0 ? "Potáhni doleva pro video" : "Potáhni doprava pro animaci")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                    VStack(alignment: .leading, spacing: 10) {
                        Text("O co jde")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.secondary)
                        Text(definition.summary)
                            .font(.body)
                        Text("Co udělat")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.secondary)
                            .padding(.top, 4)
                        ForEach(Array(lesson.steps.enumerated()), id: \.offset) { index, step in
                            HStack(alignment: .firstTextBaseline, spacing: 10) {
                                Text("\(index + 1)")
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(.black)
                                    .frame(width: 22, height: 22)
                                    .background(Theme.brand, in: Circle())
                                Text(step)
                                    .font(.body)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
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
            guard !reduceMotion, lesson.beats.count > 1 else { return }
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 2_800_000_000)
                guard !Task.isCancelled else { return }
                beat = (beat + 1) % lesson.beats.count
            }
        }
    }

    private var animationPage: some View {
        VStack(spacing: 12) {
            TouchDartboard(marks: shown.darts, interactive: false, showMarkNumbers: shown.darts.count > 1) { _ in }
                .frame(maxWidth: 300)
                .frame(maxWidth: .infinity)
            Text(shown.caption)
                .font(.headline)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .frame(minHeight: 72, alignment: .top)
        }
        .padding(.horizontal, 8)
    }
}

/// Video ke hře je soubor `TrainingVideos/<id>.mp4` v aplikaci, třeba `around-clock.mp4`.
enum TrainingClip {
    static func url(for id: String) -> URL? {
        let folders: [String?] = ["TrainingVideos", "Resources/TrainingVideos", nil]
        for ext in ["mp4", "mov", "m4v"] {
            for folder in folders {
                if let folder, let url = Bundle.main.url(forResource: id, withExtension: ext, subdirectory: folder) {
                    return url
                }
                if folder == nil, let url = Bundle.main.url(forResource: id, withExtension: ext) {
                    return url
                }
            }
        }
        return nil
    }
}

private struct TrainingClipPage: View {
    var gameID: String

    var body: some View {
        Group {
            if let url = TrainingClip.url(for: gameID) {
                TrainingClipPlayer(url: url)
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "video.fill")
                        .font(.system(size: 36, weight: .semibold))
                        .foregroundStyle(.black)
                        .frame(width: 72, height: 72)
                        .background(Theme.brand, in: Circle())
                        .accessibilityHidden(true)
                    Text("Sem přijde vaše video")
                        .font(.headline)
                    Text("Ke každé hře doplníte vlastní vysvětlení. Až ho přidáte, přehraje se tady místo téhle plochy.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(24)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Theme.card, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                .padding(.horizontal, 8)
                .padding(.bottom, 28)
            }
        }
    }
}

private struct TrainingClipPlayer: View {
    var url: URL
    @State private var player: AVPlayer?

    var body: some View {
        VideoPlayer(player: player)
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .padding(.horizontal, 8)
            .padding(.bottom, 28)
            .onAppear {
                if player == nil { player = AVPlayer(url: url) }
                player?.play()
            }
            .onDisappear { player?.pause() }
    }
}

private struct TrainingDemoBeat {
    var darts: [Dart]
    var caption: String
}

private struct TrainingLesson {
    var beats: [TrainingDemoBeat]
    var steps: [String]

    static func load(_ id: String) -> TrainingLesson {
        switch id {
        case "around-clock":
            return TrainingLesson(beats: [
                TrainingDemoBeat(darts: [Dart(1)], caption: "Začni na 1. Platí single, double i triple."),
                TrainingDemoBeat(darts: [Dart(2)], caption: "Zásah posune cíl na 2, potom na 3 a dál."),
                TrainingDemoBeat(darts: [Dart(5)], caption: "Minutí tě nevrací. Zůstáváš na stejném čísle."),
                TrainingDemoBeat(darts: [Dart(20)], caption: "Po 1 až 19 přijde dvacítka."),
                TrainingDemoBeat(darts: [Dart(25, 2)], caption: "Kolo uzavře bull. Platí 25 i 50.")
            ], steps: [
                "Hoď na číslo 1. Zásah je single, double i triple.",
                "Po zásahu se cíl posune o jedno číslo výš, až na 20.",
                "Když mineš, číslo se nemění a házíš na něj znovu.",
                "Po dvacítce tref střed. Zelená 25 i červená 50 kolo ukončí.",
                "Hra končí zásahem bullu, nebo když dojde limit šipek."
            ])
        case "bobs-27":
            return TrainingLesson(beats: [
                TrainingDemoBeat(darts: [Dart(1, 2)], caption: "Kolo D1. Zásah přičte 2 body ke startu 27."),
                TrainingDemoBeat(darts: [Dart(1)], caption: "S1 se nepočítá. V kole platí jen double."),
                TrainingDemoBeat(darts: [Dart(16, 2)], caption: "D16 přičte 32. Každé kolo je další double."),
                TrainingDemoBeat(darts: [Dart(20, 2)], caption: "Po D20 vyhrává skóre nad nulou.")
            ], steps: [
                "Začínáš na 27. Kola jdou D1, D2, až D20 a v každém máš tři šipky.",
                "Trefený double přičte svou hodnotu. D1 přidá 2, D20 přidá 40.",
                "Single a triple toho čísla jsou minuta a body nepřidají.",
                "Když v kole mineš všechny tři šipky, stejná hodnota se odečte.",
                "Nula a méně hru prohrává. Po D20 vyhráváš, jen když zůstanou body nad nulou."
            ])
        case "shanghai":
            return TrainingLesson(beats: [
                TrainingDemoBeat(darts: [Dart(1)], caption: "Kolo na 1. První šipka může být single."),
                TrainingDemoBeat(darts: [Dart(1), Dart(1, 2)], caption: "K ní přidej double stejného čísla."),
                TrainingDemoBeat(darts: [Dart(1), Dart(1, 2), Dart(1, 3)], caption: "Single, double i triple v jedné návštěvě je Shanghai."),
                TrainingDemoBeat(darts: [Dart(7)], caption: "Čísla jdou od nejmenšího. Výchozí řada je 1 až 7.")
            ], steps: [
                "Každé kolo patří jednomu číslu. Výchozí jsou 1 až 7, od nejmenšího.",
                "V kole máš tři šipky. Počítá se jen číslo toho kola.",
                "Když v jedné návštěvě trefíš single, double i triple, hra hned končí výhrou.",
                "Bez Shanghai se zásahy sčítají. Po posledním čísle stačí skóre nad nulou.",
                "V pravidlech si čísla zapneš a vypneš. Hraje se jen to, co necháš zapnuté."
            ])
        case "checkout-40":
            return TrainingLesson(beats: [
                TrainingDemoBeat(darts: [Dart(20, 2)], caption: "Ze 40 je nejkratší cesta jedna šipka, D20."),
                TrainingDemoBeat(darts: [Dart(20), Dart(10, 2)], caption: "S20 a D10 je taky přesně 40."),
                TrainingDemoBeat(darts: [Dart(10, 2), Dart(10, 2)], caption: "Dvě D10 platí. Poslední šipka musí být double."),
                TrainingDemoBeat(darts: [Dart(20, 3)], caption: "T20 je 60. To je přehoz a čtyřicítka se vrací.")
            ], steps: [
                "Na začátku máš 40 a jednu návštěvu, tedy nejvýš tři šipky.",
                "Na nulu se musíš dostat doublem. Nejkratší hod je D20.",
                "Platí i jiná přesná cesta, třeba S20 a D10, nebo dvě D10.",
                "Poslední šipka, která zavře, musí být double. Single ani triple čtyřicítku nezavřou.",
                "Přehoz vrací skóre na 40. Kolo je splněné, jen když skončíš přesně na nule."
            ])
        case "treble-20":
            return TrainingLesson(beats: [
                TrainingDemoBeat(darts: [Dart(20, 3)], caption: "Jediný platný zásah je T20."),
                TrainingDemoBeat(darts: [Dart(20)], caption: "S20 je minuta, i když leží na dvacítce."),
                TrainingDemoBeat(darts: [Dart(20, 2)], caption: "D20 taky neplatí. Chce to trojitý prstenec."),
                TrainingDemoBeat(darts: [Dart(20, 3), Dart(20, 3), Dart(20, 3)], caption: "Tři T20 jsou čistá návštěva. Jiných 60 bodů se nepočítá.")
            ], steps: [
                "Házej na trojitou dvacítku. Počítá se jen T20.",
                "Single 20 a double 20 jsou minuta, body z nich neber.",
                "Libovolný jiný součet 60, třeba T19 a S3, zásah není.",
                "Každé T20 přidá jeden úspěšný hod. Série roste jen z dalších T20.",
                "Po daném počtu šipek uspěješ, když trefíš požadovaný podíl."
            ])
        case "bull-challenge":
            return TrainingLesson(beats: [
                TrainingDemoBeat(darts: [Dart(25)], caption: "Zelený střed, 25, je zásah."),
                TrainingDemoBeat(darts: [Dart(25, 2)], caption: "Červený střed, 50, je taky zásah."),
                TrainingDemoBeat(darts: [Dart(20)], caption: "Číslo mimo střed se nepočítá."),
                TrainingDemoBeat(darts: [Dart(25, 2), Dart(25)], caption: "Stačí kterýkoli střed. Sleduje se podíl zásahů.")
            ], steps: [
                "Cíl je jen střed terče. Oba kroužky platí.",
                "Zelená 25 je jeden zásah. Červená 50 je taky jeden zásah.",
                "Single, double ani triple čísla 1 až 20 se nepočítají.",
                "Každá šipka je jeden pokus. Minutí sérii úspěšnosti snižuje.",
                "Po daném počtu šipek uspěješ, když střed trefíš dost často."
            ])
        case "cricket-practice":
            return TrainingLesson(beats: [
                TrainingDemoBeat(darts: [Dart(20), Dart(20), Dart(20)], caption: "Tři singly zavřou dvacítku."),
                TrainingDemoBeat(darts: [Dart(20, 3)], caption: "Jedno T20 zavře prázdné číslo najednou."),
                TrainingDemoBeat(darts: [Dart(19)], caption: "Pak jdou 19, 18, 17, 16 a 15."),
                TrainingDemoBeat(darts: [Dart(25, 2)], caption: "Nakonec bull. 25 je jedna značka, 50 jsou dvě.")
            ], steps: [
                "Zavíráš 20, 19, 18, 17, 16, 15 a bull. Soupeře nemáš.",
                "Každý zásah čísla je jedna značka. Tři značky číslo zavřou.",
                "Triple dá tři značky, takže prázdné číslo zavře jednou šipkou.",
                "Další zásah zavřeného čísla už nic nepřidá. Body se nesbírají.",
                "Bull bere oba středy. 25 je jedna značka, 50 jsou dvě. Hra končí, když je zavřené všechno.",
                "V pravidlech si čísla zapneš a vypneš. Na klávesnici zůstanou jen ta."
            ])
        case "practice-501":
            return TrainingLesson(beats: [
                TrainingDemoBeat(darts: [Dart(20, 3), Dart(20, 3), Dart(20, 3)], caption: "Z 501 se odečítá. Tři T20 uberou 180."),
                TrainingDemoBeat(darts: [Dart(20)], caption: "S20 ubere 20. Počítá se každá šipka návštěvy."),
                TrainingDemoBeat(darts: [Dart(20, 2)], caption: "Zbylých 40 zavře D20. Na nulu se jde doublem."),
                TrainingDemoBeat(darts: [Dart(19, 3)], caption: "Přehoz, nebo nula bez doublu, celou návštěvu zahodí.")
            ], steps: [
                "Začínáš na 501. Každá šipka od skóre odečte svou hodnotu.",
                "Návštěva jsou tři šipky. T20, T20 a T20 je 180 a víc v jednom kole nejde.",
                "Pod nulu se dostat nesmíš. Takový hod je přehoz a vrací skóre z začátku návštěvy.",
                "Nula platí jen doublem. Zbylých 40 zavře D20, zbylých 32 zavře D16.",
                "Leg je hotový, když skončíš přesně na nule. Sleduje se průměr a počet šipek."
            ])
        case "checkout-descent":
            return TrainingLesson(beats: [
                TrainingDemoBeat(darts: [Dart(20, 3), Dart(19, 3), Dart(12, 2)], caption: "Start 141. Zavřeš v limitu a jdeš na 140."),
                TrainingDemoBeat(darts: [Dart(20, 3), Dart(20)], caption: "Limit šipek došel bez zavření. Jdeš o číslo výš."),
                TrainingDemoBeat(darts: [Dart(20, 3), Dart(20, 3), Dart(10, 2)], caption: "Zavření první návštěvou je záchyt. Výš už nespadneš."),
                TrainingDemoBeat(darts: [Dart(20, 2)], caption: "Zavřením spodní hranice hra končí.")
            ], steps: [
                "Vybereš si začáteční číslo, třeba 141, a spodní hranici, kde hra končí.",
                "Vybereš i počet šipek na jedno číslo. 9 šipek jsou tři návštěvy.",
                "Když číslo v limitu zavřeš, další pokus je o jedno níž.",
                "Když ho v limitu nezavřeš, další pokus je o jedno výš, nejvýš 170.",
                "Zavření hned první návštěvou číslo uloží jako záchyt. Neúspěch tě nad něj už nevrátí.",
                "Hra končí zavřením spodní hranice, nebo když dojdou pokusy."
            ])
        case DoubleTraining.definitionID:
            return TrainingLesson(beats: [
                TrainingDemoBeat(darts: [Dart(16, 2)], caption: "Cíl je jeden double, třeba D16. Zásah se počítá."),
                TrainingDemoBeat(darts: [Dart(16)], caption: "S16 je minuta, i když leží na stejném čísle."),
                TrainingDemoBeat(darts: [Dart(8, 2)], caption: "Jiný double taky neplatí. Platí jen zvolený."),
                TrainingDemoBeat(darts: [Dart(16, 2), Dart(16, 2), Dart(16)], caption: "Po sérii se spočítá úspěšnost.")
            ], steps: [
                "Vyber si double sám, nebo vezmi doporučený nejslabší ze svých statistik.",
                "Celou sérii házíš jen na tento double. Každá šipka je jeden pokus.",
                "Single ani triple stejného čísla se nepočítají. U bullu platí jen 50.",
                "Po posledním hodu uspěješ, když trefíš aspoň zvolený podíl šipek.",
                "Zásahy se propisují do statistik, takže příští doporučení vychází i z tréninku."
            ])
        default:
            return TrainingLesson(
                beats: [TrainingDemoBeat(darts: [Dart(20)], caption: definitionFallback)],
                steps: ["Tref zvýrazněný segment.", "Postupuj podle popisu hry, dokud ji nesplníš."]
            )
        }
    }

    private static var definitionFallback: String { "Tref zvýrazněný segment." }
}

#if DEBUG
#Preview {
    NavigationStack { TrainingHomeView() }.dartiqoPreview(PreviewSupport.store(activeMatch: false))
}
#endif
