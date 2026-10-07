import SwiftUI

struct PlayView: View {
    @EnvironmentObject var store: AppStore
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Eyebrow(text: "Match room")
                Text("Jak dnes\nzahraješ?").font(.system(size: 38, weight: .bold, design: .rounded))
                Text("Vyber hru. Sestav soupeře. Hraj po svém.").foregroundStyle(.secondary)
                ForEach(GameMode.allCases) { mode in
                    NavigationLink { SetupView(mode: mode) } label: {
                        HStack(spacing: 18) {
                            Image(systemName: mode.symbol).font(.title2).foregroundStyle(Theme.action).frame(width: 52, height: 58).background(Theme.action.opacity(0.1), in: RoundedRectangle(cornerRadius: 16))
                            VStack(alignment: .leading, spacing: 7) { Text(mode.shortTitle).font(.title3.bold()); Text(mode.detail).font(.caption).foregroundStyle(.secondary) }
                            Spacer(minLength: 0); Image(systemName: "arrow.up.right").foregroundStyle(.secondary)
                        }.foregroundStyle(.primary).surface()
                    }.buttonStyle(.plain)
                }
                if !store.presets.isEmpty {
                    Text("Tvoje předvolby").font(.title2.bold())
                    ForEach(store.presets) { preset in
                        NavigationLink { SetupView(mode: preset.setup.config.mode, preset: preset.setup) } label: {
                            HStack { Image(systemName: "bookmark.fill").foregroundStyle(Theme.action); VStack(alignment: .leading, spacing: 5) { Text(preset.name).bold(); Text(preset.setup.config.summary).font(.caption).foregroundStyle(.secondary) }; Spacer(); Image(systemName: "chevron.right") }.foregroundStyle(.primary).surface()
                        }.buttonStyle(.plain).contextMenu { Button("Odstranit předvolbu", role: .destructive) { store.deletePreset(preset.id) } }
                    }
                }
                Label("Hra a všechny předvolby fungují offline.", systemImage: "wifi.slash").font(.caption).foregroundStyle(.secondary)
            }.padding(22).frame(maxWidth: 760)
        }.screen().navigationTitle("Hrát").navigationBarTitleDisplayMode(.inline)
    }
}

private enum Opening {
    case random, pick, bull
}

