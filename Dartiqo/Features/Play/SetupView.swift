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

private enum Opening: String, Identifiable {
    case random, pick, bull
    var id: String { rawValue }
}

struct SetupView: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dismiss) private var dismiss
    private let onHome: (() -> Void)?
    private let coversLiveBar: Bool
    @State private var draft: SetupDraft
    @State private var step = 0
    @State private var live = false
    @State private var replace = false
    @State private var savePreset = false
    @State private var presetName = "Moje 501"
    @State private var scoreText = "501"
    @State private var scoreExact = false
    @State private var limitCustom = false
    @State private var openRule: RuleKey? = .start
    @State private var friendPicker: FriendPickerTarget?
    @State private var botPicker: BotPickerTarget?
    @State private var ghostPicker: GhostPickerTarget?
    /// Rozbalená karta handicapu (index místa).
    @State private var handicapFocus: Int?
    @FocusState private var focusedGuest: UUID?

    private struct FriendPickerTarget: Identifiable, Equatable {
        var id = UUID()
        /// `nil` = přidat do volných míst, jinak vyměnit toto místo.
        var seatID: UUID?
    }
    private struct BotPickerTarget: Identifiable, Equatable {
        var id: UUID
        /// `nil` = nový bot, jinak úprava existujícího místa.
        var seatID: UUID?
        var level: Int
        var style: BotPlayingStyle
        var adaptive: Bool
    }
    private struct GhostPickerTarget: Identifiable, Equatable {
        var id = UUID()
        /// `true` = přidat ghosta do sestavy, `false` = jen změnit variantu.
        var adding: Bool
        var initialKind: GhostKind?
    }
    private enum RuleKey: Hashable { case start, finish, mode, length, limit, handicap }
    @State private var opening: Opening?
    @State private var modeInfo: GameMode?
    @State private var openingInfo: Opening?
    @State private var pickedStarter: Int?
    @State private var bullWinner: Int?
    @State private var showStarterPicker = false
    @State private var showBullOff = false
    @State private var bullLaunched = false
    @State private var showCoinToss = false
    @State private var coinLaunched = false
    @State private var showH2HAfterToss = false
    @State private var coinWinner: Int?
    @State private var pregameSeries: HeadToHead?
    @State private var openSoloTraining = false
    private let presetScores = [101, 301, 501, 701, 1001]
    private var options: Binding<MatchOptions> { Binding(get: { draft.config.settings }, set: { draft.config.options = $0 }) }
    init(
        mode: GameMode,
        preset: SetupDraft? = nil,
        onHome: (() -> Void)? = nil,
        coversLiveBar: Bool = false,
        startAtOpening: Bool = false
    ) {
        self.onHome = onHome
        self.coversLiveBar = coversLiveBar
        let draft = preset ?? SetupDraft(mode: mode)
        _draft = State(initialValue: draft)
        // Rychlá hra přeskočí sestavení a rovnou nabídne, kdo hází první.
        if startAtOpening {
            _step = State(initialValue: draft.seats.count > 1 ? 4 : 3)
        }
    }
    private var canContinue: Bool {
        guard !draft.seats.isEmpty else { return false }
        if draft.seats.contains(where: \.ghostSeat) {
            guard draft.config.mode == .x01, let kind = draft.ghostKind else { return false }
            return store.ghostOffer(
                kind,
                startingScore: draft.config.startingScore,
                outRule: draft.config.outRule,
                matchID: draft.ghostMatchID
            ) != nil
        }
        return !draft.seats.indices.contains {
            !isMe($0) && !draft.seats[$0].isBot && !draft.seats[$0].ghostSeat
                && draft.seats[$0].name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }
    private var showsOpening: Bool { draft.seats.count > 1 }
    /// Jen já u terče → zápas nemá smysl, jdeme do tréninku.
    private var isSoloTraining: Bool {
        draft.seats.count == 1 && draft.includesMe
            && !draft.seats[0].isBot && !draft.seats[0].ghostSeat
    }
    private var stepCount: Int { showsOpening ? 5 : 4 }
    private var stepTitles: [String] { showsOpening ? ["Hra", "Hráči", "Pravidla", "Souhrn", "Start"] : ["Hra", "Hráči", "Pravidla", "Souhrn"] }
    private var isLastStep: Bool { step >= stepCount - 1 }
    private var advanceTitle: String {
        if isSoloTraining, step >= 1 { return "Trénovat" }
        return isLastStep ? "Hrát" : "Pokračovat"
    }
    private var advanceSymbol: String {
        if isSoloTraining, step >= 1 { return "scope" }
        return isLastStep ? "play.fill" : "arrow.right"
    }
    private var soloTrainingIDs: [String] {
        TrainingCatalog.ids(for: draft.config.mode, startingScore: draft.config.startingScore)
    }
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
    /// Plynulé otevírání bannerů — bez pružiny, která seká layout.
    private var sectionMotion: Animation { reduceMotion ? .easeInOut(duration: 0.18) : .smooth(duration: 0.42) }
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
                        else if step == 3 { summaryStep }
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
            .onChange(of: openRule) { _, key in
                guard let key, step == 2 else { return }
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 280_000_000)
                    withAnimation(.smooth(duration: 0.35)) { proxy.scrollTo(key, anchor: .top) }
                }
            }
        }
        .animation(motion, value: step)
        .safeAreaInset(edge: .bottom, spacing: 0) { setupBar }
        .toolbar(.hidden, for: .tabBar)
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
                    .accessibilityLabel("Předchozí krok")
                }
            }
            if let match = store.activeMatch {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        store.tapHaptic()
                        live = true
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: match.finished ? "flag.checkered" : "play.fill")
                            Text(liveMark(match))
                                .monospacedDigit()
                        }
                        .font(AppFont.caption(14, weight: .bold))
                    }
                    .tint(Theme.brand)
                    .accessibilityLabel(resumeAccessibility(match))
                }
            }
        }
        .sensoryFeedback(.selection, trigger: step)
        .onAppear {
            scoreText = "\(draft.config.startingScore)"
            if !presetScores.contains(draft.config.startingScore) { scoreExact = true }
            syncLiveBar()
        }
        .onDisappear {
            if coversLiveBar { store.localSetupCoversBar = false }
        }
        .onChange(of: store.section) { _, _ in syncLiveBar() }
        .onChange(of: showsOpening) { _, shown in
            if !shown, step > 3 { setStep(3) }
        }
        .onChange(of: showBullOff) { _, shown in
            if !shown { bullLaunched = false }
        }
        .confirmationDialog("Máš rozehraný zápas", isPresented: $replace, titleVisibility: .visible) {
            Button("Pokračovat v rozehraném") { live = true }
            Button("Zahodit rozehraný a spustit nový", role: .destructive) { start() }
            Button("Zrušit", role: .cancel) {}
        }
        .fullScreenCover(isPresented: $live) {
            NavigationStack { MatchView() }
                .environmentObject(store)
        }
        .navigationDestination(isPresented: $openSoloTraining) {
            TrainingHomeView(gameIDs: soloTrainingIDs, onHome: onHome)
                .environmentObject(store)
        }
        .sheet(item: $modeInfo) { mode in
            ModeInfoSheet(mode: mode) {
                modeInfo = nil
                withAnimation(motion) { draft.config.mode = mode }
            }
        }
        .sheet(item: $openingInfo) { mode in
            OpeningInfoSheet(mode: mode) {
                openingInfo = nil
                applyOpening(mode)
            }
        }
        .onChange(of: store.homeGeneration) { _, _ in
            live = false
            showStarterPicker = false
            showBullOff = false
            showCoinToss = false
            showH2HAfterToss = false
            pregameSeries = nil
        }
        .onChange(of: draft.seats.count) { _, count in
            if let picked = pickedStarter, !draft.seats.indices.contains(picked) || count < 2 {
                pickedStarter = nil
            }
            if count < 2 { showStarterPicker = false }
        }
        .fullScreenCover(isPresented: $showCoinToss) {
            ZStack {
                if coinLaunched {
                    NavigationStack { MatchView() }
                        .transition(.opacity)
                } else if showH2HAfterToss, let series = pregameSeries {
                    HeadToHeadPregameView(
                        series: series,
                        myName: store.profile?.name ?? "Já",
                        myPhoto: store.profile?.photoJPEG,
                        theirPhoto: pregameOpponentPhoto(series),
                        onContinue: { finishAfterToss() },
                        onCancel: {
                            showCoinToss = false
                            showH2HAfterToss = false
                            coinLaunched = false
                            pregameSeries = nil
                        }
                    )
                    .transition(.opacity)
                } else {
                    CoinTossView(players: coinTossPlayers) { winner in
                        coinWinner = winner
                        opening = .random
                        commitScoreFromField()
                        ensureFriendIDs()
                        if let series = makePregameSeries() {
                            pregameSeries = series
                            withAnimation(.easeInOut(duration: 0.3)) { showH2HAfterToss = true }
                        } else {
                            finishAfterToss()
                        }
                    } onCancel: {
                        showCoinToss = false
                        showH2HAfterToss = false
                        coinLaunched = false
                        pregameSeries = nil
                    }
                    .transition(.opacity)
                }
            }
            .environmentObject(store)
            .onAppear {
                coinLaunched = false
                showH2HAfterToss = false
                pregameSeries = nil
            }
        }
        .fullScreenCover(isPresented: $showBullOff) {
            ZStack {
                if bullLaunched {
                    NavigationStack { MatchView() }
                        .transition(.opacity)
                } else {
                    BullOffView(names: draft.seats.indices.map(seatName), bots: draft.seats.indices.map { index in
                        isMe(index) ? nil : (draft.seats[index].isBot ? draft.seats[index].level : nil)
                    }) { winner in
                        bullWinner = winner
                        opening = .bull
                        commitScoreFromField()
                        if let active = store.activeMatch, !active.finished {
                            showBullOff = false
                            Task { @MainActor in
                                try? await Task.sleep(nanoseconds: 450_000_000)
                                replace = true
                            }
                        } else if makeMatch() {
                            withAnimation(.easeInOut(duration: 0.35)) { bullLaunched = true }
                        } else {
                            showBullOff = false
                        }
                    } onCancel: {
                        showBullOff = false
                        if bullWinner == nil { opening = nil }
                    }
                    .transition(.opacity)
                }
            }
            .environmentObject(store)
        }
        .fullScreenCover(isPresented: $showStarterPicker) {
            StarterPickerView(
                players: starterPicks,
                initial: pickedStarter
            ) { winner in
                withAnimation(motion) {
                    pickedStarter = winner
                    opening = .pick
                }
                showStarterPicker = false
            } onCancel: {
                showStarterPicker = false
                if pickedStarter == nil { opening = nil }
            }
        }
    }

    private var headline: String {
        switch step {
        case 0: return "Jaká hra?"
        case 1: return "Kdo hraje?"
        case 2: return "Jak se hraje?"
        case 3: return "Všechno sedí?"
        default: return "Kdo začíná?"
        }
    }

    private var subtitle: String {
        switch step {
        case 0: return "Vyber režim. Ostatní doladíš v dalším kroku."
        case 1:
            return isSoloTraining
                ? "Sám u terče = trénink. Přidej soupeře, pokud chceš zápas."
                : "Sestav, kdo stojí u terče. Až čtyři místa."
        case 2: return "Klepni na sekci a nastav ji. Ostatní zůstanou sbalené."
        case 3: return "Kdo hraje a podle jakých pravidel. Klepnutím na řádek ho změníš."
        default: return "Rozhodni, kdo hází první leg."
        }
    }

    private var canAdvance: Bool { isLastStep ? canPlay : (step == 0 || canContinue) }

    private func liveMark(_ match: Match) -> String {
        if match.finished { return "Výsledek" }
        let state = match.currentState
        switch match.config.mode {
        case .x01:
            return "\(state.remaining)"
        case .cricket, .countUp:
            return "\(state.points)"
        case .aroundClock:
            return state.clockTarget > 20 ? "Bull" : "\(state.clockTarget)"
        }
    }

    private func syncLiveBar() {
        guard coversLiveBar else { return }
        store.localSetupCoversBar = store.section == .home
    }

    private func resumeAccessibility(_ match: Match) -> String {
        if match.finished { return "Zápas skončil. Zobrazit výsledek." }
        return "Rozehraný zápas. Skóre \(liveMark(match)). Pokračovat ve hře."
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
                        Text(advanceTitle)
                            .font(.headline)
                            .contentTransition(.opacity)
                        Image(systemName: advanceSymbol)
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
                .animation(motion, value: canAdvance)
                .animation(motion, value: isSoloTraining)
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 6)
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
                ChoiceCard(title: mode.shortTitle, detail: mode.detail, symbol: mode.symbol, selected: draft.config.mode == mode, action: {
                    withAnimation(motion) {
                        draft.config.mode = mode
                        if mode != .x01 { replaceGhostWithBotIfNeeded() }
                    }
                }, info: { modeInfo = mode })
            }
        }
    }

    private func replaceGhostWithBotIfNeeded() {
        guard let index = draft.seats.firstIndex(where: \.ghostSeat) else { return }
        draft.seats[index] = SeatDraft(name: "Bot", isBot: true)
        draft.ghostKind = nil
        draft.ghostMatchID = nil
        draft.starter = 0
    }

    private var canAddSeat: Bool {
        draft.seats.count < 4 && !draft.seats.contains(where: \.ghostSeat)
    }

    private func openBotPicker(seatID: UUID) {
        guard let seat = draft.seats.first(where: { $0.id == seatID }), seat.isBot else { return }
        botPicker = BotPickerTarget(id: seat.id, seatID: seat.id, level: seat.level, style: seat.botStyle ?? .balanced, adaptive: seat.adaptiveBot == true)
    }

    private func confirmBot(_ choice: BotChoice, target: BotPickerTarget) {
        withAnimation(motion) {
            if let seatID = target.seatID, let index = draft.seats.firstIndex(where: { $0.id == seatID }) {
                draft.seats[index].level = choice.level
                draft.seats[index].isBot = true
                draft.seats[index].botStyle = choice.style
                draft.seats[index].adaptiveBot = choice.adaptive ? true : nil
            } else if draft.seats.count < 4 {
                draft.seats.append(SeatDraft(name: "Bot", isBot: true, level: choice.level, botStyle: choice.style, adaptiveBot: choice.adaptive))
                draft.starter = 0
            }
        }
    }

    private func setPlaysMyself(_ on: Bool) {
        guard on != draft.includesMe else { return }
        hideKeyboard()
        withAnimation(motion) {
            if on {
                guard draft.seats.count < 4 else { return }
                draft.seats.insert(SeatDraft(name: "Já"), at: 0)
                draft.withoutMe = nil
            } else {
                if !draft.seats.isEmpty { draft.seats.removeFirst() }
                draft.withoutMe = true
            }
            draft.starter = 0
        }
    }

    private var rosterStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("U terče")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(draft.seats.count)/4")
                    .font(.caption.weight(.bold).monospacedDigit())
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.primary.opacity(0.08), in: Capsule())
            }

            VStack(spacing: 10) {
                ForEach(draft.seats.indices, id: \.self) { index in
                    seatRow(index)
                }
            }

            if canAddSeat {
                HStack(spacing: 8) {
                    addChip("Kamarád", icon: "person.fill") {
                        openFriendPicker()
                    }
                    addChip("Bot", icon: "cpu") { addBot() }
                    if draft.config.mode == .x01 {
                        addChip("Ghost", icon: "person.fill.viewfinder") { openGhostPicker(adding: true) }
                    }
                }
            }

            scoreOnlyCard
        }
        .sensoryFeedback(.selection, trigger: draft.seats.count)
        .sheet(item: $friendPicker) { target in
            FriendPickerSheet(
                taken: takenFriends(excluding: target.seatID),
                slots: target.seatID == nil ? friendPickerSlots : 1
            ) { picked in
                applyPickedFriends(picked, replacing: target.seatID)
            }
            .environmentObject(store)
        }
        .sheet(item: $botPicker) { target in
            BotPickerSheet(
                initialLevel: target.level,
                title: target.seatID == nil ? "Přidat bota" : "Změnit bota",
                confirmTitle: target.seatID == nil ? "Přidat bota" : "Potvrdit",
                adaptiveEnabled: store.data.adaptiveAI != false,
                suggestedLevel: store.profile.map { AdaptiveBotEngine.recommendedLevel(matches: store.matches, playerID: $0.id) } ?? AdaptiveBotEngine.fallbackLevel,
                initialStyle: target.style,
                initialAdaptive: target.adaptive
            ) { choice in
                confirmBot(choice, target: target)
            }
        }
        .sheet(item: $ghostPicker) { target in
            GhostPickerSheet(
                startingScore: draft.config.startingScore,
                outRule: draft.config.outRule,
                initialKind: target.initialKind,
                initialMatchID: draft.ghostMatchID,
                title: target.adding ? "Přidat ghosta" : "Změnit ghosta",
                confirmTitle: target.adding ? "Přidat ghosta" : "Potvrdit"
            ) { selection in
                confirmGhost(selection, adding: target.adding)
            }
            .environmentObject(store)
        }
    }

    @ViewBuilder
    private func seatRow(_ index: Int) -> some View {
        if isMe(index) {
            meCard
        } else if draft.seats[index].ghostSeat {
            ghostSeatCard(index)
        } else if draft.seats[index].isBot {
            botEditor(index)
        } else {
            friendCard(index)
        }
    }

    private func openGhostPicker(adding: Bool) {
        hideKeyboard()
        ghostPicker = GhostPickerTarget(
            adding: adding,
            initialKind: draft.ghostKind
        )
    }

    private func confirmGhost(_ selection: GhostSelection, adding: Bool) {
        withAnimation(motion) {
            if adding || !draft.seats.contains(where: \.ghostSeat) {
                if draft.includesMe {
                    draft.seats = [SeatDraft(name: "Já"), SeatDraft(name: "Ghost", isGhost: true)]
                } else {
                    draft.seats = [SeatDraft(name: "Ghost", isGhost: true)]
                }
            }
            draft.ghostKind = selection.kind
            draft.ghostMatchID = selection.kind == .pickMatch ? selection.matchID : nil
            draft.starter = 0
        }
    }

    private func botEditor(_ index: Int) -> some View {
        let resolved = resolvedBot(draft.seats[index])
        let info = BotLevel.get(resolved.level)
        return HStack(spacing: 4) {
            Button { openBotPicker(seatID: draft.seats[index].id) } label: {
                HStack(spacing: 12) {
                    BotPortrait(level: resolved.level, size: 64, selected: false)
                        .id(info.photo)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(botPersona(index))
                            .font(.headline)
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        Text(botSubtitle(index))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Theme.action)
                            .contentTransition(.opacity)
                        Text("Průměr \(info.averageText) · \(botStyleTitle(index))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)
                    }
                    Spacer(minLength: 4)
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.tertiary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(botPersona(index)), úroveň \(resolved.level)")
            .accessibilityHint("Otevře výběr bota")
            removeButton(index)
        }
        .padding(.leading, 12)
        .padding(.trailing, 6)
        .padding(.vertical, 12)
        .playerCard(seatColor(index))
        .sensoryFeedback(.selection, trigger: resolved.level)
    }

    private var friendPickerSlots: Int {
        max(1, min(4, 4 - draft.seats.count))
    }

    private func openFriendPicker(replacing seatID: UUID? = nil) {
        hideKeyboard()
        friendPicker = FriendPickerTarget(seatID: seatID)
    }

    private func takenFriends(excluding seatID: UUID?) -> Set<UUID> {
        var ids = Set(draft.seats.compactMap(\.friendID))
        if let seatID, let current = draft.seats.first(where: { $0.id == seatID })?.friendID {
            ids.remove(current)
        }
        if let me = store.profile?.id { ids.insert(me) }
        return ids
    }

    private func applyPickedFriends(_ picked: [PickedFriend], replacing seatID: UUID? = nil) {
        guard !picked.isEmpty else { return }
        hideKeyboard()
        withAnimation(motion) {
            if let seatID,
               let index = draft.seats.firstIndex(where: { $0.id == seatID }),
               let friend = picked.first {
                draft.seats[index].name = friend.name
                draft.seats[index].friendID = friend.id
                draft.seats[index].isBot = false
                draft.seats[index].isGhost = nil
                return
            }
            var queue = picked
            let empty = draft.seats.indices.filter { index in
                !isMe(index) && !draft.seats[index].isBot && !draft.seats[index].ghostSeat
                    && draft.seats[index].friendID == nil
                    && draft.seats[index].name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }
            for index in empty {
                guard !queue.isEmpty else { break }
                let friend = queue.removeFirst()
                draft.seats[index] = SeatDraft(name: friend.name, friendID: friend.id)
            }
            for friend in queue where draft.seats.count < 4 && !draft.seats.contains(where: \.ghostSeat) {
                draft.seats.append(SeatDraft(name: friend.name, friendID: friend.id))
            }
            draft.starter = 0
        }
    }

    private func addChip(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.body.weight(.semibold))
                Text(title)
                    .font(.caption.weight(.bold))
            }
            .foregroundStyle(Theme.action)
            .frame(maxWidth: .infinity, minHeight: 64)
            .background(Theme.action.opacity(0.1), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Přidat \(title.lowercased())")
    }

    private func ghostSeatCard(_ index: Int) -> some View {
        let offer = draft.ghostKind.flatMap {
            store.ghostOffer(
                $0,
                startingScore: draft.config.startingScore,
                outRule: draft.config.outRule,
                matchID: draft.ghostMatchID
            )
        }
        return HStack(spacing: 4) {
            Button { openGhostPicker(adding: false) } label: {
                HStack(spacing: 12) {
                    ZStack {
                        if let photo = store.profile?.photoJPEG {
                            Avatar(name: store.profile?.name ?? "Ghost", size: 64, photo: photo)
                                .opacity(0.9)
                        } else {
                            Image(systemName: "person.fill.viewfinder")
                                .font(.title2.weight(.semibold))
                                .foregroundStyle(Theme.action)
                                .frame(width: 64, height: 64)
                                .background(Theme.action.opacity(0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }
                    }
                    .playerRing(seatColor(index))
                    VStack(alignment: .leading, spacing: 4) {
                        Text(offer?.displayName ?? "Ghost")
                            .font(.headline)
                            .lineLimit(1)
                        Text(offer.map { $0.kind.title } ?? "Vyber variantu")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Theme.action)
                        Text(
                            offer.map { item in
                                if let note = item.styleNote, !note.isEmpty {
                                    return "\(note) · klepni pro změnu"
                                }
                                return "Průměr \(item.averageText) · klepni pro změnu"
                            } ?? "Klepni a zvol ghosta"
                        )
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)
                    }
                    Spacer(minLength: 4)
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.tertiary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(offer.map { "Ghost, \($0.kind.title), průměr \($0.averageText)" } ?? "Ghost")
            .accessibilityHint("Otevře výběr ghosta")
            removeButton(index)
        }
        .padding(.leading, 12)
        .padding(.trailing, 6)
        .padding(.vertical, 12)
        .playerCard(seatColor(index))
    }

    private var scoreOnlyCard: some View {
        let scoring = !draft.includesMe
        let locked = scoring && draft.seats.count >= 4
        return Toggle(isOn: Binding(
            get: { scoring },
            set: { setPlaysMyself(!$0) }
        )) {
            HStack(spacing: 12) {
                Image(systemName: scoring ? "pencil.and.list.clipboard" : "person.slash")
                    .font(.body.weight(.bold))
                    .foregroundStyle(scoring ? Theme.onAccent : .secondary)
                    .frame(width: 40, height: 40)
                    .background(
                        scoring ? Theme.accentFill : Color.primary.opacity(0.08),
                        in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                    )
                VStack(alignment: .leading, spacing: 2) {
                    Text("Nehraju, jen zapisuju")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text(locked
                         ? "Sestava je plná, nejdřív někoho odeber"
                         : scoring ? "Nejsi mezi hráči, jen zapisuješ skóre" : "Jsi v sestavě a statistiky se ukládají")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .tint(Theme.accentFill)
        .disabled(locked)
        .padding(.leading, 12)
        .padding(.trailing, 14)
        .padding(.vertical, 12)
        .background(scoring ? Theme.action.opacity(0.08) : Theme.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(scoring ? Theme.action.opacity(0.7) : Theme.stroke, lineWidth: scoring ? 1.5 : 1)
        )
        .animation(motion, value: scoring)
        .accessibilityHint(scoring ? "Vypni, pokud chceš hrát" : "Zapni, pokud jen zapisuješ")
    }

    private var meCard: some View {
        HStack(spacing: 14) {
            Avatar(name: store.profile?.name ?? "Já", size: 48, photo: store.profile?.photoJPEG)
                .playerRing(seatColor(0))
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(store.profile?.name ?? "Já").font(.headline).lineLimit(1)
                    Text("TY")
                        .font(.caption2.weight(.heavy))
                        .foregroundStyle(Theme.onAccent)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Theme.accentFill, in: Capsule())
                }
                Text("Hraješ · statistiky se ukládají")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
        }
        .padding(.leading, 14)
        .padding(.trailing, 14)
        .padding(.vertical, 12)
        .playerCard(seatColor(0))
    }

    /// Barva místa v sestavě. Sólo hra barvy nepotřebuje.
    private func seatColor(_ index: Int) -> Color? {
        draft.seats.count > 1 ? Theme.playerColor(index) : nil
    }

    private func botPersona(_ index: Int) -> String {
        let seat = draft.seats[index]
        let level = resolvedBot(seat).level
        let persona = BotLevel.get(level).persona
        let same = draft.seats[..<index].filter { $0.isBot && resolvedBot($0).level == level }.count
        return same == 0 ? persona : "\(persona) \(same + 1)"
    }

    private func botSubtitle(_ index: Int) -> String {
        let seat = draft.seats[index]
        let resolved = resolvedBot(seat)
        let info = BotLevel.get(resolved.level)
        if resolved.adaptive { return "Adaptive · Lv \(resolved.level) · \(info.name)" }
        return "Lv \(resolved.level) · \(info.name)"
    }

    private func botStyleTitle(_ index: Int) -> String {
        (draft.seats[index].botStyle ?? .balanced).title
    }

    /// Úroveň, se kterou bot opravdu nastoupí. Adaptive se přepočítá z historie a v zápasu už zůstane.
    private func resolvedBot(_ seat: SeatDraft) -> (level: Int, adaptive: Bool, style: BotPlayingStyle) {
        let style = seat.botStyle ?? .balanced
        let adaptive = seat.adaptiveBot == true && store.data.adaptiveAI != false
        if adaptive, let id = store.profile?.id {
            return (AdaptiveBotEngine.recommendedLevel(matches: store.matches, playerID: id), true, style)
        }
        return (min(BotDifficulty.count, max(1, seat.level)), false, style)
    }

    private func isMe(_ index: Int) -> Bool { draft.includesMe && index == 0 }

    private func addBot() {
        guard draft.seats.count < 4 else { return }
        botPicker = BotPickerTarget(id: UUID(), seatID: nil, level: 3, style: .balanced, adaptive: false)
    }

    private func removeSeat(_ index: Int) {
        guard draft.seats.indices.contains(index), !isMe(index) else { return }
        withAnimation(motion) {
            let wasGhost = draft.seats[index].ghostSeat
            _ = draft.seats.remove(at: index)
            if wasGhost {
                draft.ghostKind = nil
                draft.ghostMatchID = nil
            }
            draft.starter = 0
        }
    }

    private func removeButton(_ index: Int) -> some View {
        Button { removeSeat(index) } label: {
            Image(systemName: "xmark")
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)
                .frame(width: 32, height: 32)
                .background(Color.primary.opacity(0.07), in: Circle())
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Odebrat \(seatName(index))")
    }

    private func friendCard(_ index: Int, allowsRemove: Bool = true) -> some View {
        let seat = draft.seats[index]
        let linked = seat.friendID != nil
        let housemate = store.housemates.first { $0.id == seat.friendID }
        let photo = seat.friendID.flatMap { store.photo(for: $0) }
        let caption = housemate != nil ? "Profil na tomto telefonu" : linked ? "Uložený kamarád" : "Jméno se uloží na příště"
        return HStack(spacing: 4) {
            if linked {
                Button { openFriendPicker(replacing: seat.id) } label: {
                    HStack(spacing: 12) {
                        Avatar(name: seat.name.isEmpty ? "?" : seat.name, size: 44, photo: photo)
                            .playerRing(seatColor(index))
                        VStack(alignment: .leading, spacing: 3) {
                            Text(seat.name).font(.headline).lineLimit(1).foregroundStyle(.primary)
                            Text(caption)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text("Klepni pro změnu")
                                .font(.caption)
                                .foregroundStyle(Theme.action)
                        }
                        Spacer(minLength: 4)
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.tertiary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(seat.name), kamarád")
                .accessibilityHint("Otevře výběr kamaráda")
            } else {
                HStack(spacing: 12) {
                    Avatar(name: seat.name.isEmpty ? "?" : seat.name, size: 44, photo: photo)
                        .playerRing(seatColor(index))
                    VStack(alignment: .leading, spacing: 3) {
                        TextField("Jméno kamaráda", text: $draft.seats[index].name)
                            .font(.headline)
                            .textInputAutocapitalization(.words)
                            .autocorrectionDisabled()
                            .focused($focusedGuest, equals: seat.id)
                            .submitLabel(.done)
                        Label(caption, systemImage: "person")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .labelStyle(.titleAndIcon)
                    }
                    Spacer(minLength: 4)
                }
            }
            if allowsRemove {
                removeButton(index)
            } else if linked {
                Button("Změnit") { openFriendPicker(replacing: seat.id) }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.action)
                    .buttonStyle(.plain)
            }
        }
        .padding(.leading, 14)
        .padding(.trailing, allowsRemove ? 6 : 14)
        .padding(.vertical, 10)
        .playerCard(seatColor(index))
    }

    private var rulesStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            if draft.config.mode == .x01 {
                ruleSection(.start, "Start", icon: "flag.fill", value: "\(draft.config.startingScore) bodů") { scoreGroup }
                ruleSection(.finish, "Zavření a otevření", icon: "checkmark.seal.fill", value: finishSummary) { finishGroup }
            }
            if draft.config.mode == .cricket {
                ruleSection(.mode, "Cricket", icon: "line.3.horizontal.decrease.circle.fill", value: draft.config.settings.cricketNoScore ? "Bez bodů" : "S body") { cricketGroup }
            }
            if draft.config.mode == .countUp {
                ruleSection(.mode, "Délka", icon: "chart.bar.fill", value: "\(draft.config.settings.countUpRounds) kol") { countUpGroup }
            }
            if draft.config.mode == .aroundClock {
                ruleSection(.mode, "Zásah", icon: "clock.fill", value: draft.config.settings.clockStyle.title) { clockGroup }
            }
            if draft.config.mode == .x01 || draft.config.mode == .cricket {
                ruleSection(.length, "Délka zápasu", icon: "trophy.fill", value: draft.config.lengthLine) { lengthGroup }
            }
            if draft.config.mode == .x01 {
                ruleSection(.limit, "Limit šipek", icon: "timer", value: limitSummary) { limitGroup }
            }
            if draft.config.mode == .x01 && draft.seats.count > 1 {
                ruleSection(.handicap, "Handicap", icon: "scalemass.fill", value: handicapSummary) { handicapGroup }
            }
        }
    }

    // MARK: Souhrn

    private var summaryStep: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 10) {
                Eyebrow(text: "Hrají")
                VStack(spacing: 0) {
                    ForEach(draft.seats.indices, id: \.self) { index in
                        if index > 0 { Divider().padding(.leading, 64) }
                        summaryPlayer(index)
                    }
                }
                .background(Theme.card, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(Theme.stroke, lineWidth: 1))
            }
            VStack(alignment: .leading, spacing: 10) {
                Eyebrow(text: draft.config.mode.shortTitle)
                VStack(spacing: 0) {
                    let rows = summaryRows
                    ForEach(rows.indices, id: \.self) { index in
                        if index > 0 { Divider().padding(.leading, 64) }
                        summaryRow(rows[index])
                    }
                }
                .background(Theme.card, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(Theme.stroke, lineWidth: 1))
            }
            VStack(alignment: .leading, spacing: 12) {
                Toggle("Uložit jako předvolbu", isOn: $savePreset.animation(motion)).tint(Theme.action)
                if savePreset {
                    TextField("Název předvolby", text: $presetName)
                        .textFieldStyle(.roundedBorder)
                        .transition(.opacity)
                }
            }
            .surface()
        }
    }

    private struct SummaryRow {
        var key: RuleKey
        var icon: String
        var title: String
        var value: String
    }

    private var summaryRows: [SummaryRow] {
        var rows: [SummaryRow] = []
        switch draft.config.mode {
        case .x01:
            rows.append(SummaryRow(key: .start, icon: "flag.fill", title: "Start", value: "\(draft.config.startingScore) bodů"))
            rows.append(SummaryRow(key: .finish, icon: "checkmark.seal.fill", title: "Zavření", value: draft.config.outRule.title))
            rows.append(SummaryRow(key: .finish, icon: "door.left.hand.open", title: "Otevření", value: draft.config.doubleIn ? "Double in" : "Hned"))
        case .cricket:
            rows.append(SummaryRow(key: .mode, icon: "line.3.horizontal.decrease.circle.fill", title: "Cricket", value: draft.config.settings.cricketNoScore ? "Bez bodů" : "S body"))
        case .countUp:
            rows.append(SummaryRow(key: .mode, icon: "chart.bar.fill", title: "Délka", value: "\(draft.config.settings.countUpRounds) kol"))
        case .aroundClock:
            rows.append(SummaryRow(key: .mode, icon: "clock.fill", title: "Zásah", value: draft.config.settings.clockStyle.title))
        }
        if draft.config.mode == .x01 || draft.config.mode == .cricket {
            rows.append(SummaryRow(key: .length, icon: "trophy.fill", title: "Délka zápasu", value: draft.config.lengthLine))
        }
        if draft.config.mode == .x01 {
            rows.append(SummaryRow(key: .limit, icon: "timer", title: "Limit šipek", value: limitSummary))
        }
        if draft.config.mode == .x01 && draft.seats.count > 1 {
            rows.append(SummaryRow(key: .handicap, icon: "scalemass.fill", title: "Handicap", value: seatsHaveHandicap ? handicapSummary : "Vypnuto"))
        }
        return rows
    }

    private func summaryRow(_ row: SummaryRow) -> some View {
        Button { jumpToRule(row.key) } label: {
            HStack(spacing: 14) {
                Image(systemName: row.icon)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.action)
                    .frame(width: 36, height: 36)
                    .background(Theme.action.opacity(0.12), in: Circle())
                Text(row.title).font(.subheadline.weight(.semibold))
                Spacer(minLength: 8)
                Text(row.value)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.trailing)
                    .lineLimit(2)
                Image(systemName: "chevron.right").font(.caption.weight(.bold)).foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint("Upravit")
    }

    private func summaryPlayer(_ index: Int) -> some View {
        let seat = draft.seats[index]
        let custom = draft.config.mode == .x01 && !(seat.handicap?.isEmpty ?? true)
        return Button { setStep(1) } label: {
            HStack(spacing: 14) {
                Avatar(
                    name: seatName(index),
                    bot: seat.isBot && !isMe(index),
                    size: 36,
                    photo: seatPhoto(index),
                    asset: seat.isBot && !isMe(index) ? BotLevel.get(seat.level).photo : nil
                )
                .playerRing(seatColor(index))
                VStack(alignment: .leading, spacing: 2) {
                    Text(seatName(index)).font(.subheadline.weight(.semibold)).lineLimit(1)
                    Text(isMe(index) ? "Ty" : seat.ghostSeat ? (draft.ghostKind?.title ?? "Ghost") : seat.isBot ? "Bot · úroveň \(seat.level)" : "Kamarád")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                if draft.config.mode == .x01 {
                    Text(seatRuleLine(index))
                        .font(.caption.weight(.bold).monospacedDigit())
                        .foregroundStyle(custom ? Theme.onAccent : Color.secondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(custom ? Theme.accentFill : Color.primary.opacity(0.06), in: Capsule())
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint("Upravit hráče")
    }

    private func jumpToRule(_ key: RuleKey) {
        openRule = key
        setStep(2)
    }

    private func ruleSection<Content: View>(_ key: RuleKey, _ title: String, icon: String, value: String, @ViewBuilder content: () -> Content) -> some View {
        let open = openRule == key
        return VStack(alignment: .leading, spacing: 0) {
            Button {
                commitScoreFromField()
                hideKeyboard()
                withAnimation(sectionMotion) { openRule = open ? nil : key }
            } label: {
                HStack(spacing: 14) {
                    Image(systemName: icon)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(open ? Theme.onAccent : Theme.action)
                        .frame(width: 38, height: 38)
                        .background(open ? Theme.accentFill : Theme.action.opacity(0.12), in: Circle())
                        .animation(sectionMotion, value: open)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title).font(.headline)
                        Text(value)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .contentTransition(.opacity)
                    }
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.down")
                        .font(.footnote.weight(.bold))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(open ? 180 : 0))
                        .animation(sectionMotion, value: open)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityValue(value)
            .accessibilityHint(open ? "Sbalí nastavení" : "Rozbalí nastavení")
            .padding(16)
            SmoothExpand(isExpanded: open, animation: sectionMotion) {
                content()
                    .padding(.horizontal, 16)
                    .padding(.bottom, 16)
                    .padding(.top, 2)
            }
        }
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(open ? Theme.action.opacity(0.45) : Theme.stroke, lineWidth: open ? 1.5 : 1)
                .animation(sectionMotion, value: open)
        )
        .shadow(color: .black.opacity(open ? 0.08 : 0), radius: 14, y: 6)
        .animation(sectionMotion, value: open)
        .id(key)
    }

    private func hideKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }

    private var finishSummary: String {
        draft.config.doubleIn ? "\(draft.config.outRule.title) · Double in" : draft.config.outRule.title
    }

    private var scoreGroup: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("\(draft.config.startingScore)")
                .font(.system(size: 56, weight: .bold, design: .rounded))
                .monospacedDigit()
                .contentTransition(.numericText(value: Double(draft.config.startingScore)))
                .frame(maxWidth: .infinity)
                .accessibilityLabel("Start \(draft.config.startingScore) bodů")
            RuleTiles(
                options: presetScores.map { (id: $0, title: "\($0)", detail: nil) } + [(id: -1, title: "Vlastní", detail: nil)],
                selection: usingExactScore ? -1 : draft.config.startingScore,
                columns: 3
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
    }

    private var finishGroup: some View {
        VStack(alignment: .leading, spacing: 18) {
            finishBlock(title: "Zavření") {
                RuleTiles(
                    options: OutRule.allCases.map { (id: $0, title: $0.shortTitle, detail: outHint($0)) },
                    selection: draft.config.outRule,
                    columns: 3,
                    alignment: .leading,
                    equalHeight: true
                ) { rule in
                    withAnimation(motion) { draft.config.outRule = rule }
                }
            }
            finishBlock(title: "Otevření") {
                RuleTiles(
                    options: [
                        (id: false, title: "Hned", detail: "Každý zásah"),
                        (id: true, title: "Double in", detail: "Až od doublu")
                    ],
                    selection: draft.config.doubleIn,
                    columns: 3,
                    alignment: .leading,
                    equalHeight: true
                ) { value in
                    withAnimation(motion) { draft.config.doubleIn = value }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func finishBlock<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity, alignment: .leading)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func outHint(_ rule: OutRule) -> String {
        switch rule {
        case .double: return "Double nebo bull"
        case .straight: return "Jakýkoli zásah"
        case .master: return "Double i triple"
        }
    }

    private var limitSummary: String {
        guard let limit = draft.config.settings.dartLimit else { return "Bez limitu" }
        return "\(limit) šipek · pak rozhoz"
    }

    private var usingCustomLimit: Bool {
        guard let limit = draft.config.settings.dartLimit else { return false }
        return limitCustom || !MatchOptions.dartLimitChoices.contains(limit)
    }

    private var limitGroup: some View {
        VStack(alignment: .leading, spacing: 12) {
            RuleTiles(
                options: [(id: 0, title: "Vypnuto", detail: nil)]
                    + MatchOptions.dartLimitChoices.map { (id: $0, title: "\($0)", detail: "\($0 / 3) kol") }
                    + [(id: -1, title: "Vlastní", detail: usingCustomLimit ? "\(draft.config.settings.dartLimit ?? 0) šipek" : "kola i šipky")],
                selection: usingCustomLimit ? -1 : draft.config.settings.dartLimit ?? 0,
                columns: 3
            ) { limit in
                withAnimation(motion) {
                    limitCustom = limit == -1
                    if limit == -1 {
                        if draft.config.settings.dartLimit == nil { options.wrappedValue.dartLimit = 45 }
                    } else {
                        options.wrappedValue.dartLimit = limit == 0 ? nil : limit
                    }
                }
            }
            if usingCustomLimit, let limit = draft.config.settings.dartLimit {
                Stepper(value: Binding(
                    get: { limit / 3 },
                    set: { rounds in options.wrappedValue.dartLimit = rounds * 3 }
                ), in: MatchOptions.dartLimitRounds) {
                    VStack(alignment: .leading, spacing: 0) {
                        Text("\(limit / 3) kol")
                            .font(.system(.title2, design: .rounded).weight(.bold))
                            .monospacedDigit()
                            .contentTransition(.numericText(value: Double(limit)))
                        Text("\(limit) šipek na hráče").font(.caption).foregroundStyle(.secondary)
                    }
                }
                .padding(12)
                .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .accessibilityValue("\(limit / 3) kol, \(limit) šipek")
            }
            Text(draft.config.settings.dartLimit.map { "Když leg nikdo nezavře do \($0) šipek na hráče, rozhodne rozhoz na střed. Bližší šipka bere leg." }
                 ?? "Leg se hraje, dokud ho někdo nezavře.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var cricketGroup: some View {
        RuleTiles(
            options: [
                (id: false, title: "S body", detail: "Zavři čísla a měj víc bodů"),
                (id: true, title: "Bez bodů", detail: "Vyhrává, kdo první zavře")
            ],
            selection: draft.config.settings.cricketNoScore,
            columns: 2,
            alignment: .leading
        ) { value in
            withAnimation(motion) { options.wrappedValue.cricketNoScore = value }
        }
    }

    private var countUpGroup: some View {
        VStack(alignment: .leading, spacing: 12) {
            RuleTiles(options: roundChoices.map { (id: $0, title: "\($0)", detail: nil) }, selection: draft.config.settings.countUpRounds, columns: 3) { rounds in
                withAnimation(motion) { options.wrappedValue.countUpRounds = rounds }
            }
            Text("\(draft.config.settings.countUpRounds * 3) šipek na hráče.").font(.caption).foregroundStyle(.secondary)
        }
    }

    private var clockGroup: some View {
        VStack(alignment: .leading, spacing: 12) {
            RuleTiles(options: ClockStyle.allCases.map { (id: $0, title: $0.title, detail: nil) }, selection: draft.config.settings.clockStyle, columns: 3) { style in
                withAnimation(motion) { options.wrappedValue.clockStyle = style }
            }
            Text("Postupně 1–20 a nakonec bull. U doublů a triplů se bull bere jen jako 50.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var lengthGroup: some View {
        let bestOf = draft.config.format == .bestOf
        let stepSize = bestOf ? 2 : 1
        let legLimit = bestOf ? 15 : 11
        return VStack(alignment: .leading, spacing: 16) {
            RuleTiles(
                options: [
                    (id: MatchFormat.firstTo, title: "First to", detail: "Kdo první získá počet"),
                    (id: MatchFormat.bestOf, title: "Best of", detail: "Většina z počtu")
                ],
                selection: draft.config.format,
                columns: 2,
                alignment: .leading
            ) { format in
                withAnimation(motion) {
                    draft.config.apply(format: format, setsShown: draft.config.shownSets, legsShown: draft.config.shownLegs)
                }
            }
            CountStepper(
                title: "Sety",
                value: draft.config.shownSets,
                caption: draft.config.playsSets ? "Zápas se dělí na sety" : "Bez setů, hraje se na legy",
                canDecrease: draft.config.shownSets > 1,
                canIncrease: draft.config.shownSets + stepSize <= 11
            ) { delta in
                withAnimation(motion) {
                    draft.config.apply(format: draft.config.format, setsShown: draft.config.shownSets + delta * stepSize, legsShown: draft.config.shownLegs)
                }
            }
            CountStepper(
                title: draft.config.playsSets ? "Legy v setu" : "Legy",
                value: draft.config.shownLegs,
                caption: bestOf ? "Bere \(draft.config.legsToWin)" : "Na \(draft.config.legsToWin) výher",
                canDecrease: draft.config.shownLegs > 1,
                canIncrease: draft.config.shownLegs + stepSize <= legLimit
            ) { delta in
                withAnimation(motion) {
                    draft.config.apply(format: draft.config.format, setsShown: draft.config.shownSets, legsShown: draft.config.shownLegs + delta * stepSize)
                }
            }
            Text(draft.config.lengthDetail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .contentTransition(.opacity)
        }
    }

    // MARK: Handicap

    private var seatsHaveHandicap: Bool { draft.seats.contains { !($0.handicap?.isEmpty ?? true) } }

    private var handicapSummary: String {
        let count = draft.seats.filter { !($0.handicap?.isEmpty ?? true) }.count
        switch count {
        case 0: return "Vypnuto · všichni stejně"
        case 1: return "1 hráč má výhodu"
        case 2...4: return "\(count) hráči s úpravou"
        default: return "\(count) hráčů s úpravou"
        }
    }

    private var matchBaselineLine: String {
        var parts = ["\(draft.config.startingScore)", draft.config.outRule.shortTitle]
        parts.append(draft.config.doubleIn ? "Double in" : "Hned")
        return parts.joined(separator: " · ")
    }

    private func seatRuleLine(_ index: Int) -> String {
        var parts = ["\(seatStart(index))", seatOut(index).shortTitle]
        if seatDoubleIn(index) { parts.append("Double in") }
        return parts.joined(separator: " · ")
    }

    private func seatStart(_ index: Int) -> Int {
        draft.seats[index].handicap?.startingScore ?? draft.config.startingScore
    }

    private func seatOut(_ index: Int) -> OutRule {
        draft.seats[index].handicap?.outRule ?? draft.config.outRule
    }

    private func seatDoubleIn(_ index: Int) -> Bool {
        draft.seats[index].handicap?.doubleIn ?? draft.config.doubleIn
    }

    private func seatStartDelta(_ index: Int) -> Int {
        seatStart(index) - draft.config.startingScore
    }

    private func handicapBadge(_ index: Int) -> (text: String, accent: Bool) {
        guard !(draft.seats[index].handicap?.isEmpty ?? true) else {
            return ("Stejně", false)
        }
        let delta = seatStartDelta(index)
        if delta < 0 { return ("−\(abs(delta))", true) }
        if delta > 0 { return ("+\(delta)", true) }
        return ("Upraveno", true)
    }

    private func editHandicap(_ index: Int, _ change: (inout Handicap) -> Void) {
        guard draft.seats.indices.contains(index) else { return }
        var handicap = draft.seats[index].handicap ?? Handicap()
        change(&handicap)
        withAnimation(motion) { draft.seats[index].handicap = handicap.isEmpty ? nil : handicap }
    }

    private func clearAllHandicaps() {
        hideKeyboard()
        withAnimation(motion) {
            for index in draft.seats.indices { draft.seats[index].handicap = nil }
            handicapFocus = nil
        }
    }

    private var handicapStartChoices: [(id: Int, title: String)] {
        let base = draft.config.startingScore
        var choices: [(id: Int, title: String)] = [(id: -1, title: "Stejně")]
        for offset in [50, 100, 200] where base - offset >= GameConfig.minimumScore {
            choices.append((id: base - offset, title: "−\(offset)"))
        }
        for score in presetScores where score != base && !choices.contains(where: { $0.id == score }) {
            choices.append((id: score, title: "\(score)"))
        }
        return choices
    }

    private var handicapGroup: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Label("Vyrovnání sil", systemImage: "scalemass.fill")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(Theme.action)
                Text("Slabšímu hráči sniž start nebo zjednoduš zavření. Co necháš na „Stejně“, platí jako základ hry.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 10) {
                Image(systemName: "flag.fill")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Theme.onAccent)
                    .frame(width: 28, height: 28)
                    .background(Theme.accentFill, in: Circle())
                VStack(alignment: .leading, spacing: 2) {
                    Text("Základ hry")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(matchBaselineLine)
                        .font(.subheadline.weight(.bold).monospacedDigit())
                }
                Spacer(minLength: 0)
            }
            .padding(12)
            .background(Theme.brand.opacity(0.12), in: RoundedRectangle(cornerRadius: 16, style: .continuous))

            if draft.seats.count > 1 {
                handicapOverview
            }

            ForEach(draft.seats.indices, id: \.self) { index in
                handicapCard(index)
            }

            Button(action: clearAllHandicaps) {
                Label("Všem stejně jako hra", systemImage: "equal.circle.fill")
                    .font(.subheadline.weight(.bold))
                    .frame(maxWidth: .infinity, minHeight: 48)
            }
            .buttonStyle(.bordered)
            .buttonBorderShape(.capsule)
            .tint(Theme.action)
            .disabled(!seatsHaveHandicap)
            .accessibilityHint("Zruší handicap všech hráčů")
        }
    }

    private var handicapOverview: some View {
        HStack(spacing: 8) {
            ForEach(draft.seats.indices, id: \.self) { index in
                let badge = handicapBadge(index)
                let custom = !(draft.seats[index].handicap?.isEmpty ?? true)
                Button {
                    withAnimation(sectionMotion) {
                        handicapFocus = handicapFocus == index ? nil : index
                    }
                } label: {
                    VStack(spacing: 6) {
                        Avatar(
                            name: seatName(index),
                            bot: draft.seats[index].isBot && !isMe(index),
                            size: 36,
                            photo: seatPhoto(index),
                            asset: draft.seats[index].isBot && !isMe(index) ? BotLevel.get(draft.seats[index].level).photo : nil
                        )
                        .playerRing(seatColor(index))
                        Text(seatName(index))
                            .font(.caption2.weight(.semibold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                        Text("\(seatStart(index))")
                            .font(.system(.title3, design: .rounded).weight(.bold))
                            .monospacedDigit()
                            .foregroundStyle(custom ? Theme.action : .primary)
                            .contentTransition(.numericText(value: Double(seatStart(index))))
                        Text(badge.text)
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(badge.accent ? Theme.onAccent : .secondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(badge.accent ? Theme.accentFill : Color.primary.opacity(0.06), in: Capsule())
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .padding(.horizontal, 4)
                    .background(
                        (handicapFocus == index ? Color.primary.opacity(0.08) : Color.primary.opacity(0.04)),
                        in: RoundedRectangle(cornerRadius: 16, style: .continuous)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(custom ? Theme.action.opacity(0.45) : Color.clear, lineWidth: 1.5)
                    )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(seatName(index)), start \(seatStart(index)), \(badge.text)")
            }
        }
        .sensoryFeedback(.selection, trigger: handicapFocus)
    }

    private func handicapCard(_ index: Int) -> some View {
        let handicap = draft.seats[index].handicap
        let custom = !(handicap?.isEmpty ?? true)
        let open = handicapFocus == index || draft.seats.count == 1
        let start = handicap?.startingScore
        let startSelection: Int = {
            if start == nil { return -1 }
            if handicapStartChoices.contains(where: { $0.id == start }) { return start! }
            return -2
        }()
        let badge = handicapBadge(index)
        return VStack(alignment: .leading, spacing: 0) {
            Button {
                hideKeyboard()
                withAnimation(sectionMotion) {
                    handicapFocus = open && draft.seats.count > 1 ? nil : index
                }
            } label: {
                HStack(spacing: 12) {
                    Avatar(
                        name: seatName(index),
                        bot: draft.seats[index].isBot && !isMe(index),
                        size: 40,
                        photo: seatPhoto(index),
                        asset: draft.seats[index].isBot && !isMe(index) ? BotLevel.get(draft.seats[index].level).photo : nil
                    )
                    .playerRing(seatColor(index))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(seatName(index)).font(.headline).lineLimit(1)
                        Text(custom ? "Hraje jinak než základ hry" : "Stejná pravidla jako hra")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 4)
                    Text(badge.text)
                        .font(.caption.weight(.bold).monospacedDigit())
                        .foregroundStyle(badge.accent ? Theme.onAccent : .secondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(badge.accent ? Theme.accentFill : Color.primary.opacity(0.06), in: Capsule())
                    Image(systemName: "chevron.down")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(open ? 180 : 0))
                        .animation(sectionMotion, value: open)
                        .opacity(draft.seats.count > 1 ? 1 : 0)
                }
                .padding(14)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint(open ? "Sbalí úpravu" : "Upravit handicap")

            SmoothExpand(isExpanded: open, animation: sectionMotion) {
                VStack(alignment: .leading, spacing: 14) {
                    handicapField(
                        title: "Start",
                        hint: seatStartDelta(index) == 0
                            ? "Stejný start jako hra (\(draft.config.startingScore))"
                            : seatStartDelta(index) < 0
                            ? "Výhoda \(abs(seatStartDelta(index))) bodů — míň zbývá do nuly"
                            : "Těžší start o \(seatStartDelta(index)) bodů"
                    ) {
                        OptionSwitcher(options: handicapStartChoices, selection: startSelection) { id in
                            editHandicap(index) { $0.startingScore = id == -1 ? nil : id }
                        }
                        ScoreEntryField(value: start, placeholder: draft.config.startingScore) { value in
                            editHandicap(index) { $0.startingScore = value == draft.config.startingScore ? nil : value }
                        }
                    }

                    handicapField(
                        title: "Zavření",
                        hint: seatOut(index) == draft.config.outRule
                            ? "Stejné zavření jako hra"
                            : "Vlastní: \(seatOut(index).title)"
                    ) {
                        OptionSwitcher(
                            options: [(id: OutRule?.none, title: "Stejně")] + OutRule.allCases.map { (id: OutRule?.some($0), title: $0.shortTitle) },
                            selection: handicap?.outRule
                        ) { rule in
                            editHandicap(index) { $0.outRule = rule == draft.config.outRule ? nil : rule }
                        }
                    }

                    handicapField(
                        title: "Otevření",
                        hint: seatDoubleIn(index) == draft.config.doubleIn
                            ? "Stejné otevření jako hra"
                            : seatDoubleIn(index) ? "Musí trefit double, než začne sčítat" : "Může hned bodovat"
                    ) {
                        OptionSwitcher(
                            options: [
                                (id: Bool?.none, title: "Stejně"),
                                (id: Bool?.some(false), title: "Hned"),
                                (id: Bool?.some(true), title: "Double in")
                            ],
                            selection: handicap?.doubleIn
                        ) { value in
                            editHandicap(index) { $0.doubleIn = value == draft.config.doubleIn ? nil : value }
                        }
                    }

                    if custom {
                        Button {
                            editHandicap(index) { $0 = Handicap() }
                        } label: {
                            Label("Vrátit na základ hry", systemImage: "arrow.uturn.backward")
                                .font(.caption.weight(.semibold))
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(Theme.action)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 14)
            }
        }
        .background(
            (custom ? Theme.action.opacity(0.06) : Color.primary.opacity(0.04)),
            in: RoundedRectangle(cornerRadius: 18, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(custom ? Theme.action.opacity(0.35) : Color.clear, lineWidth: 1)
        )
    }

    private func handicapField<Content: View>(title: String, hint: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)
            content()
            Text(hint)
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
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
            if opening == .pick, let starter = pickedStarter, draft.seats.indices.contains(starter) {
                Label("Začíná \(seatName(starter))", systemImage: "flag.checkered")
                    .font(.headline)
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.brand.opacity(0.18), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                Button("Změnit hráče") { showStarterPicker = true }
                    .font(.subheadline.weight(.semibold))
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

    private func applyOpening(_ mode: Opening) {
        withAnimation(motion) {
            opening = mode
            if mode == .random {
                pickedStarter = nil
                coinWinner = nil
            }
            if mode == .pick { showStarterPicker = true }
            if mode == .bull { showBullOff = true }
        }
    }

    private var starterPicks: [StarterPick] {
        draft.seats.indices.map { index in
            let seat = draft.seats[index]
            let level = seat.isBot ? resolvedBot(seat).level : seat.level
            let detail: String = {
                if isMe(index) { return "Ty" }
                if seat.ghostSeat { return "Ghost" }
                if seat.isBot { return "Bot" }
                return "Hráč"
            }()
            return StarterPick(
                id: index,
                name: seatName(index),
                detail: detail,
                photo: seatPhoto(index),
                asset: seat.isBot && !isMe(index) ? BotLevel.get(level).photo : nil,
                bot: seat.isBot && !isMe(index),
                tint: Theme.playerColor(index)
            )
        }
    }

    private var coinTossPlayers: [CoinTossPlayer] {
        draft.seats.indices.map { index in
            let seat = draft.seats[index]
            let photo = seatPhoto(index)
            let asset: String? = seat.isBot && !isMe(index) ? BotLevel.get(seat.level).photo : nil
            return CoinTossPlayer(
                id: index,
                name: seatName(index),
                photo: photo,
                asset: asset,
                bot: seat.isBot && !isMe(index),
                tint: Theme.playerColor(index)
            )
        }
    }

    private func openingCard(_ title: String, detail: String, symbol: String, mode: Opening) -> some View {
        ChoiceCard(title: title, detail: detail, symbol: symbol, selected: opening == mode, action: {
            applyOpening(mode)
        }, info: { openingInfo = mode })
    }

    private func commitScore(_ value: Int) {
        draft.config.startingScore = value
        scoreText = "\(value)"
    }

    private func advance() {
        commitScoreFromField()
        if isSoloTraining, step >= 1 {
            hideKeyboard()
            openSoloTraining = true
            return
        }
        if !isLastStep {
            setStep(step + 1)
        } else if opening == .random, draft.seats.count > 1 {
            coinLaunched = false
            showCoinToss = true
        } else if store.activeMatch != nil {
            replace = true
        } else {
            start()
        }
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
    /// Fotka místa: ty a ghost berou portrét profilu, kamarád svůj uložený snímek.
    private func seatPhoto(_ index: Int) -> Data? {
        guard draft.seats.indices.contains(index) else { return nil }
        if isMe(index) || draft.seats[index].ghostSeat { return store.profile?.photoJPEG }
        guard let id = draft.seats[index].friendID else { return nil }
        return store.photo(for: id)
    }

    private func seatName(_ i: Int) -> String {
        if isMe(i) { return store.profile?.name ?? "Já" }
        let seat = draft.seats[i]
        if seat.ghostSeat {
            return draft.ghostKind.flatMap {
                store.ghostOffer(
                    $0,
                    startingScore: draft.config.startingScore,
                    outRule: draft.config.outRule,
                    matchID: draft.ghostMatchID
                )?.displayName
            } ?? "Ghost"
        }
        return seat.isBot ? botPersona(i) : seat.name
    }
    private func start() {
        guard makeMatch() else { return }
        live = true
    }

    private func finishAfterToss() {
        if let active = store.activeMatch, !active.finished {
            showCoinToss = false
            showH2HAfterToss = false
            pregameSeries = nil
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 450_000_000)
                replace = true
            }
        } else if makeMatch() {
            withAnimation(.easeInOut(duration: 0.35)) { coinLaunched = true }
        } else {
            showCoinToss = false
            showH2HAfterToss = false
            pregameSeries = nil
        }
    }

    private func ensureFriendIDs() {
        for i in draft.seats.indices where !isMe(i) && !draft.seats[i].isBot && !draft.seats[i].ghostSeat && draft.seats[i].friendID == nil {
            draft.seats[i].friendID = store.addFriend(draft.seats[i].name)?.id
        }
    }

    /// H2H před startem — jen 1v1, kde hraješ ty.
    private func makePregameSeries() -> HeadToHead? {
        guard let me = store.profile?.id,
              draft.seats.count == 2,
              let myIndex = draft.seats.indices.first(where: isMe),
              let other = draft.seats.indices.first(where: { $0 != myIndex })
        else { return nil }
        let seat = draft.seats[other]
        let resolved = seat.isBot ? resolvedBot(seat) : nil
        let key: RivalKey?
        if let resolved {
            key = RivalKey(kind: .bot(resolved.level))
        } else {
            key = RivalKey.from(seat: seat, ghostKind: draft.ghostKind)
        }
        guard let key else { return nil }
        let name = seatName(other)
        if let series = HeadToHead.series(from: store.matches, me: me, key: key) {
            return series
        }
        return .empty(
            key: key,
            name: name,
            botLevel: resolved?.level ?? (seat.isBot ? seat.level : nil),
            isGhost: seat.ghostSeat
        )
    }

    private func pregameOpponentPhoto(_ series: HeadToHead) -> Data? {
        guard case .person(let id) = series.key.kind else { return nil }
        return store.photo(for: id)
    }

    private func makeMatch() -> Bool {
        guard let profile = store.profile, canContinue else { return false }
        ensureFriendIDs()
        var players: [Player] = []
        var ghostOffer: GhostOffer?
        var ghostSeat = -1
        for i in draft.seats.indices {
            let seat = draft.seats[i]
            if isMe(i) {
                players.append(Player(id: profile.id, name: profile.name))
            } else if seat.ghostSeat {
                guard let kind = draft.ghostKind,
                      let offer = store.ghostOffer(
                        kind,
                        startingScore: draft.config.startingScore,
                        outRule: draft.config.outRule,
                        matchID: draft.ghostMatchID
                      )
                else { return false }
                ghostOffer = offer
                ghostSeat = players.count
                players.append(Player(id: UUID(), name: offer.displayName))
            } else {
                let resolved = seat.isBot ? resolvedBot(seat) : nil
                let name = seat.isBot ? seatName(i) : String(seat.name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(24))
                players.append(Player(
                    id: seat.isBot ? UUID() : seat.friendID ?? UUID(),
                    name: name,
                    botLevel: resolved?.level,
                    botStyle: resolved?.style,
                    adaptiveBot: resolved?.adaptive == true ? true : nil
                ))
            }
        }
        guard !players.isEmpty else { return false }
        store.notePlayed(with: draft.seats.compactMap(\.friendID))
        if [.aroundClock, .countUp].contains(draft.config.mode) {
            draft.config.legsToWin = 1
            draft.config.setsToWin = 1
        }
        draft.config.startingScore = min(GameConfig.maximumScore, max(GameConfig.minimumScore, draft.config.startingScore))
        draft.config.handicaps = draft.config.mode == .x01 && seatsHaveHandicap ? draft.seats.map { $0.handicap ?? Handicap() } : nil
        let first = openingPlayer(count: players.count)
        draft.starter = first
        store.remember(draft)
        if savePreset { store.addPreset(name: presetName, setup: draft); savePreset = false }
        var match = Match(config: draft.config, players: players, firstPlayer: first)
        if let offer = ghostOffer, ghostSeat >= 0 {
            match.ghostKind = offer.kind
            match.ghostLabel = offer.kind.title
            match.ghostAverage = offer.average
            match.ghostVisits = offer.visits
            match.ghostVisitIndex = 0
            match.ghostPlayerIndex = ghostSeat
        }
        store.activeMatch = match
        store.feedback()
        return true
    }

    private func openingPlayer(count: Int) -> Int {
        guard count > 1 else { return 0 }
        switch opening {
        case .pick: return min(max(0, pickedStarter ?? 0), count - 1)
        case .bull: return min(max(0, bullWinner ?? 0), count - 1)
        case .random: return min(max(0, coinWinner ?? Int.random(in: 0..<count)), count - 1)
        case nil: return Int.random(in: 0..<count)
        }
    }
}

/// Plynulé rozbalení výšky — animuje mezi 0 a změřenou výškou obsahu (bez skoku nil→0).
private struct SmoothExpand<Content: View>: View {
    var isExpanded: Bool
    var animation: Animation
    var content: Content
    @State private var measuredHeight: CGFloat = 0

    init(isExpanded: Bool, animation: Animation, @ViewBuilder content: () -> Content) {
        self.isExpanded = isExpanded
        self.animation = animation
        self.content = content()
    }

    var body: some View {
        ZStack(alignment: .top) {
            content
                .fixedSize(horizontal: false, vertical: true)
                .hidden()
                .background {
                    GeometryReader { geo in
                        Color.clear.preference(key: SmoothExpandHeightKey.self, value: geo.size.height)
                    }
                }

            content
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .opacity(isExpanded ? 1 : 0)
        }
        .frame(height: isExpanded ? measuredHeight : 0, alignment: .top)
        .clipped()
        .onPreferenceChange(SmoothExpandHeightKey.self) { height in
            guard height > 0, abs(height - measuredHeight) > 0.5 else { return }
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) { measuredHeight = height }
        }
        .allowsHitTesting(isExpanded)
        .accessibilityHidden(!isExpanded)
        .animation(animation, value: isExpanded)
    }
}

private struct SmoothExpandHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

/// Vysvětlivka startu: kdo hází první a proč.
private struct OpeningInfoSheet: View {
    @Environment(\.dismiss) private var dismiss
    var mode: Opening
    var onSelect: () -> Void

    private var title: String {
        switch mode {
        case .random: return "Náhodně"
        case .pick: return "Vybrat hráče"
        case .bull: return "Rozhoz na střed"
        }
    }

    private var summary: String {
        switch mode {
        case .random: return "Los určí, kdo hází první."
        case .pick: return "Sám zvolíš, kdo začíná."
        case .bull: return "Každý hodí na střed. Červený bere před zeleným."
        }
    }

    private var rules: String {
        switch mode {
        case .random: return "Aplikace vylosuje prvního hráče až při startu zápasu. Nikdo si pořadí nevybírá a los je pokaždé nový."
        case .pick: return "Otevře se obrazovka se všemi hráči. Klepneš na toho, kdo má házet první. Ostatní jdou za ním v pořadí, v jakém jsou v zápase."
        case .bull: return "Každý hráč hodí jednu šipku na střed. Blíž ke středu vyhrává, červený střed bere před zeleným. Když jsou dva stejně blízko, hážou znovu jen oni. Vítěz rozhozu začíná zápas."
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if mode == .bull {
                        TouchDartboard(marks: [Dart(25, 2)], interactive: false) { _ in }
                            .frame(maxWidth: 320)
                            .frame(maxWidth: .infinity)
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        Text("O co jde")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.secondary)
                        Text(summary)
                            .font(.body)
                        Text("Co udělat")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.secondary)
                            .padding(.top, 4)
                        Text(rules)
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.card, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                    Button("Vybrat tenhle start", action: onSelect)
                        .buttonStyle(PrimaryButton())
                }
                .padding(20)
            }
            .screen()
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Zavřít") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}

/// Vysvětlivka režimu: terč ukáže, o co ve hře jde.
private struct ModeInfoSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var mode: GameMode
    var onSelect: () -> Void
    @State private var beat = 0

    private var beats: [(darts: [Dart], caption: String)] {
        switch mode {
        case .x01:
            return [
                ([Dart(20, 3), Dart(20, 3), Dart(20, 3)], "Každá šipka ubírá ze startu. Tři T20 jsou 180."),
                ([Dart(20, 2)], "Na nulu se zavírá. U double out musí poslední šipka být double."),
                ([Dart(20, 3)], "Přehoz návštěvu zahodí a skóre se vrátí.")
            ]
        case .cricket:
            return [
                ([Dart(20), Dart(20), Dart(20, 3)], "Tři zásahy zavřou číslo. Triple počítá za tři."),
                ([Dart(25, 2)], "Po 15–20 se zavírá bull. 25 i 50 se počítají."),
                ([Dart(20, 3)], "Body za číslo jdou jen tobě, dokud ho soupeř taky nezavře.")
            ]
        case .aroundClock:
            return [
                ([Dart(1)], "Začni jedničkou. Platí single, double i triple."),
                ([Dart(2), Dart(3)], "Další číslo přijde až po zásahu. Minutí zůstává."),
                ([Dart(25, 2)], "Po dvacítce kolo uzavře bull.")
            ]
        case .countUp:
            return [
                ([Dart(20, 3), Dart(20, 3), Dart(20, 3)], "Body se přičítají. 180 je nejvyšší návštěva."),
                ([Dart(19, 3), Dart(20, 3), Dart(18, 3)], "Hraje se zvolený počet kol. Vyhrává vyšší součet.")
            ]
        }
    }

    private var rules: String {
        switch mode {
        case .x01: return "Zvolíš start, třeba 501. Šipky od něj odečítají. Skóre pod nulu, nebo zavření bez požadovaného násobiče, je přehoz. Leg vyhraje, kdo se dostane přesně na nulu."
        case .cricket: return "Cíle jsou 20, 19, 18, 17, 16, 15 a bull. Každý zásah je jedna značka, triple jsou tři. Tři značky číslo zavřou. Další zásahy na číslo, které soupeř ještě nemá, přičítají body. Vyhrává, kdo zavře všechno a má aspoň tolik bodů jako soupeř."
        case .aroundClock: return "Jde se popořadě od 1 do 20 a nakonec na bull. Posouvá tě jakýkoli násobič daného čísla. Minutí tě nevrací, jen zůstáváš na stejném cíli."
        case .countUp: return "Nikdo neodečítá. Každá návštěva přičte body a po zvoleném počtu kol vyhrává vyšší součet. Je to závod o maximum, ne o zavření."
        }
    }

    var body: some View {
        let shown = beats[beat % beats.count]
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
                        Text(mode.detail)
                            .font(.body)
                        Text("Co udělat")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.secondary)
                            .padding(.top, 4)
                        Text(rules)
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
            .navigationTitle(mode.shortTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Zavřít") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .task(id: mode.id) {
            guard !reduceMotion, beats.count > 1 else { return }
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 2_800_000_000)
                guard !Task.isCancelled else { return }
                beat = (beat + 1) % beats.count
            }
        }
    }
}

struct ChoiceCard: View {
    var title: String
    var detail: String
    var symbol: String
    var selected: Bool
    var action: () -> Void
    /// Když je nastavené, stojí na místě kolečka výběru.
    var info: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 0) {
            Button(action: action) {
                HStack(spacing: 16) {
                    Image(systemName: symbol).font(.title2).frame(width: 46, height: 52).foregroundStyle(Theme.action)
                    VStack(alignment: .leading, spacing: 7) {
                        Text(title).font(.title3.bold())
                        Text(detail).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                    if info == nil {
                        Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(selected ? Theme.action : .secondary)
                            .contentTransition(.symbolEffect(.replace))
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if let info {
                Button(action: info) {
                    Image(systemName: "info.circle")
                        .font(.title2)
                        .foregroundStyle(Theme.action)
                        .frame(width: 44, height: 44)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Info o hře \(title)")
            }
        }
        .foregroundStyle(.primary)
        .padding(.leading, 18)
        .padding(.trailing, info == nil ? 18 : 10)
        .padding(.vertical, 18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(selected ? Theme.action.opacity(0.09) : Theme.card, in: RoundedRectangle(cornerRadius: 22))
        .overlay(RoundedRectangle(cornerRadius: 22).stroke(selected ? Theme.action : Theme.stroke, lineWidth: selected ? 1.5 : 1))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
struct ChoicePill: View {
    var title: String; var selected: Bool; var action: () -> Void
    var body: some View {
        Button(action: action) { Text(title).font(.system(.subheadline, design: .rounded, weight: .bold)).frame(maxWidth: .infinity).frame(minHeight: 44).foregroundStyle(selected ? Theme.onAccent : .primary).background(selected ? Theme.accentFill : Theme.background, in: RoundedRectangle(cornerRadius: 12, style: .continuous)) }.buttonStyle(.plain).accessibilityAddTraits(selected ? .isSelected : [])
    }
}

private extension View {
    /// Kroužek v barvě hráče kolem avataru.
    func playerRing(_ color: Color?) -> some View {
        padding(color == nil ? 0 : 3)
            .overlay {
                if let color { Circle().strokeBorder(color, lineWidth: 3) }
            }
    }

    /// Karta hráče s nádechem a rámečkem v jeho barvě.
    func playerCard(_ color: Color?) -> some View {
        let shape = RoundedRectangle(cornerRadius: 20, style: .continuous)
        return background {
            ZStack(alignment: .leading) {
                Theme.card
                if let color { color.opacity(0.10) }
            }
        }
        .clipShape(shape)
        .overlay(shape.strokeBorder(color?.opacity(0.55) ?? Theme.stroke, lineWidth: color == nil ? 1 : 1.5))
        .animation(.easeInOut(duration: 0.25), value: color)
    }
}

/// Mřížka velkých voleb s volitelným popiskem.
struct RuleTiles<ID: Hashable>: View {
    var options: [(id: ID, title: String, detail: String?)]
    var selection: ID
    var columns: Int
    var alignment: HorizontalAlignment = .center
    /// Stejná výška dlaždic (pro řádky s popiskem).
    var equalHeight: Bool = false
    var onSelect: (ID) -> Void

    var body: some View {
        let tall = options.contains { $0.detail != nil } || equalHeight
        let tileHeight: CGFloat = tall ? 72 : 50
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: columns), spacing: 8) {
            ForEach(options, id: \.id) { option in
                let selected = option.id == selection
                Button { onSelect(option.id) } label: {
                    VStack(alignment: alignment, spacing: 3) {
                        Text(option.title)
                            .font(.system(.headline, design: .rounded, weight: .bold))
                            .monospacedDigit()
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                        if let detail = option.detail {
                            Text(detail)
                                .font(.caption2)
                                .foregroundStyle(selected ? Color.black.opacity(0.7) : Color.secondary)
                                .multilineTextAlignment(alignment == .center ? .center : .leading)
                                .lineLimit(2)
                                .minimumScaleFactor(0.85)
                        } else if equalHeight {
                            Text(" ")
                                .font(.caption2)
                                .hidden()
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity, minHeight: tileHeight, maxHeight: tileHeight, alignment: Alignment(horizontal: alignment, vertical: .center))
                    .foregroundStyle(selected ? Color.black : Color.primary)
                    .background(selected ? Theme.brand : Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .sensoryFeedback(.selection, trigger: selection)
    }
}

/// Libovolné startovní skóre. Prázdné pole znamená stejně jako hra.
struct ScoreEntryField: View {
    var value: Int?
    var placeholder: Int
    var onCommit: (Int?) -> Void
    @State private var text = ""
    @FocusState private var focused: Bool
    private var range: ClosedRange<Int> { GameConfig.minimumScore...GameConfig.maximumScore }
    private var invalid: Bool { Int(text).map { !range.contains($0) } ?? false }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Vlastní číslo").font(.subheadline.weight(.semibold))
                    Text(invalid ? "Jen \(range.lowerBound) až \(range.upperBound)" : "Napiš jakýkoli start")
                        .font(.caption)
                        .foregroundStyle(invalid ? Color.red : Color.secondary)
                        .contentTransition(.opacity)
                }
                Spacer(minLength: 8)
                TextField("\(placeholder)", text: $text)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.center)
                    .font(.system(.title3, design: .rounded, weight: .bold))
                    .monospacedDigit()
                    .focused($focused)
                    .frame(width: 104, height: 46)
                    .background(Color.primary.opacity(0.06), in: Capsule())
                    .overlay(Capsule().stroke(invalid ? Color.red : (focused ? Theme.action : Color.clear), lineWidth: 1.5))
                    .accessibilityLabel("Vlastní start")
            }
        }
        .onAppear { text = value.map(String.init) ?? "" }
        .onChange(of: value) { _, new in
            if !focused { text = new.map(String.init) ?? "" }
        }
        .onChange(of: focused) { _, isFocused in
            if !isFocused { text = value.map(String.init) ?? "" }
        }
        .onChange(of: text) { _, raw in
            let digits = String(raw.filter(\.isNumber).prefix(4))
            if digits != raw { text = digits; return }
            guard focused else { return }
            if digits.isEmpty { onCommit(nil) }
            else if let number = Int(digits), range.contains(number) { onCommit(number) }
        }
    }
}

/// Velké číslo s tlačítky minus a plus.
struct CountStepper: View {
    var title: String
    var value: Int
    var caption: String
    var canDecrease: Bool
    var canIncrease: Bool
    var onStep: (Int) -> Void

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(caption).font(.caption).foregroundStyle(.secondary).contentTransition(.opacity)
            }
            Spacer(minLength: 8)
            HStack(spacing: 0) {
                stepButton("minus", enabled: canDecrease, label: "Méně") { onStep(-1) }
                Text("\(value)")
                    .font(.system(.title2, design: .rounded, weight: .bold))
                    .monospacedDigit()
                    .frame(minWidth: 52)
                    .contentTransition(.numericText(value: Double(value)))
                stepButton("plus", enabled: canIncrease, label: "Více") { onStep(1) }
            }
            .padding(3)
            .background(Color.primary.opacity(0.06), in: Capsule())
        }
        .sensoryFeedback(.selection, trigger: value)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(title)
        .accessibilityValue("\(value)")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: if canIncrease { onStep(1) }
            case .decrement: if canDecrease { onStep(-1) }
            @unknown default: break
            }
        }
    }

    private func stepButton(_ symbol: String, enabled: Bool, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.subheadline.weight(.bold))
                .frame(width: 44, height: 44)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(enabled ? Color.primary : Color.secondary.opacity(0.4))
        .disabled(!enabled)
        .accessibilityLabel(label)
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

private struct BullShot: Identifiable {
    let id = UUID()
    let player: Int
    let dart: Dart
}

/// Body a přímky leží mimo `scaleEffect`, aby při přiblížení zůstaly stejně velké.
private struct BullPins: View, Animatable {
    struct Pin {
        var x: Double
        var y: Double
        var color: Color
        var closest: Bool
    }

    var zoom: CGFloat
    var pins: [Pin]

    var animatableData: CGFloat {
        get { zoom }
        set { zoom = newValue }
    }

    var body: some View {
        Canvas { context, size in
            let radius = min(size.width, size.height) * 0.43 * zoom
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            for pin in pins {
                let end = CGPoint(x: center.x + pin.x * radius, y: center.y + pin.y * radius)
                var line = Path()
                line.move(to: center)
                line.addLine(to: end)
                context.stroke(line, with: .color(.black.opacity(0.55)), style: StrokeStyle(lineWidth: pin.closest ? 5 : 4, lineCap: .round))
                context.stroke(line, with: .color(pin.color), style: StrokeStyle(lineWidth: pin.closest ? 3 : 2, lineCap: .round))
                let dot = CGRect(x: end.x - 7, y: end.y - 7, width: 14, height: 14)
                context.fill(Path(ellipseIn: dot), with: .color(pin.color))
                context.stroke(Path(ellipseIn: dot), with: .color(.black.opacity(0.7)), lineWidth: 1.5)
            }
            if !pins.isEmpty {
                let hub = CGRect(x: center.x - 3, y: center.y - 3, width: 6, height: 6)
                context.fill(Path(ellipseIn: hub), with: .color(.white))
            }
        }
    }
}

struct StarterPick: Identifiable, Equatable {
    var id: Int
    var name: String
    var detail: String
    var photo: Data?
    var asset: String?
    var bot: Bool
    var tint: Color
}

/// Obrazovka startu: klepnutí na hráče ho vybere jako toho, kdo hází první.
struct StarterPickerView: View {
    var players: [StarterPick]
    var initial: Int?
    var onFinish: (Int) -> Void
    var onCancel: () -> Void

    @State private var selection: Int?

    private var chosen: StarterPick? { players.first { $0.id == selection } }
    private var roomy: Bool { players.count <= 2 }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                header
                    .padding(.top, 8)
                ScrollView {
                    VStack(spacing: 12) {
                        ForEach(players) { player in
                            Button {
                                withAnimation(.smooth(duration: 0.25)) { selection = player.id }
                            } label: {
                                playerCard(player, selected: player.id == selection)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.top, 28)
                    .padding(.bottom, 12)
                }
                confirm
                    .padding(.bottom, 10)
            }
            .padding(.horizontal, 24)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background { backdrop }
            .navigationTitle("Výběr hráče")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Zavřít", action: onCancel)
                }
            }
        }
        .sensoryFeedback(.selection, trigger: selection)
        .onAppear {
            selection = initial.flatMap { id in players.contains { $0.id == id } ? id : nil }
        }
    }

    private var header: some View {
        VStack(spacing: 6) {
            Text("Start")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            Text("Kdo hází první")
                .font(.largeTitle.bold())
                .multilineTextAlignment(.center)
            Text("Klepni na hráče. Tím se vybere a začíná první leg.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var backdrop: some View {
        ZStack {
            Theme.background
            RadialGradient(
                colors: [(chosen?.tint ?? Theme.brand).opacity(0.22), .clear],
                center: .center,
                startRadius: 20,
                endRadius: 420
            )
        }
        .ignoresSafeArea()
        .animation(.smooth(duration: 0.35), value: chosen?.id)
    }

    private var confirm: some View {
        let ready = chosen != nil
        return GlassEffectContainer(spacing: 10) {
            Button {
                guard let selection else { return }
                onFinish(selection)
            } label: {
                Label(ready ? "Začíná \(chosen?.name ?? "hráč")" : "Klepni na hráče", systemImage: ready ? "flag.checkered" : "hand.tap")
                    .font(.headline)
                    .foregroundStyle(ready ? Theme.onAccent : Color.secondary)
                    .frame(maxWidth: .infinity, minHeight: 54)
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .glassEffect(ready ? .regular.tint(Theme.brand).interactive() : .regular, in: Capsule())
            .disabled(!ready)
        }
        .animation(.smooth(duration: 0.25), value: selection)
    }

    private func playerCard(_ player: StarterPick, selected: Bool) -> some View {
        HStack(spacing: 16) {
            Avatar(
                name: player.name,
                bot: player.bot,
                size: roomy ? 84 : 64,
                photo: player.photo,
                asset: player.asset
            )
            .playerRing(player.tint)
            VStack(alignment: .leading, spacing: 4) {
                Text(player.name)
                    .font(roomy ? .title2.bold() : .title3.bold())
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(player.detail)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(player.tint)
            }
            Spacer(minLength: 8)
            Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                .font(.title)
                .foregroundStyle(selected ? player.tint : Color.secondary)
                .contentTransition(.symbolEffect(.replace))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, roomy ? 22 : 16)
        .frame(maxWidth: .infinity, minHeight: roomy ? 120 : 88, alignment: .leading)
        .background(
            selected ? player.tint.opacity(0.18) : Color.primary.opacity(0.06),
            in: RoundedRectangle(cornerRadius: 24, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(selected ? player.tint : Color.primary.opacity(0.08), lineWidth: selected ? 2 : 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(player.name), \(player.detail)")
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityHint("Vybere hráče, který hází první")
    }
}

/// Rozhoz na střed. Červený střed je výš než zelený. Stejný výsledek se hází znovu v opačném pořadí.
/// Určí, kdo začíná, nebo rozhodne leg po vypršení limitu šipek.
struct BullOffView: View {
    enum Purpose { case opening, decider }
    var names: [String]
    var bots: [Int?]
    var purpose: Purpose = .opening
    var onFinish: (Int) -> Void
    var onCancel: () -> Void

    @State private var order: [Int]
    @State private var shots: [BullShot] = []
    @State private var winner: Int?
    @State private var note: String?
    /// Každé kolo hodů má vlastní číslo, aby bot hodil i tehdy, když začíná stejný hráč.
    @State private var round = 0
    /// Remíza je vidět chvíli na terči, než začne další kolo.
    @State private var tieShown = false
    /// 1, dokud nehodí všichni. Pak se plynule přiblíží na rozdíl hodů.
    @State private var shownZoom: CGFloat = 1

    init(names: [String], bots: [Int?], purpose: Purpose = .opening, onFinish: @escaping (Int) -> Void, onCancel: @escaping () -> Void) {
        self.names = names
        self.bots = bots
        self.purpose = purpose
        self.onFinish = onFinish
        self.onCancel = onCancel
        _order = State(initialValue: Array(names.indices))
    }

    private var pending: [Int] {
        let done = Set(shots.map(\.player))
        return order.filter { !done.contains($0) }
    }
    private var current: Int? { winner == nil && !tieShown ? pending.first : nil }

    private var headline: String {
        if let winner { return "Blíž je \(name(winner))" }
        if tieShown { return "Remíza" }
        if let current { return "Hází \(name(current))" }
        return "Rozhoz na střed"
    }

    private var subline: String {
        if let note { return note }
        if winner != nil { return "\(purpose == .decider ? "Leg bere" : "Začíná") \(name(winner ?? 0)). Terč je přiblížený na rozdíl hodů." }
        if shots.isEmpty {
            let tap = "Klepni tam, kam šipka dopadla. Přímka je v procentech poloměru."
            return purpose == .decider ? "Limit šipek vypršel a nikdo nezavřel. Leg rozhodne bližší šipka. \(tap)" : tap
        }
        return "Červený střed bere před zeleným."
    }

    /// Přiblížení až ve chvíli, kdy hodili všichni. Do té doby zůstává celý terč.
    private var targetZoom: CGFloat {
        guard pending.isEmpty, !shots.isEmpty else { return 1 }
        let farthest = shots.compactMap { shot -> Double? in
            guard let x = shot.dart.x, let y = shot.dart.y else { return nil }
            return hypot(x, y)
        }.max() ?? 1
        guard farthest > 0.02 else { return 1 }
        return CGFloat(min(6, max(1, 0.78 / farthest)))
    }

    private var rankedShots: [(player: Int, dart: Dart, rank: Int)] {
        shots.map { (player: $0.player, dart: $0.dart, rank: rank($0.dart)) }
            .sorted { $0.rank < $1.rank }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 14) {
                header
                TouchDartboard(marks: [], interactive: humanTurn) { dart in
                    guard let current, humanTurn else { return }
                    record(dart, player: current)
                }
                .scaleEffect(shownZoom, anchor: .center)
                .overlay {
                    BullPins(
                        zoom: shownZoom,
                        pins: shots.compactMap { shot in
                            guard let x = shot.dart.x, let y = shot.dart.y, x.isFinite, y.isFinite else { return nil }
                            return BullPins.Pin(x: x, y: y, color: color(shot.player), closest: rankedShots.count > 1 && rank(shot.dart) == rankedShots.first?.rank)
                        }
                    )
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
            .background(Color.black.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Zavřít", action: onCancel)
                }
                ToolbarItem(placement: .bottomBar) {
                    Button("Znovu", action: reset)
                }
                ToolbarSpacer(.flexible, placement: .bottomBar)
                ToolbarItem(placement: .bottomBar) {
                    Button(purpose == .decider ? "Potvrdit" : "Hrát") { if let winner { onFinish(winner) } }
                        .buttonStyle(.borderedProminent)
                        .tint(Theme.brand)
                        .foregroundStyle(.black)
                        .disabled(winner == nil)
                }
            }
            .toolbarColorScheme(.dark, for: .navigationBar)
        }
        .preferredColorScheme(.dark)
        .onChange(of: targetZoom) { _, new in
            withAnimation(.smooth(duration: 1.05)) { shownZoom = new }
        }
        .task(id: "\(round)-\(current ?? -1)") {
            guard let current, bots.indices.contains(current), let level = bots[current], winner == nil else { return }
            try? await Task.sleep(nanoseconds: 700_000_000)
            guard !Task.isCancelled, self.current == current, winner == nil else { return }
            record(botDart(level: level), player: current)
        }
        .task(id: tieShown ? round : -1) {
            guard tieShown else { return }
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            guard !Task.isCancelled, tieShown else { return }
            withAnimation(.smooth(duration: 0.45)) {
                order = Array(order.reversed())
                shots = []
                tieShown = false
                round += 1
                note = "Hází se znovu v opačném pořadí. Začíná \(name(order.first ?? 0))."
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(headline)
                .font(.title.bold())
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(subline)
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.72))
                .fixedSize(horizontal: false, vertical: true)
            if !rankedShots.isEmpty {
                HStack(spacing: 8) {
                    ForEach(rankedShots, id: \.player) { item in
                        let closest = item.rank == rankedShots.first?.rank
                        VStack(alignment: .leading, spacing: 3) {
                            HStack(spacing: 6) {
                                Circle().fill(color(item.player)).frame(width: 10, height: 10)
                                Text(name(item.player))
                                    .font(.subheadline.weight(.bold))
                                    .lineLimit(1)
                            }
                            Text(measureText(item.dart))
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.white.opacity(0.8))
                            if rankedShots.count > 1 {
                                Text(closest && rankedShots.allSatisfy { $0.rank == item.rank } ? "stejně" : (closest ? "blíž" : "dál"))
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(closest ? Color(red: 0.30, green: 0.90, blue: 0.55) : .white.opacity(0.55))
                            }
                        }
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .background(.white.opacity(closest ? 0.14 : 0.06), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                }
            }
        }
    }

    private func color(_ player: Int) -> Color { Theme.playerColor(player) }

    private func reset() {
        order = Array(names.indices)
        shots = []
        winner = nil
        note = nil
        tieShown = false
        round += 1
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
        guard winner == nil, !tieShown, pending.isEmpty, !order.isEmpty else { return }
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
            order = leaders
            tieShown = true
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
        let spread = max(0.04, 0.78 - Double(min(BotDifficulty.count, max(1, level))) * 0.034)
        let radius = sqrt(Double.random(in: 0...1)) * spread
        let angle = Double.random(in: 0..<(2 * Double.pi))
        return BoardGeometry.hit(x: cos(angle) * radius, y: sin(angle) * radius)
    }
}

#if DEBUG
#Preview("Výběr hráče") {
    StarterPickerView(
        players: [
            StarterPick(id: 0, name: "Ty", detail: "Ty", photo: nil, asset: nil, bot: false, tint: Theme.playerColor(0)),
            StarterPick(id: 1, name: "Bot 5", detail: "Bot", photo: nil, asset: BotLevel.get(5).photo, bot: true, tint: Theme.playerColor(1))
        ],
        initial: nil,
        onFinish: { _ in },
        onCancel: {}
    )
}
#Preview("Hrát") {
    NavigationStack { PlayView() }.dartiqoPreview(PreviewSupport.store(activeMatch: false))
}
#Preview("Setup") {
    NavigationStack { SetupView(mode: .x01) }.dartiqoPreview(PreviewSupport.store(activeMatch: false))
}
#endif