struct SetupView: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var draft: SetupDraft
    @State private var step = 0
    @State private var live = false
    @State private var replace = false
    @State private var savePreset = false
    @State private var presetName = "Moje 501"
    @State private var scoreText = "501"
    @State private var scoreExact = false
    @State private var opening: Opening?
    @State private var pickedStarter: Int?
    @State private var bullWinner: Int?
    @State private var showBullOff = false
    @State private var chromeID = UUID()
    @EnvironmentObject private var setupChrome: MatchSetupChrome
    private let presetScores = [101, 301, 501, 701, 1001]
    private var options: Binding<MatchOptions> { Binding(get: { draft.config.settings }, set: { draft.config.options = $0 }) }
    init(mode: GameMode, preset: SetupDraft? = nil) { _draft = State(initialValue: preset ?? SetupDraft(mode: mode)) }
    private var canContinue: Bool { !draft.seats.dropFirst().contains { !$0.isBot && $0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty } }
    private var showsOpening: Bool { draft.seats.count > 1 }
    private var stepCount: Int { showsOpening ? 4 : 3 }
    private var stepTitles: [String] { showsOpening ? ["Hra", "Hráči", "Pravidla", "Start"] : ["Hra", "Hráči", "Pravidla"] }
    private var isLastStep: Bool { step >= stepCount - 1 }
    private var canPlay: Bool {
        guard canContinue else { return false }
        guard showsOpening else { return true }
        switch opening {
        case .random: return true
        case .pick: return pickedStarter != nil
        case .bull: return bullWinner != nil
        case nil: return false
        }
    }
    private var motion: Animation? { reduceMotion ? nil : .smooth(duration: 0.38) }
    private var usingExactScore: Bool { scoreExact || !presetScores.contains(draft.config.startingScore) }

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
                        else if step == 1 { rosterStep }
                        else if step == 2 { rulesStep }
                        else { openingStep }
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
        .screen()
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle("Nový zápas")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(step > 0)
        .toolbar {
            if step > 0 {
                ToolbarItem(placement: .topBarLeading) {
                    Button { setStep(step - 1) } label: {
                        Image(systemName: "chevron.left")
                    }
                    .buttonStyle(.glass)
                    .accessibilityLabel("Předchozí krok")
                }
            }
        }
        .sensoryFeedback(.selection, trigger: step)
        .onAppear {
            scoreText = "\(draft.config.startingScore)"
            if !presetScores.contains(draft.config.startingScore) { scoreExact = true }
            setupChrome.owner = chromeID
            pushChrome()
        }
        .onDisappear {
            guard setupChrome.owner == chromeID else { return }
            if !showBullOff && !live {
                setupChrome.title = nil
                setupChrome.owner = nil
            }
        }
        .onChange(of: chromeKey) { _, _ in
            guard setupChrome.owner == chromeID else { return }
            pushChrome()
        }
        .onChange(of: setupChrome.token) { _, _ in
            guard setupChrome.owner == chromeID else { return }
            advance()
        }
        .onChange(of: showsOpening) { _, shown in
            if !shown, step > 2 { setStep(2) }
        }
        .onChange(of: showBullOff) { _, shown in
            if !shown { pushChrome() }
        }
        .confirmationDialog("Máš rozehraný zápas", isPresented: $replace, titleVisibility: .visible) {
            Button("Pokračovat v rozehraném") { live = true }
            Button("Zahodit rozehraný a spustit nový", role: .destructive) { start() }
            Button("Zrušit", role: .cancel) {}
        }
        .fullScreenCover(isPresented: $live) { NavigationStack { MatchView() }.environmentObject(store) }
        .fullScreenCover(isPresented: $showBullOff) {
            BullOffView(names: draft.seats.indices.map(seatName), bots: draft.seats.indices.map { index in
                index == 0 ? nil : (draft.seats[index].isBot ? draft.seats[index].level : nil)
            }) { winner in
                bullWinner = winner
                opening = .bull
                showBullOff = false
            } onCancel: {
                showBullOff = false
                if bullWinner == nil { opening = nil }
            }
        }
    }

    private var headline: String {
        switch step {
        case 0: return "Jaká hra?"
        case 1: return "Kdo hraje?"
        case 2: return "Jak se hraje?"
        default: return "Kdo začíná?"
        }
    }

    private var subtitle: String {
        switch step {
        case 0: return "Vyber režim. Ostatní doladíš v dalším kroku."
        case 1: return "Ty a až tři soupeři. Kamarád, nebo bot."
        case 2: return "Jedna věc po druhé. Dole uvidíš, co z toho vznikne."
        default: return "Rozhodni, kdo hází první leg."
        }
    }

    private var chromeKey: String { "\(step)|\(stepCount)|\(canContinue)|\(canPlay)|\(isLastStep)" }

    private func pushChrome() {
        setupChrome.title = isLastStep ? "Hrát" : "Pokračovat"
        setupChrome.enabled = isLastStep ? canPlay : (step == 0 || canContinue)
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
        .accessibilityAdjustableAction { direction in
            if direction == .decrement, step > 0 { setStep(step - 1) }
        }
    }

    private var gameStep: some View {
        VStack(spacing: 12) {
            ForEach(GameMode.allCases) { mode in
                ChoiceCard(title: mode.shortTitle, detail: mode.detail, symbol: mode.symbol, selected: draft.config.mode == mode) {
                    withAnimation(motion) { draft.config.mode = mode }
                }
            }
            if let id = store.profile?.id.uuidString, let last = store.data.lastSetups?[id] {
                Button {
                    draft = last
                    scoreText = "\(last.config.startingScore)"
                    setStep(2)
                } label: {
                    Label("Použít poslední nastavení", systemImage: "clock.arrow.circlepath")
                        .font(.subheadline.bold())
                        .frame(maxWidth: .infinity)
                        .padding(16)
                }
                .foregroundStyle(Theme.action)
            }
        }
    }
    private var rosterKind: Int? {
        if draft.seats.count == 1 { return 2 }
        guard draft.seats.count == 2 else { return nil }
        return draft.seats[1].isBot ? 0 : 1
    }

    private var rosterStep: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 8) {
                quickRoster("S botem", icon: "cpu", kind: 0)
                quickRoster("Kamarádi", icon: "person.2", kind: 1)
                quickRoster("Sólo", icon: "person", kind: 2)
            }
            HStack { Avatar(name: store.profile?.name ?? "Já"); VStack(alignment: .leading, spacing: 5) { Text(store.profile?.name ?? "Já").font(.headline); Text("Tvůj profil · statistiky se ukládají").font(.caption).foregroundStyle(.secondary) }; Spacer(); Text("TY").font(.caption.bold()).foregroundStyle(Theme.action) }.surface()
            ForEach(Array(draft.seats.indices.dropFirst()), id: \.self) { i in seatCard(i) }
            if draft.seats.count < 4 {
                Button { withAnimation(motion) { draft.seats.append(SeatDraft(name: "Hráč \(draft.seats.count + 1)")) } } label: { Label("Přidat hráče nebo bota", systemImage: "plus.circle").font(.headline).frame(maxWidth: .infinity).padding(18).background(Theme.action.opacity(0.07), in: RoundedRectangle(cornerRadius: 20)).overlay(RoundedRectangle(cornerRadius: 20).stroke(Theme.action.opacity(0.25), style: StrokeStyle(lineWidth: 1, dash: [5,4]))) }.foregroundStyle(Theme.action)
            }
            Text("Všichni lidští hráči zapisují na tomto telefonu.").font(.caption).foregroundStyle(.secondary)
        }
    }

    private func quickRoster(_ title: String, icon: String, kind: Int) -> some View {
        let selected = rosterKind == kind
        return Button {
            withAnimation(motion) {
                draft.seats = [SeatDraft(name: "Já")]
                if kind != 2 { draft.seats.append(SeatDraft(name: kind == 0 ? "Bot" : "Kamarád", isBot: kind == 0)) }
                draft.starter = 0
            }
        } label: {
            Label(title, systemImage: icon)
                .font(.caption.bold())
                .frame(maxWidth: .infinity)
                .padding(.vertical, 15)
                .foregroundStyle(selected ? Theme.onAccent : .primary)
                .background(selected ? Theme.accentFill : Theme.card, in: RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
    private func seatCard(_ i: Int) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Avatar(name: draft.seats[i].name, bot: draft.seats[i].isBot)
                Picker("Typ hráče", selection: $draft.seats[i].isBot) { Text("Kamarád").tag(false); Text("Bot").tag(true) }.pickerStyle(.segmented)
                Button { draft.seats.remove(at: i); draft.starter = 0 } label: { Image(systemName: "minus.circle").frame(width: 44, height: 44) }.foregroundStyle(.secondary).accessibilityLabel("Odebrat hráče \(i + 1)")
            }
            if draft.seats[i].isBot {
                HStack { VStack(alignment: .leading, spacing: 4) { Text(BotLevel.get(draft.seats[i].level).name).font(.title3.bold()); Text("Přesnější skórování i zavírání s vyšší úrovní").font(.caption).foregroundStyle(.secondary) }; Spacer(); Text("\(draft.seats[i].level)").font(.system(size: 32, weight: .bold, design: .rounded)).foregroundStyle(Theme.action) }
                Slider(value: Binding(get: { Double(draft.seats[i].level) }, set: { draft.seats[i].level = Int($0) }), in: 1...10, step: 1).tint(Theme.action).accessibilityLabel("Úroveň bota \(i + 1)")
                HStack { Text("ZAČÁTEČNÍK"); Spacer(); Text("LEGENDA") }.font(.system(size: 9, weight: .bold, design: .monospaced)).foregroundStyle(.secondary)
            } else { TextField("Jméno kamaráda", text: $draft.seats[i].name).textFieldStyle(.roundedBorder).autocorrectionDisabled() }
        }.surface()
    }
    private var rulesStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            if draft.config.mode == .x01 { scoreGroup }
            if draft.config.mode == .x01 { finishGroup }
            if draft.config.mode == .cricket { cricketGroup }
            if draft.config.mode == .countUp { countUpGroup }
            if draft.config.mode == .aroundClock { clockGroup }
            if draft.config.mode == .x01 || draft.config.mode == .cricket { lengthGroup }
            flowGroup
            VStack(alignment: .leading, spacing: 14) {
                Eyebrow(text: "Připraveno ke hře")
                Text((0..<draft.seats.count).map(seatName).joined(separator: "  ·  ")).font(.headline)
                Text(draft.config.summary).font(.subheadline).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                Toggle("Uložit jako předvolbu", isOn: $savePreset).tint(Theme.action)
                if savePreset { TextField("Název předvolby", text: $presetName).textFieldStyle(.roundedBorder) }
            }
            .surface()
        }
    }

    private var scoreGroup: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Start").font(.headline)
            OptionSwitcher(
                options: presetScores.map { ($0, "\($0)") } + [(-1, "Přesně")],
                selection: usingExactScore ? -1 : draft.config.startingScore
            ) { id in
                withAnimation(motion) {
                    if id == -1 {
                        scoreExact = true
                    } else {
                        scoreExact = false
                        commitScore(id)
                    }
                }
            }
            if usingExactScore {
                TextField("Skóre", text: $scoreText)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.center)
                    .font(.system(size: 40, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .padding(.vertical, 8)
                    .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .onChange(of: scoreText) { _, raw in
                        let digits = String(raw.filter(\.isNumber).prefix(4))
                        if digits != raw { scoreText = digits; return }
                        if let value = Int(digits), (GameConfig.minimumScore...GameConfig.maximumScore).contains(value) {
                            draft.config.startingScore = value
                        }
                    }
                Text("Od \(GameConfig.minimumScore) do \(GameConfig.maximumScore).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .surface()
    }

    private var finishGroup: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Zavření").font(.headline)
            OptionSwitcher(options: OutRule.allCases.map { ($0, $0.shortTitle) }, selection: draft.config.outRule) { rule in
                withAnimation(motion) { draft.config.outRule = rule }
            }
            Text(draft.config.outRule.detail).font(.caption).foregroundStyle(.secondary)
            Toggle("Otevřít doublem", isOn: $draft.config.doubleIn).tint(Theme.action)
        }
        .surface()
    }

    private var cricketGroup: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Cricket").font(.headline)
            Toggle("Bez bodů", isOn: options.cricketNoScore).tint(Theme.action)
            Text(draft.config.settings.cricketNoScore ? "Vyhrává, kdo první zavře 15–20 a bull." : "Zavři všechna čísla a měj aspoň tolik bodů jako soupeři.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .surface()
    }

    private var countUpGroup: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Délka").font(.headline)
            OptionSwitcher(options: roundChoices.map { ($0, "\($0)") }, selection: draft.config.settings.countUpRounds) { rounds in
                options.wrappedValue.countUpRounds = rounds
            }
            Text("\(draft.config.settings.countUpRounds * 3) šipek na hráče.").font(.caption).foregroundStyle(.secondary)
        }
        .surface()
    }

    private var clockGroup: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Zásah").font(.headline)
            OptionSwitcher(options: ClockStyle.allCases.map { ($0, $0.title) }, selection: draft.config.settings.clockStyle) { style in
                options.wrappedValue.clockStyle = style
            }
            Text("Postupně 1–20 a nakonec bull. U doublů a triplů se bull bere jen jako 50.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .surface()
    }

    private var lengthGroup: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Délka").font(.headline)
            OptionSwitcher(options: MatchFormat.allCases.map { ($0, $0.title) }, selection: draft.config.format) { format in
                withAnimation(motion) {
                    draft.config.apply(format: format, setsShown: draft.config.shownSets, legsShown: draft.config.shownLegs)
                }
            }
            Text("Sety").font(.subheadline.weight(.semibold))
            OptionSwitcher(options: setChoices.map { ($0, "\($0)") }, selection: draft.config.shownSets) { value in
                withAnimation(motion) {
                    draft.config.apply(format: draft.config.format, setsShown: value, legsShown: draft.config.shownLegs)
                }
            }
            Text(draft.config.playsSets ? "Zápas se dělí na sety." : "Jeden set. Hraje se jen na legy.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("Legy").font(.subheadline.weight(.semibold))
            OptionSwitcher(options: legChoices.map { ($0, "\($0)") }, selection: draft.config.shownLegs) { value in
                withAnimation(motion) {
                    draft.config.apply(format: draft.config.format, setsShown: draft.config.shownSets, legsShown: value)
                }
            }
            Text(draft.config.lengthDetail)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .contentTransition(.opacity)
        }
        .surface()
    }

    private var setChoices: [Int] { draft.config.format == .bestOf ? Array(stride(from: 1, through: 11, by: 2)) : Array(1...11) }
    private var legChoices: [Int] { draft.config.format == .bestOf ? Array(stride(from: 1, through: 15, by: 2)) : Array(1...11) }
    private var roundChoices: [Int] {
        var values = [5, 10, 15, 20, 30]
        let current = draft.config.settings.countUpRounds
        if !values.contains(current) { values.append(current); values.sort() }
        return values
    }

    private var openingStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            openingCard("Náhodně", detail: "Los určí, kdo hází první.", symbol: "dice", mode: .random)
            openingCard("Vybrat hráče", detail: "Sám zvolíš, kdo začíná.", symbol: "person.fill", mode: .pick)
            openingCard("Rozhoz na střed", detail: "Každý hodí na střed. Červený bere před zeleným. Stejný střed se hází znovu.", symbol: "smallcircle.filled.circle", mode: .bull)
            if opening == .pick {
                OptionSwitcher(
                    options: draft.seats.indices.map { ($0, seatName($0)) },
                    selection: pickedStarter ?? -1
                ) { index in
                    withAnimation(motion) { pickedStarter = index }
                }
            }
            if opening == .bull, let bullWinner {
                Label("Začíná \(seatName(bullWinner))", systemImage: "flag.checkered")
                    .font(.headline)
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.brand.opacity(0.18), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                Button("Hodit znovu") { showBullOff = true }
                    .font(.subheadline.weight(.semibold))
            }
        }
    }

    private func openingCard(_ title: String, detail: String, symbol: String, mode: Opening) -> some View {
        ChoiceCard(title: title, detail: detail, symbol: symbol, selected: opening == mode) {
            withAnimation(motion) {
                opening = mode
                if mode == .random { pickedStarter = nil }
                if mode == .pick, pickedStarter == nil { pickedStarter = 0 }
                if mode == .bull { showBullOff = true }
            }
        }
    }

    private var flowGroup: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Během hry").font(.headline)
            if draft.config.mode == .x01 && !draft.config.doubleIn {
                Picker("Zápis skóre", selection: options.entry) {
                    ForEach(EntryStyle.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                Text(draft.config.settings.entry == .total ? "Napíšeš součet kola. Při zavření potvrdíš počet šipek." : "Každá šipka se zapíše hned a třetí předá tah.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Label("Zápis po jednotlivých šipkách", systemImage: "scope")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            if draft.seats.contains(where: \.isBot) {
                Picker("Tempo šipek bota", selection: options.botDelay) {
                    Text("Rychlé").tag(0.5)
                    Text("Plynulé").tag(1.5)
                    Text("Klidné").tag(3.0)
                }
                .pickerStyle(.segmented)
            }
            if draft.config.mode == .x01 { Toggle("Nápověda zavření", isOn: options.checkoutHints).tint(Theme.action) }
            Toggle("Nezhasínat displej", isOn: options.keepAwake).tint(Theme.action)
        }
        .surface()
    }

    private func commitScore(_ value: Int) {
        draft.config.startingScore = value
        scoreText = "\(value)"
    }

    private func advance() {
        commitScoreFromField()
        if !isLastStep { setStep(step + 1) }
        else if store.activeMatch != nil { replace = true }
        else { start() }
    }

    private func commitScoreFromField() {
        if let value = Int(scoreText), (GameConfig.minimumScore...GameConfig.maximumScore).contains(value) {
            draft.config.startingScore = value
        }
        scoreText = "\(draft.config.startingScore)"
    }

    private func setStep(_ value: Int) {
        commitScoreFromField()
        withAnimation(motion) { step = value }
    }
    private func seatName(_ i: Int) -> String { i == 0 ? store.profile?.name ?? "Já" : draft.seats[i].isBot ? "Bot \(i) · L\(draft.seats[i].level)" : draft.seats[i].name }
    private func start() {
        guard let profile = store.profile, canContinue else { return }
        var players = [Player(id: profile.id, name: profile.name)]
        for i in draft.seats.indices.dropFirst() {
            let seat = draft.seats[i]
            players.append(Player(name: seat.isBot ? "Bot \(i) · L\(seat.level)" : String(seat.name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(24)), botLevel: seat.isBot ? seat.level : nil))
        }
        if [.aroundClock, .countUp].contains(draft.config.mode) {
            draft.config.legsToWin = 1
            draft.config.setsToWin = 1
        }
        draft.config.startingScore = min(GameConfig.maximumScore, max(GameConfig.minimumScore, draft.config.startingScore))
        let first = openingPlayer(count: players.count)
        draft.starter = opening == .random ? -1 : first
        store.remember(draft)
        if savePreset { store.addPreset(name: presetName, setup: draft); savePreset = false }
        store.activeMatch = Match(config: draft.config, players: players, firstPlayer: first)
        store.feedback(); live = true
    }

    private func openingPlayer(count: Int) -> Int {
        guard count > 1 else { return 0 }
        switch opening {
        case .pick: return min(max(0, pickedStarter ?? 0), count - 1)
        case .bull: return min(max(0, bullWinner ?? 0), count - 1)
        case .random, nil: return Int.random(in: 0..<count)
        }
    }
}
struct ChoiceCard: View {
    var title: String; var detail: String; var symbol: String; var selected: Bool; var action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
                Image(systemName: symbol).font(.title2).frame(width: 46, height: 52).foregroundStyle(Theme.action)
                VStack(alignment: .leading, spacing: 7) { Text(title).font(.title3.bold()); Text(detail).font(.caption).foregroundStyle(.secondary) }
                Spacer(minLength: 0)
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(selected ? Theme.action : .secondary)
                    .contentTransition(.symbolEffect(.replace))
            }.foregroundStyle(.primary).padding(18).frame(maxWidth: .infinity, alignment: .leading).background(selected ? Theme.action.opacity(0.09) : Theme.card, in: RoundedRectangle(cornerRadius: 22)).overlay(RoundedRectangle(cornerRadius: 22).stroke(selected ? Theme.action : Theme.stroke, lineWidth: selected ? 1.5 : 1))
        }.buttonStyle(.plain).accessibilityAddTraits(selected ? .isSelected : [])
    }
}
struct ChoicePill: View {
    var title: String; var selected: Bool; var action: () -> Void
    var body: some View {
        Button(action: action) { Text(title).font(.system(.subheadline, design: .rounded, weight: .bold)).frame(maxWidth: .infinity).frame(minHeight: 44).foregroundStyle(selected ? Theme.onAccent : .primary).background(selected ? Theme.accentFill : Theme.background, in: RoundedRectangle(cornerRadius: 12, style: .continuous)) }.buttonStyle(.plain).accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// Stejný přepínač pro skóre, zavření, formát, sety i legy.
struct OptionSwitcher<ID: Hashable>: View {
    var options: [(id: ID, title: String)]
    var selection: ID
    var onSelect: (ID) -> Void

    var body: some View {
        let compact = options.count <= 3
        Group {
            if compact {
                HStack(spacing: 4) { chips }
            } else {
                ScrollViewReader { proxy in
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 4) { chips }
                    }
                    .onAppear { proxy.scrollTo(selection, anchor: .center) }
                    .onChange(of: selection) { _, id in
                        withAnimation(.smooth(duration: 0.28)) { proxy.scrollTo(id, anchor: .center) }
                    }
                }
            }
        }
        .padding(4)
        .background(Color.primary.opacity(0.06), in: Capsule())
        .sensoryFeedback(.selection, trigger: selection)
    }

    @ViewBuilder private var chips: some View {
        ForEach(options, id: \.id) { option in
            let selected = option.id == selection
            Button { onSelect(option.id) } label: {
                Text(option.title)
                    .font(.subheadline.weight(.bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .padding(.horizontal, 12)
                    .frame(maxWidth: options.count <= 3 ? .infinity : nil)
                    .frame(minHeight: 40)
                    .foregroundStyle(selected ? .black : .primary)
                    .background(selected ? Theme.brand : Color.clear, in: Capsule())
            }
            .buttonStyle(.plain)
            .id(option.id)
            .accessibilityAddTraits(selected ? .isSelected : [])
        }
    }
}

struct SetupAccessoryButton: View {
    @EnvironmentObject private var chrome: MatchSetupChrome
    @Environment(\.tabViewBottomAccessoryPlacement) private var placement

    var body: some View {
        Button {
            guard chrome.enabled else { return }
            chrome.token += 1
        } label: {
            Text(chrome.title ?? "Pokračovat")
                .font(.headline.weight(.semibold))
                .foregroundStyle(.black)
                .lineLimit(1)
                .frame(maxWidth: placement == .inline ? nil : .infinity)
                .padding(.vertical, placement == .inline ? 0 : 4)
        }
        .buttonStyle(.glassProminent)
        .tint(Theme.brand)
        .disabled(!chrome.enabled)
    }
}

private struct BullShot: Identifiable {
    let id = UUID()
    let player: Int
    let dart: Dart
}

/// Rozhoz na střed. Červený střed je výš než zelený. Stejný výsledek se hází znovu v opačném pořadí.
private struct BullOffView: View {
    var names: [String]
    var bots: [Int?]
    var onFinish: (Int) -> Void
    var onCancel: () -> Void

    @State private var order: [Int]
    @State private var shots: [BullShot] = []
    @State private var winner: Int?
    @State private var note: String?

    init(names: [String], bots: [Int?], onFinish: @escaping (Int) -> Void, onCancel: @escaping () -> Void) {
        self.names = names
        self.bots = bots
        self.onFinish = onFinish
        self.onCancel = onCancel
        _order = State(initialValue: Array(names.indices))
    }

    private var pending: [Int] {
        let done = Set(shots.map(\.player))
        return order.filter { !done.contains($0) }
    }
    private var current: Int? { winner == nil ? pending.first : nil }

    private var barTitle: String {
        if let winner { return "Začíná \(name(winner))" }
        if let current { return "Hází \(name(current))" }
        return "Rozhoz na střed"
    }

    private var barSubtitle: String {
        note ?? "Přímka je v procentech poloměru. Červený bere před zeleným."
    }

    var body: some View {
        NavigationStack {
            TouchDartboard(marks: shots.map(\.dart), interactive: humanTurn) { dart in
                guard let current, humanTurn else { return }
                record(dart, player: current)
            }
            .overlay { measureLines }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.black.ignoresSafeArea())
            .navigationTitle(barTitle)
            .navigationSubtitle(barSubtitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Zavřít", action: onCancel)
                }
                ToolbarItem(placement: .bottomBar) {
                    Button("Znovu", action: reset)
                        .buttonStyle(.glass)
                }
                ToolbarSpacer(.flexible, placement: .bottomBar)
                ToolbarItem(placement: .bottomBar) {
                    Button("Hrát") { if let winner { onFinish(winner) } }
                        .buttonStyle(.glassProminent)
                        .tint(Theme.brand)
                        .disabled(winner == nil)
                }
            }
            .toolbarColorScheme(.dark, for: .navigationBar)
        }
        .preferredColorScheme(.dark)
        .task(id: current) {
            guard let current, bots.indices.contains(current), let level = bots[current], winner == nil else { return }
            try? await Task.sleep(nanoseconds: 700_000_000)
            guard !Task.isCancelled, self.current == current, winner == nil else { return }
            record(botDart(level: level), player: current)
        }
    }

    /// Stejný střed a poloměr jako `TouchDartboard`, aby přímka seděla na zásah.
    private var measureLines: some View {
        GeometryReader { geo in
            let radius = min(geo.size.width, geo.size.height) * 0.43
            let center = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)
            ZStack {
                Canvas { context, _ in
                    for shot in shots {
                        guard let end = point(for: shot.dart, center: center, radius: radius) else { continue }
                        var path = Path()
                        path.move(to: center)
                        path.addLine(to: end)
                        context.stroke(path, with: .color(.white), style: StrokeStyle(lineWidth: 2, lineCap: .round))
                    }
                }
                ForEach(shots) { shot in
                    if let end = point(for: shot.dart, center: center, radius: radius) {
                        Text(measureText(shot.dart))
                            .font(.caption.weight(.bold))
                            .monospacedDigit()
                            .foregroundStyle(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(.black.opacity(0.78), in: Capsule())
                            .position(labelPosition(from: center, to: end))
                            .accessibilityLabel("\(name(shot.player)), \(measureText(shot.dart))")
                    }
                }
            }
            .allowsHitTesting(false)
        }
    }

    private func point(for dart: Dart, center: CGPoint, radius: CGFloat) -> CGPoint? {
        guard let x = dart.x, let y = dart.y, x.isFinite, y.isFinite else { return nil }
        return CGPoint(x: center.x + x * radius, y: center.y + y * radius)
    }

    private func labelPosition(from center: CGPoint, to end: CGPoint) -> CGPoint {
        let dx = end.x - center.x
        let dy = end.y - center.y
        let length = max(hypot(dx, dy), 1)
        let mid = CGPoint(x: (center.x + end.x) / 2, y: (center.y + end.y) / 2)
        let along = min(18, length * 0.35)
        return CGPoint(x: mid.x - dy / length * along, y: mid.y + dx / length * along)
    }

    private func reset() {
        order = Array(names.indices)
        shots = []
        winner = nil
        note = nil
    }

    private var humanTurn: Bool {
        guard let current, bots.indices.contains(current) else { return false }
        return bots[current] == nil && winner == nil
    }

    private func name(_ player: Int) -> String {
        names.indices.contains(player) ? names[player] : "Hráč"
    }

    private func measureText(_ dart: Dart) -> String {
        if dart.segment == 25 { return dart.multiplier == 2 ? "červený střed" : "zelený střed" }
        guard let x = dart.x, let y = dart.y, hypot(x, y) <= 1 else { return "mimo terč" }
        return "\(rank(dart) - 100) % poloměru"
    }

    private func record(_ dart: Dart, player: Int) {
        guard winner == nil, current == player else { return }
        shots.append(BullShot(player: player, dart: dart))
        resolveIfComplete()
    }

    private func resolveIfComplete() {
        guard winner == nil, pending.isEmpty, !order.isEmpty else { return }
        let scored = order.compactMap { player -> (player: Int, rank: Int)? in
            guard let shot = shots.last(where: { $0.player == player }) else { return nil }
            return (player, rank(shot.dart))
        }
        guard let best = scored.map(\.rank).min() else { return }
        let leaders = order.filter { player in scored.first { $0.player == player }?.rank == best }
        if leaders.count == 1 {
            winner = leaders[0]
        } else {
            note = replayNote(best: best, count: leaders.count)
            order = Array(leaders.reversed())
            shots = []
        }
    }

    private func replayNote(best: Int, count: Int) -> String {
        let again = "Hází se znovu, opačné pořadí."
        if best == 0 { return count == 2 ? "Oba červený střed. \(again)" : "Stejný červený střed. \(again)" }
        if best == 1 { return count == 2 ? "Oba zelený střed. \(again)" : "Stejný zelený střed. \(again)" }
        return "Stejná vzdálenost. \(again)"
    }

    /// Nižší číslo vyhrává. Červený střed je výš než zelený, oba jsou výš než zbytek terče.
    private func rank(_ dart: Dart) -> Int {
        if dart.segment == 25 { return dart.multiplier == 2 ? 0 : 1 }
        guard let x = dart.x, let y = dart.y, x.isFinite, y.isFinite else { return 10_000 }
        let radius = hypot(x, y)
        if radius > 1 { return 9_000 }
        return 100 + Int((radius * 100).rounded())
    }

    private func botDart(level: Int) -> Dart {
        let spread = max(0.05, 0.75 - Double(min(10, max(1, level))) * 0.065)
        let radius = sqrt(Double.random(in: 0...1)) * spread
        let angle = Double.random(in: 0..<(2 * Double.pi))
        return BoardGeometry.hit(x: cos(angle) * radius, y: sin(angle) * radius)
    }
}
