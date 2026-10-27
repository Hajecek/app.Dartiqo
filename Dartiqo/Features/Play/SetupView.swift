import SwiftUI

/// Průvodce zakládá nebo upravuje online lobby místo lokálního zápasu.
struct OnlineSetupMode {
    var editing = false
    var isPublic = true
    var finish: (SetupDraft, OnlineLobbySettings) async -> Void
}

struct PlayView: View {
    @EnvironmentObject var store: AppStore
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Eyebrow(text: "Match room")
                Text("Jak dnes\nzahraješ?").font(.system(size: 38, weight: .bold, design: .rounded))
                Text("Vyber hru. Sestav soupeře. Hraj po svém.").foregroundStyle(.secondary)
                ForEach(GameMode.allCases) { mode in
                    NavigationLink { SetupView(mode: mode, pickGame: false) } label: {
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
                        NavigationLink { SetupView(mode: preset.setup.config.mode, preset: preset.setup, pickGame: false) } label: {
                            HStack { Image(systemName: "bookmark.fill").foregroundStyle(Theme.action); VStack(alignment: .leading, spacing: 5) { Text(preset.name).bold(); Text(preset.setup.config.summary).font(.caption).foregroundStyle(.secondary) }; Spacer(); Image(systemName: "chevron.right") }.foregroundStyle(.primary).surface()
                        }.buttonStyle(.plain).contextMenu { Button("Odstranit předvolbu", role: .destructive) { store.deletePreset(preset.id) } }
                    }
                }
                Label("Hra a všechny předvolby fungují offline.", systemImage: "wifi.slash").font(.caption).foregroundStyle(.secondary)
            }.padding(22).frame(maxWidth: 760)
        }.screen().navigationTitle("Hrát").navigationBarTitleDisplayMode(.inline)
    }
}

extension GameMode {
    /// Stejné odstíny jako dlaždice na Domů a v Tréninku.
    var tileColors: [Color] {
        switch self {
        case .x01: return [Color(red: 1.0, green: 0.42, blue: 0.29), Color(red: 0.86, green: 0.20, blue: 0.20)]
        case .cricket: return [Color(red: 0.18, green: 0.78, blue: 0.48), Color(red: 0.05, green: 0.50, blue: 0.32)]
        case .aroundClock: return [Color(red: 0.18, green: 0.48, blue: 0.98), Color(red: 0.08, green: 0.22, blue: 0.72)]
        case .countUp: return [Color(red: 0.58, green: 0.28, blue: 0.96), Color(red: 0.34, green: 0.12, blue: 0.70)]
        }
    }
}

private enum Opening: String, Identifiable {
    case random, pick, bull
    var id: String { rawValue }
}

private enum SetupStep: Int, Comparable {
    case game, players, rules, opening

    static func < (lhs: SetupStep, rhs: SetupStep) -> Bool { lhs.rawValue < rhs.rawValue }

    var title: String {
        switch self {
        case .game: return "Hra"
        case .players: return "Hráči"
        case .rules: return "Pravidla"
        case .opening: return "Start"
        }
    }
}

struct SetupView: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dismiss) private var dismiss
    private let onHome: (() -> Void)?
    private let coversLiveBar: Bool
    @State private var draft: SetupDraft
    @State private var live = false
    @State private var replace = false
    @State private var savePreset = false
    @State private var presetName = "Moje 501"
    @State private var scoreText = "501"
    @State private var scoreExact = false
    @State private var limitCustom = false
    @State private var friendPicker: FriendPickerTarget?
    @State private var botPicker: BotPickerTarget?
    @State private var ghostPicker: GhostPickerTarget?
    /// Rozbalená karta handicapu (index místa).
    @State private var handicapFocus: Int?
    /// Handicap je volitelný. Hodnota je vidět i když je editor sbalený.
    @State private var showHandicap = false
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
        var choice: BotChoice
    }
    private struct GhostPickerTarget: Identifiable, Equatable {
        var id = UUID()
        /// `true` = přidat ghosta do sestavy, `false` = jen změnit variantu.
        var adding: Bool
        var initialKind: GhostKind?
    }
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
    @State private var showH2HAfterBull = false
    @State private var showPregame = false
    @State private var pregameLaunched = false
    /// Bilance už proběhla (los nebo rozhoz). Zahodit rozehraný zápas ji nesmí pustit znovu.
    @State private var pregameSeen = false
    @State private var coinWinner: Int?
    @State private var pregameSeries: HeadToHead?
    @State private var openSoloTraining = false
    @State private var step: SetupStep
    /// Směr posledního přechodu mezi kroky, aby obrazovka vyjela ze správné strany.
    @State private var stepsForward = true
    /// Hra už jednou prošla do nastavení. Na výběru hry se pak označí.
    @State private var gameChosen: Bool
    /// Krok, kterým obrazovka začala. Zpět z něj vede systémová navigace.
    private let entryStep: SetupStep
    /// Online zápas nezačne na telefonu. Po pravidlech se založí nebo upraví lobby.
    private let online: OnlineSetupMode?
    @Binding private var onlineNotice: String?
    @State private var onlinePublic = true
    @State private var onlineSending = false
    private var isOnline: Bool { online != nil }
    private var isEditingLobby: Bool { online?.editing == true }
    private var startsWithGame: Bool { entryStep == .game }
    private let presetScores = [101, 301, 501, 701, 1001]
    private var options: Binding<MatchOptions> { Binding(get: { draft.config.settings }, set: { draft.config.options = $0 }) }
    init(
        mode: GameMode,
        preset: SetupDraft? = nil,
        onHome: (() -> Void)? = nil,
        coversLiveBar: Bool = false,
        startAtOpening: Bool = false,
        pickGame: Bool = true,
        online: OnlineSetupMode? = nil,
        onlineNotice: Binding<String?> = .constant(nil)
    ) {
        self.onHome = onHome
        self.coversLiveBar = coversLiveBar
        self.online = online
        self._onlineNotice = onlineNotice
        _onlinePublic = State(initialValue: online?.isPublic ?? true)
        let draft = preset ?? SetupDraft(mode: mode)
        let entry: SetupStep
        // Rychlá hra přijde s hotovou sestavou a má hned ukázat, kdo hází první.
        if let online {
            entry = online.editing ? .rules : .game
        } else if startAtOpening {
            entry = draft.seats.count > 1 ? .opening : .rules
        } else {
            entry = pickGame ? .game : .players
        }
        self.entryStep = entry
        _step = State(initialValue: entry)
        _gameChosen = State(initialValue: entry != .game)
        _draft = State(initialValue: draft)
        if startAtOpening, draft.seats.contains(where: { !($0.handicap?.isEmpty ?? true) }) {
            _showHandicap = State(initialValue: true)
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
    private var advanceTitle: String {
        if isOnline, isLastStep { return isEditingLobby ? "Uložit" : "Založit lobby" }
        return isSoloTraining ? "Trénovat" : "Hrát"
    }
    private var advanceSymbol: String {
        if isOnline, isLastStep { return isEditingLobby ? "checkmark" : "person.2.fill" }
        return isSoloTraining ? "scope" : "play.fill"
    }
    /// Proč ještě nejde spustit zápas. U sóla je to nápověda, tlačítko zůstane zapnuté.
    private var advanceHint: String? {
        if isOnline { return nil }
        if let rosterHint { return rosterHint }
        if opening == .pick, pickedStarter == nil { return "Vyber hráče, který začíná." }
        if opening == .bull, bullWinner == nil { return "Dohraj rozhoz na střed." }
        return nil
    }
    /// Co chybí v sestavě. U sóla je to nápověda, pokračovat jde dál.
    private var rosterHint: String? {
        if isOnline {
            if !canContinue { return "Doplň jméno soupeře." }
            return draft.seats.count < 2 ? "Soupeře můžeš přidat teď, nebo ho pozvat potom v lobby." : nil
        }
        if isSoloTraining { return "Sám u terče otevře trénink. Přidej soupeře, pokud chceš zápas." }
        if draft.seats.contains(where: \.ghostSeat) {
            let offer = draft.ghostKind.flatMap {
                store.ghostOffer($0, startingScore: draft.config.startingScore, outRule: draft.config.outRule, matchID: draft.ghostMatchID)
            }
            if offer == nil { return "Vyber ghosta, který umí tuhle hru." }
        }
        if !canContinue { return "Doplň jméno každého hráče." }
        return nil
    }

    /// Kroky průvodce. „Kdo začíná“ má smysl jen pro víc hráčů.
    private var flow: [SetupStep] {
        if isOnline { return isEditingLobby ? [.rules] : [.game, .players, .rules] }
        return showsOpening ? [.game, .players, .rules, .opening] : [.game, .players, .rules]
    }
    private var isLastStep: Bool { step == flow.last }
    private func neighbour(_ offset: Int) -> SetupStep? {
        guard let index = flow.firstIndex(of: step) else { return nil }
        let target = index + offset
        return flow.indices.contains(target) ? flow[target] : nil
    }
    /// Jestli jde z tohoto kroku dál.
    private var stepReady: Bool {
        if isLastStep { return canAdvance }
        switch step {
        case .players: return canContinue
        default: return true
        }
    }
    private var stepHint: String? {
        if isLastStep { return advanceHint }
        return step == .players ? rosterHint : nil
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
        ZStack {
            ScrollView {
                page(for: step)
                    .padding(.horizontal, 20)
                    .padding(.top, step == .game ? 20 : 8)
                    .padding(.bottom, 20)
                    .frame(maxWidth: 760)
            }
            .id(step)
            .transition(reduceMotion ? .opacity : .push(from: stepsForward ? .trailing : .leading))
        }
        .animation(motion, value: draft.config.mode)
        .safeAreaInset(edge: .top, spacing: 0) {
            if step != .game {
                stepProgress
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if step != .game {
                setupBar
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .toolbar(step == .game ? .automatic : .hidden, for: .tabBar)
        .navigationBarBackButtonHidden(showsStepBack)
        .screen()
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle(isEditingLobby ? "Upravit lobby" : step == .game || (isOnline && step == entryStep) ? "Nový zápas" : step.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if showsStepBack, let previous = neighbour(-1) {
                ToolbarItem(placement: .topBarLeading) {
                    Button { goTo(previous) } label: {
                        Image(systemName: "chevron.left")
                    }
                    .accessibilityLabel("Zpět na \(previous.title.lowercased())")
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
        .onAppear {
            scoreText = "\(draft.config.startingScore)"
            if !presetScores.contains(draft.config.startingScore) { scoreExact = true }
            if seatsHaveHandicap { showHandicap = true }
            syncLiveBar()
        }
        .onDisappear {
            if coversLiveBar { store.localSetupCoversBar = false }
        }
        .onChange(of: store.section) { _, _ in syncLiveBar() }
        .onChange(of: showBullOff) { _, shown in
            if !shown {
                bullLaunched = false
                showH2HAfterBull = false
            }
        }
        .onChange(of: showPregame) { _, shown in
            if !shown {
                pregameLaunched = false
                pregameSeen = false
                pregameSeries = nil
            }
        }
        .confirmationDialog("Máš rozehraný zápas", isPresented: $replace, titleVisibility: .visible) {
            Button("Pokračovat v rozehraném") {
                pregameSeen = false
                live = true
            }
            Button("Zahodit rozehraný a spustit nový", role: .destructive) { confirmReplace() }
            Button("Zrušit", role: .cancel) { pregameSeen = false }
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
                pickGame(mode)
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
            showH2HAfterBull = false
            showPregame = false
            pregameLaunched = false
            pregameSeen = false
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
                } else if showH2HAfterBull, let series = pregameSeries {
                    HeadToHeadPregameView(
                        series: series,
                        myName: store.profile?.name ?? "Já",
                        myPhoto: store.profile?.photoJPEG,
                        theirPhoto: pregameOpponentPhoto(series),
                        onContinue: { finishAfterBull() },
                        onCancel: {
                            showBullOff = false
                            showH2HAfterBull = false
                            pregameSeries = nil
                        }
                    )
                    .transition(.opacity)
                } else {
                    BullOffView(names: draft.seats.indices.map(seatName), bots: draft.seats.indices.map { index in
                        isMe(index) ? nil : (draft.seats[index].isBot ? draft.seats[index].level : nil)
                    }) { winner in
                        bullWinner = winner
                        opening = .bull
                        commitScoreFromField()
                        ensureFriendIDs()
                        if let active = store.activeMatch, !active.finished {
                            showBullOff = false
                            Task { @MainActor in
                                try? await Task.sleep(nanoseconds: 450_000_000)
                                replace = true
                            }
                        } else if let series = makePregameSeries() {
                            pregameSeries = series
                            withAnimation(.easeInOut(duration: 0.3)) { showH2HAfterBull = true }
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
            .onAppear {
                bullLaunched = false
                showH2HAfterBull = false
                pregameSeries = nil
            }
        }
        .fullScreenCover(isPresented: $showPregame) { pregameCover() }
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

    private var canAdvance: Bool { isOnline ? canContinue : (isSoloTraining || canPlay) }

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
        VStack(spacing: 8) {
            if let onlineNotice, !onlineNotice.isEmpty {
                Text(onlineNotice)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
            } else if let stepHint {
                Text(stepHint)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(stepReady ? Color.secondary : Color.primary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .contentTransition(.opacity)
            }
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

                    Button {
                        if isLastStep {
                            advance()
                        } else if let next = neighbour(1) {
                            goTo(next)
                        }
                    } label: {
                        HStack(spacing: 8) {
                            Text(isLastStep ? (onlineSending ? "Zakládám…" : advanceTitle) : "Další")
                                .font(.headline)
                                .contentTransition(.opacity)
                            Image(systemName: isLastStep ? advanceSymbol : "arrow.right")
                                .font(.subheadline.weight(.bold))
                                .contentTransition(.symbolEffect(.replace))
                        }
                        .foregroundStyle(stepReady ? Color.black : Color.secondary)
                        .frame(maxWidth: .infinity, minHeight: 56)
                        .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .glassEffect(stepReady ? .regular.tint(Theme.brand).interactive() : .regular, in: Capsule())
                    .disabled(!stepReady || onlineSending)
                    .animation(motion, value: stepReady)
                    .animation(motion, value: isLastStep)
                    .animation(motion, value: isSoloTraining)
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 6)
        .background(Theme.background.opacity(0.94))
    }

    // MARK: Krok 1 – výběr hry

    private var stepMotion: Animation { reduceMotion ? .easeInOut(duration: 0.2) : .smooth(duration: 0.4) }

    private func goTo(_ target: SetupStep) {
        guard target != step else { return }
        hideKeyboard()
        if target != .game { gameChosen = true }
        stepsForward = target > step
        // Směr se musí vykreslit dřív než změna kroku, jinak odjíždějící stránka použije starý přechod.
        Task { @MainActor in
            withAnimation(stepMotion) { step = target }
        }
    }

    private func pickGame(_ mode: GameMode) {
        withAnimation(motion) {
            draft.config.mode = mode
            if mode != .x01 { replaceGhostWithBotIfNeeded() }
        }
        if step == .game { goTo(.players) }
    }

    /// Hotová sestava jde rovnou na poslední krok. Ukazatel nahoře vede zpátky.
    private func loadAndReview(_ setup: SetupDraft) {
        load(setup)
        goTo(flow.last ?? .players)
    }

    private var showsStepBack: Bool { step != .game && step != entryStep }

    /// Převezme celou sestavu (minulou nebo předvolbu) a zahodí rozpracovaný start.
    private func load(_ setup: SetupDraft) {
        draft = setup
        scoreText = "\(setup.config.startingScore)"
        scoreExact = !presetScores.contains(setup.config.startingScore)
        limitCustom = false
        showHandicap = setup.seats.contains { !($0.handicap?.isEmpty ?? true) }
        handicapFocus = nil
        opening = nil
        pickedStarter = nil
        bullWinner = nil
        coinWinner = nil
    }

    private var gamePicker: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 6) {
                Eyebrow(text: "Krok 1 ze \(flow.count)")
                Text("Co si zahrajete?")
                    .font(AppFont.display(34))
                Text("Vyber hru. Hráče a pravidla nastavíš v dalším kroku.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if startsWithGame, !isOnline, let last = store.lastSetup {
                lastSetupCard(last)
            }

            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                ForEach(GameMode.allCases) { mode in
                    gameCard(mode)
                }
            }

            if !isOnline, !store.presets.isEmpty {
                presetList
            }

            Label(
                isOnline ? "Soupeř se připojí kódem lobby." : "Hra a všechny předvolby fungují offline.",
                systemImage: isOnline ? "person.2" : "wifi.slash"
            )
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
        }
        .sensoryFeedback(.selection, trigger: draft.config.mode)
    }

    private func gameCard(_ mode: GameMode) -> some View {
        let current = gameChosen && draft.config.mode == mode
        let shape = RoundedRectangle(cornerRadius: 26, style: .continuous)
        return Button { pickGame(mode) } label: {
            VStack(alignment: .leading, spacing: 4) {
                Image(systemName: mode.symbol)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(width: 46, height: 46)
                    .background(.white.opacity(0.2), in: Circle())
                Spacer(minLength: 18)
                Text(mode.shortTitle)
                    .font(AppFont.title(24))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(modeTagline(mode))
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.white.opacity(0.88))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(16)
            .frame(maxWidth: .infinity, minHeight: 186, alignment: .topLeading)
            .background {
                ZStack(alignment: .bottomTrailing) {
                    LinearGradient(colors: mode.tileColors, startPoint: .topLeading, endPoint: .bottomTrailing)
                    Image(systemName: mode.symbol)
                        .font(.system(size: 118, weight: .bold))
                        .foregroundStyle(.white.opacity(0.12))
                        .offset(x: 30, y: 28)
                }
            }
            .clipShape(shape)
            .overlay(shape.strokeBorder(current ? Theme.brand : .white.opacity(0.1), lineWidth: current ? 3 : 1))
            .contentShape(shape)
        }
        .buttonStyle(PressScale())
        .overlay(alignment: .topTrailing) {
            Button { modeInfo = mode } label: {
                Image(systemName: current ? "checkmark.circle.fill" : "info.circle")
                    .font(.title3.weight(.semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(current ? Theme.brand : .white.opacity(0.9))
                    .frame(width: 44, height: 44)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .padding(6)
            .accessibilityLabel("Jak se hraje \(mode.shortTitle)")
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(mode.shortTitle). \(modeTagline(mode))")
        .accessibilityAddTraits(current ? .isSelected : [])
    }

    private func modeTagline(_ mode: GameMode) -> String {
        switch mode {
        case .x01: return "Ze startu přesně na nulu"
        case .cricket: return "Zavři čísla, sbírej body"
        case .aroundClock: return "Od jedničky až po bull"
        case .countUp: return "Co nejvíc bodů za kola"
        }
    }

    private func lastSetupCard(_ last: SetupDraft) -> some View {
        Button {
            loadAndReview(last)
        } label: {
            HStack(spacing: 14) {
                Image(systemName: "arrow.counterclockwise")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(Theme.onAccent)
                    .frame(width: 46, height: 46)
                    .background(Theme.accentFill, in: Circle())
                VStack(alignment: .leading, spacing: 4) {
                    Text("Jako minule · \(last.config.mode.shortTitle)")
                        .font(.headline)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text(last.config.summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    lineup(last)
                        .padding(.top, 2)
                }
                Spacer(minLength: 4)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.tertiary)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .setupCard()
            .contentShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        }
        .buttonStyle(PressScale())
        .accessibilityHint("Otevře nastavení se stejnými hráči a pravidly")
    }

    /// Překrývající se avatary sestavy.
    private func lineup(_ setup: SetupDraft) -> some View {
        HStack(spacing: -8) {
            ForEach(Array(setup.seats.prefix(4).enumerated()), id: \.element.id) { index, seat in
                let me = setup.includesMe && index == 0
                let bot = seat.isBot && !me
                Avatar(
                    name: me ? (store.profile?.name ?? "Já") : (seat.name.isEmpty ? "?" : seat.name),
                    bot: bot,
                    size: 26,
                    photo: me || seat.ghostSeat ? store.profile?.photoJPEG : seat.friendID.flatMap { store.photo(for: $0) },
                    asset: bot ? BotLevel.get(seat.level).photo : nil
                )
                .overlay(Circle().strokeBorder(Theme.card, lineWidth: 2))
            }
        }
        .accessibilityHidden(true)
    }

    private var presetList: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Tvoje předvolby")
                .font(.title3.weight(.bold))
            VStack(spacing: 0) {
                ForEach(Array(store.presets.enumerated()), id: \.element.id) { index, preset in
                    if index > 0 { Divider().padding(.leading, 70) }
                    Button {
                        loadAndReview(preset.setup)
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: preset.setup.config.mode.symbol)
                                .font(.subheadline.weight(.bold))
                                .foregroundStyle(.white)
                                .frame(width: 42, height: 42)
                                .background(
                                    LinearGradient(colors: preset.setup.config.mode.tileColors, startPoint: .topLeading, endPoint: .bottomTrailing),
                                    in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                                )
                            VStack(alignment: .leading, spacing: 3) {
                                Text(preset.name)
                                    .font(.headline)
                                    .foregroundStyle(.primary)
                                    .lineLimit(1)
                                Text(preset.setup.config.summary)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            Spacer(minLength: 4)
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(.tertiary)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button("Odstranit předvolbu", systemImage: "trash", role: .destructive) {
                            store.deletePreset(preset.id)
                        }
                    }
                }
            }
            .setupCard()
        }
    }

    // MARK: Další kroky

    @ViewBuilder
    private func page(for step: SetupStep) -> some View {
        switch step {
        case .game:
            gamePicker
        case .players:
            rosterStep
        case .rules:
            VStack(alignment: .leading, spacing: 16) {
                rulesStep
                presetBlock
            }
        case .opening:
            VStack(alignment: .leading, spacing: 16) {
                openingStep
                matchSummary
            }
        }
    }

    /// Ukazatel průvodce nad obsahem. Hotové kroky jdou klepnutím otevřít znovu.
    private var stepProgress: some View {
        let mode = draft.config.mode
        let current = flow.firstIndex(of: step) ?? 0
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Button { goTo(.game) } label: {
                    HStack(spacing: 6) {
                        Image(systemName: mode.symbol)
                            .font(.caption.weight(.bold))
                        Text(mode.shortTitle)
                            .font(.subheadline.weight(.bold))
                            .lineLimit(1)
                        Image(systemName: "chevron.down")
                            .font(.caption2.weight(.heavy))
                            .opacity(0.8)
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .frame(minHeight: 32)
                    .background(
                        LinearGradient(colors: mode.tileColors, startPoint: .topLeading, endPoint: .bottomTrailing),
                        in: Capsule()
                    )
                    .contentShape(Capsule())
                }
                .buttonStyle(PressScale())
                .accessibilityLabel("Hra \(mode.shortTitle). Změnit hru")
                Spacer(minLength: 8)
                Text("Krok \(current + 1) ze \(flow.count)")
                    .font(.caption.weight(.bold).monospacedDigit())
                    .foregroundStyle(.secondary)
                    .contentTransition(.numericText(value: Double(current)))
            }
            HStack(spacing: 6) {
                ForEach(Array(flow.enumerated()), id: \.element) { index, item in
                    let done = index < current
                    let active = index == current
                    Button { goTo(item) } label: {
                        VStack(alignment: .leading, spacing: 5) {
                            Capsule()
                                .fill(index <= current ? Theme.accentFill : Color.primary.opacity(0.12))
                                .frame(height: 5)
                            Text(item.title)
                                .font(.caption2.weight(active ? .heavy : .semibold))
                                .foregroundStyle(active ? .primary : .secondary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(!done)
                    .accessibilityLabel("\(item.title)\(active ? ", aktuální krok" : done ? ", hotovo" : "")")
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 6)
        .padding(.bottom, 10)
        .frame(maxWidth: 760)
        .frame(maxWidth: .infinity)
        .background(Theme.background.opacity(0.94))
        .animation(motion, value: step)
    }

    /// Velký nadpis stránky průvodce.
    private func pageHeader<Trailing: View>(_ title: String, hint: String, @ViewBuilder trailing: () -> Trailing) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(AppFont.display(30))
                    .fixedSize(horizontal: false, vertical: true)
                Text(hint)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .contentTransition(.opacity)
            }
            Spacer(minLength: 8)
            trailing()
        }
        .padding(.bottom, 4)
    }

    private func pageHeader(_ title: String, hint: String) -> some View {
        pageHeader(title, hint: hint) { EmptyView() }
    }

    /// Shrnutí před startem: hra, sestava a pravidla na jednom místě.
    private var matchSummary: some View {
        let mode = draft.config.mode
        return VStack(alignment: .leading, spacing: 10) {
            Text("Shrnutí")
                .font(.headline)
            VStack(spacing: 0) {
                summaryRow(icon: mode.symbol, title: mode.shortTitle, detail: draft.config.summary, edit: .rules)
                Divider().padding(.leading, 62)
                summaryRow(
                    icon: "person.2.fill",
                    title: draft.seats.indices.map(seatName).joined(separator: " vs "),
                    detail: draft.includesMe ? "Hraješ i ty" : "Jen zapisuješ",
                    edit: .players
                ) {
                    lineup(draft)
                }
            }
            .setupCard()
        }
    }

    private func summaryRow(icon: String, title: String, detail: String, edit target: SetupStep) -> some View {
        summaryRow(icon: icon, title: title, detail: detail, edit: target) { EmptyView() }
    }

    private func summaryRow<Accessory: View>(icon: String, title: String, detail: String, edit target: SetupStep, @ViewBuilder accessory: () -> Accessory) -> some View {
        Button { goTo(target) } label: {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(Theme.action)
                    .frame(width: 36, height: 36)
                    .background(Theme.action.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 8)
                accessory()
                Text("Upravit")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Theme.action)
            }
            .padding(14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint("Vrátí na krok \(target.title.lowercased())")
    }

    private func replaceGhostWithBotIfNeeded() {
        guard let index = draft.seats.firstIndex(where: \.ghostSeat) else { return }
        draft.seats[index] = SeatDraft(name: "Bot", isBot: true)
        draft.ghostKind = nil
        draft.ghostMatchID = nil
        draft.starter = 0
    }

    private var canAddSeat: Bool {
        if isOnline { return draft.seats.count < 2 }
        return draft.seats.count < 4 && !draft.seats.contains(where: \.ghostSeat)
    }

    private func openBotPicker(seatID: UUID) {
        guard let seat = draft.seats.first(where: { $0.id == seatID }), seat.isBot else { return }
        botPicker = BotPickerTarget(id: seat.id, seatID: seat.id, choice: choice(for: seat))
    }

    private func choice(for seat: SeatDraft) -> BotChoice {
        BotChoice(
            level: seat.level,
            style: seat.botStyle ?? .balanced,
            adaptive: seat.adaptiveBot == true,
            customAverage: seat.customAverage,
            customCheckout: seat.customCheckout,
            customName: seat.customAverage == nil ? nil : seat.name,
            customConsistency: seat.customConsistency,
            customPressure: seat.customPressure,
            customIntelligence: seat.customIntelligence
        )
    }

    private func confirmBot(_ choice: BotChoice, target: BotPickerTarget) {
        withAnimation(motion) {
            if let seatID = target.seatID, let index = draft.seats.firstIndex(where: { $0.id == seatID }) {
                apply(choice, to: &draft.seats[index])
            } else if draft.seats.count < 4 {
                var seat = SeatDraft(name: "Bot", isBot: true)
                apply(choice, to: &seat)
                draft.seats.append(seat)
                draft.starter = 0
            }
        }
    }

    private func apply(_ choice: BotChoice, to seat: inout SeatDraft) {
        seat.isBot = true
        seat.level = choice.level
        seat.botStyle = choice.style
        seat.adaptiveBot = choice.adaptive ? true : nil
        seat.customAverage = choice.customAverage
        seat.customCheckout = choice.customCheckout
        seat.customConsistency = choice.customConsistency
        seat.customPressure = choice.customPressure
        seat.customIntelligence = choice.customIntelligence
        seat.name = choice.isCustom ? (choice.customName ?? "Vlastní") : "Bot"
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
        VStack(alignment: .leading, spacing: 12) {
            pageHeader(
                "Kdo bude hrát?",
                hint: isOnline
                    ? "Ty a jeden soupeř. Bota ani ghosta online nevezmeš."
                    : isSoloTraining
                    ? "Jsi tu sám. Přidej soupeře, nebo jdi trénovat."
                    : "Kamarád, bot, nebo v X01 ghost."
            ) {
                Text("\(draft.seats.count)/\(isOnline ? 2 : 4)")
                    .font(.caption.weight(.bold).monospacedDigit())
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .background(Color.primary.opacity(0.08), in: Capsule())
                    .contentTransition(.numericText(value: Double(draft.seats.count)))
            }

            lineupGrid

            if canAddSeat {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Přidat soupeře")
                        .font(.headline)
                        .padding(.top, 6)
                    HStack(spacing: 10) {
                        opponentOption("Kamarád", detail: isOnline ? "Ze seznamu přátel, nebo až v lobby" : "Ze seznamu přátel", icon: "person.fill", tint: GameMode.aroundClock.tileColors) {
                            openFriendPicker()
                        }
                        if !isOnline {
                            opponentOption("Bot", detail: "Od nováčka po profíka", icon: "cpu", tint: GameMode.cricket.tileColors) {
                                addBot()
                            }
                            if draft.config.mode == .x01 {
                                opponentOption("Ghost", detail: "Proti svému výkonu", icon: "person.fill.viewfinder", tint: GameMode.countUp.tileColors) {
                                    openGhostPicker(adding: true)
                                }
                            }
                        }
                    }
                }
                .transition(.opacity)
            } else {
                Label(
                    isOnline
                        ? "Online je jeden na jednoho."
                        : draft.seats.contains(where: \.ghostSeat) ? "Ghost se hraje jen jeden na jednoho." : "Sestava je plná. Pro dalšího hráče někoho odeber.",
                    systemImage: "info.circle"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            if !isOnline {
                scoreOnlyCard
                    .padding(.top, 6)
            }
        }
        .animation(motion, value: draft.seats.count)
        .animation(motion, value: canAddSeat)
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
                initial: target.choice,
                title: target.seatID == nil ? "Přidat bota" : "Změnit bota",
                confirmTitle: target.seatID == nil ? "Přidat bota" : "Potvrdit",
                adaptiveEnabled: store.data.adaptiveAI != false,
                reading: adaptiveReading
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

    // MARK: Sestava

    /// Karty hráčů vedle sebe. Lichý počet doplní karta volného místa, dva hráči dostanou VS.
    private var lineupGrid: some View {
        let showsOpenSeat = canAddSeat && draft.seats.count % 2 == 1
        let cells = draft.seats.count + (showsOpenSeat ? 1 : 0)
        return LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
            ForEach(draft.seats) { seat in
                if let index = draft.seats.firstIndex(where: { $0.id == seat.id }) {
                    seatTile(index)
                        .transition(.scale(scale: 0.9).combined(with: .opacity))
                }
            }
            if showsOpenSeat {
                openSeatTile
                    .transition(.opacity)
            }
        }
        .overlay {
            if cells == 2 {
                Text("VS")
                    .font(.system(size: 15, weight: .black, design: .rounded))
                    .foregroundStyle(Theme.onAccent)
                    .frame(width: 44, height: 44)
                    .background(Theme.accentFill, in: Circle())
                    .overlay(Circle().strokeBorder(Theme.background, lineWidth: 4))
                    .shadow(color: .black.opacity(0.18), radius: 6, y: 2)
                    .accessibilityHidden(true)
                    .transition(.scale.combined(with: .opacity))
            }
        }
    }

    private struct SeatFace {
        var badge: String
        var detail: String
        var action: (() -> Void)?
        var accessibility: String
        var hint: String?
    }

    private func seatFace(_ index: Int) -> SeatFace {
        let seat = draft.seats[index]
        if isMe(index) {
            return SeatFace(badge: "TY", detail: "Statistiky se ukládají", action: nil, accessibility: "\(seatName(index)), ty")
        }
        if seat.ghostSeat {
            let offer = ghostOffer
            let detail = offer.map { item in
                if let note = item.styleNote, !note.isEmpty { return note }
                return "\(item.kind.title) · průměr \(item.averageText)"
            } ?? "Klepni a vyber ghosta"
            return SeatFace(
                badge: "GHOST",
                detail: detail,
                action: { openGhostPicker(adding: false) },
                accessibility: offer.map { "Ghost, \($0.kind.title), průměr \($0.averageText)" } ?? "Ghost",
                hint: "Otevře výběr ghosta"
            )
        }
        if seat.isBot {
            let resolved = resolvedBot(seat)
            let badge = resolved.isCustom ? "VLASTNÍ BOT" : resolved.adaptive ? "ADAPTIVE · LV \(resolved.level)" : "BOT · LV \(resolved.level)"
            return SeatFace(
                badge: badge,
                detail: botDetailLine(resolved),
                action: { openBotPicker(seatID: seat.id) },
                accessibility: botAccessibility(index, resolved: resolved),
                hint: "Otevře výběr bota"
            )
        }
        if seat.friendID != nil {
            let housemate = store.housemates.contains { $0.id == seat.friendID }
            return SeatFace(
                badge: housemate ? "PROFIL" : "KAMARÁD",
                detail: housemate ? "Profil na tomto telefonu" : "Klepni pro změnu",
                action: { openFriendPicker(replacing: seat.id) },
                accessibility: "\(seat.name), kamarád",
                hint: "Otevře výběr kamaráda"
            )
        }
        return SeatFace(badge: "HOST", detail: "Jméno se uloží na příště", action: nil, accessibility: "Host")
    }

    private var ghostOffer: GhostOffer? {
        draft.ghostKind.flatMap {
            store.ghostOffer($0, startingScore: draft.config.startingScore, outRule: draft.config.outRule, matchID: draft.ghostMatchID)
        }
    }

    @ViewBuilder
    private func seatPortrait(_ index: Int) -> some View {
        let seat = draft.seats[index]
        let color = Theme.playerColor(index)
        if seat.isBot && !isMe(index) {
            let level = resolvedBot(seat).level
            BotPortrait(level: level, size: 76, showsLevelBadge: false)
                .id(BotLevel.get(level).photo)
        } else if seat.ghostSeat {
            ZStack(alignment: .bottomTrailing) {
                if let photo = store.profile?.photoJPEG {
                    Avatar(name: "Ghost", size: 70, photo: photo)
                        .opacity(0.55)
                        .grayscale(0.6)
                } else {
                    Image(systemName: "person.fill.viewfinder")
                        .font(.system(size: 28, weight: .semibold))
                        .foregroundStyle(Theme.action)
                        .frame(width: 70, height: 70)
                        .background(Theme.action.opacity(0.12), in: Circle())
                }
                Image(systemName: "person.fill.viewfinder")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.black)
                    .frame(width: 24, height: 24)
                    .background(color, in: Circle())
            }
            .playerRing(color)
        } else {
            Avatar(
                name: isMe(index) ? (store.profile?.name ?? "Já") : (seat.name.isEmpty ? "?" : seat.name),
                size: 70,
                photo: seatPhoto(index)
            )
            .playerRing(color)
        }
    }

    private func seatTile(_ index: Int) -> some View {
        let face = seatFace(index)
        let color = Theme.playerColor(index)
        return Group {
            if let action = face.action {
                Button(action: action) { seatTileBody(index, face: face, color: color) }
                    .buttonStyle(PressScale())
                    .accessibilityLabel(face.accessibility)
                    .accessibilityHint(face.hint ?? "")
            } else {
                seatTileBody(index, face: face, color: color)
            }
        }
        .overlay(alignment: .topLeading) {
            Text("\(index + 1)")
                .font(.caption.weight(.heavy).monospacedDigit())
                .foregroundStyle(.black)
                .frame(width: 24, height: 24)
                .background(color, in: Circle())
                .padding(10)
                .accessibilityHidden(true)
        }
        .overlay(alignment: .topTrailing) {
            if !isMe(index) {
                Button { removeSeat(index) } label: {
                    Image(systemName: "xmark")
                        .font(.caption2.weight(.heavy))
                        .foregroundStyle(.secondary)
                        .frame(width: 26, height: 26)
                        .background(Color.primary.opacity(0.08), in: Circle())
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Odebrat \(seatName(index))")
            }
        }
        .sensoryFeedback(.selection, trigger: draft.seats[index].isBot ? resolvedBot(draft.seats[index]).level : 0)
    }

    private func seatTileBody(_ index: Int, face: SeatFace, color: Color) -> some View {
        let seat = draft.seats[index]
        let guest = !isMe(index) && !seat.isBot && !seat.ghostSeat && seat.friendID == nil
        let shape = RoundedRectangle(cornerRadius: 26, style: .continuous)
        return VStack(spacing: 10) {
            seatPortrait(index)
            VStack(spacing: 6) {
                if guest {
                    TextField("Jméno", text: $draft.seats[index].name)
                        .font(.headline)
                        .multilineTextAlignment(.center)
                        .textInputAutocapitalization(.words)
                        .autocorrectionDisabled()
                        .focused($focusedGuest, equals: seat.id)
                        .submitLabel(.done)
                        .padding(.horizontal, 10)
                        .frame(minHeight: 34)
                        .background(Color.primary.opacity(0.06), in: Capsule())
                } else {
                    Text(seatName(index))
                        .font(.headline)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                Text(face.badge)
                    .font(.caption2.weight(.heavy))
                    .foregroundStyle(.black)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(color, in: Capsule())
                    .contentTransition(.opacity)
                Text(face.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 22)
        .padding(.bottom, 16)
        .frame(maxWidth: .infinity, minHeight: 218, alignment: .top)
        .background {
            ZStack {
                Theme.card
                LinearGradient(colors: [color.opacity(0.3), color.opacity(0)], startPoint: .top, endPoint: .center)
            }
        }
        .clipShape(shape)
        .overlay(shape.strokeBorder(color.opacity(0.6), lineWidth: 1.5))
        .contentShape(shape)
    }

    /// Volné místo v sestavě. Nabídne stejné typy soupeřů jako karty pod mřížkou.
    private var openSeatTile: some View {
        let shape = RoundedRectangle(cornerRadius: 26, style: .continuous)
        return Menu {
            Button("Kamarád", systemImage: "person.fill") { openFriendPicker() }
            if !isOnline {
                Button("Bot", systemImage: "cpu") { addBot() }
                if draft.config.mode == .x01 {
                    Button("Ghost", systemImage: "person.fill.viewfinder") { openGhostPicker(adding: true) }
                }
            }
        } label: {
            VStack(spacing: 12) {
                Image(systemName: "plus")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(Theme.action)
                    .frame(width: 70, height: 70)
                    .background(Theme.action.opacity(0.1), in: Circle())
                VStack(spacing: 4) {
                    Text("Soupeř")
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Text("Klepni a přidej")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.top, 22)
            .frame(maxWidth: .infinity, minHeight: 218, alignment: .top)
            .background(Color.primary.opacity(0.03), in: shape)
            .overlay(shape.strokeBorder(Color.primary.opacity(0.22), style: StrokeStyle(lineWidth: 1.5, dash: [6, 5])))
            .contentShape(shape)
        }
        .buttonStyle(PressScale())
        .accessibilityLabel("Přidat soupeře")
    }

    private func opponentOption(_ title: String, detail: String, icon: String, tint: [Color], action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                Image(systemName: icon)
                    .font(.headline.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(width: 42, height: 42)
                    .background(LinearGradient(colors: tint, startPoint: .topLeading, endPoint: .bottomTrailing), in: Circle())
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text(detail)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .padding(12)
            .frame(maxWidth: .infinity, minHeight: 118, alignment: .topLeading)
            .setupCard()
            .contentShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        }
        .buttonStyle(PressScale())
        .accessibilityLabel("Přidat: \(title)")
        .accessibilityHint(detail)
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

    private var friendPickerSlots: Int {
        if isOnline { return 1 }
        return max(1, min(4, 4 - draft.seats.count))
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
        .background(scoring ? Theme.action.opacity(0.08) : Theme.card, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(scoring ? Theme.action.opacity(0.7) : Theme.stroke, lineWidth: scoring ? 1.5 : 1)
        )
        .animation(motion, value: scoring)
        .accessibilityHint(scoring ? "Vypni, pokud chceš hrát" : "Zapni, pokud jen zapisuješ")
    }

    /// Barva místa v sestavě. Sólo hra barvy nepotřebuje.
    private func seatColor(_ index: Int) -> Color? {
        draft.seats.count > 1 ? Theme.playerColor(index) : nil
    }

    private func botPersona(_ index: Int) -> String {
        draft.seats[index].botTitle(
            earlier: draft.seats[..<index],
            adaptiveAllowed: store.data.adaptiveAI != false,
            suggestedLevel: suggestedBotLevel
        )
    }

    private func botDetailLine(_ resolved: ResolvedBot) -> String {
        if let average = resolved.average, let checkout = resolved.checkout {
            let avg = average.formatted(.number.precision(.fractionLength(1)))
            let percent = Int((checkout * 100).rounded())
            return "Průměr \(avg) · double \(percent) % · \(resolved.style.title)"
        }
        let info = BotLevel.get(resolved.level)
        return "Průměr \(info.averageText) · \(resolved.style.title)"
    }

    private func botAccessibility(_ index: Int, resolved: ResolvedBot) -> String {
        if resolved.isCustom {
            return "\(botPersona(index)), \(botDetailLine(resolved))"
        }
        return "\(botPersona(index)), úroveň \(resolved.level)"
    }

    private var suggestedBotLevel: Int { adaptiveReading.recommendedLevel }

    private var adaptiveReading: AdaptiveReading {
        guard let id = store.profile?.id else {
            return AdaptiveBotEngine.reading(matches: [], playerID: UUID())
        }
        return AdaptiveBotEngine.reading(matches: store.matches, playerID: id)
    }

    /// Úroveň, se kterou bot opravdu nastoupí. Adaptive se přepočítá z historie a v zápasu už zůstane.
    private func resolvedBot(_ seat: SeatDraft) -> ResolvedBot {
        seat.resolve(adaptiveAllowed: store.data.adaptiveAI != false, suggestedLevel: suggestedBotLevel)
    }

    private func isMe(_ index: Int) -> Bool { draft.includesMe && index == 0 }

    private func addBot() {
        guard draft.seats.count < 4 else { return }
        botPicker = BotPickerTarget(id: UUID(), seatID: nil, choice: BotChoice(level: 3))
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

    private var onlineRulesHint: String {
        switch draft.config.mode {
        case .x01: return "Stejně jako lokální X01. Online se hraje bez double in."
        case .cricket: return "Stejný cricket jako v lokální hře. Soupeř se připojí kódem lobby."
        case .aroundClock: return "Stejné kolo hodin jako v lokální hře. Soupeř se připojí kódem lobby."
        case .countUp: return "Stejný Count Up jako v lokální hře. Soupeř se připojí kódem lobby."
        }
    }

    private var rulesStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            pageHeader(
                "Jak se bude hrát?",
                hint: isOnline ? onlineRulesHint : "Výchozí nastavení stačí. Změň jen to, co chceš jinak."
            )
            if isOnline {
                VStack(spacing: 0) {
                    ruleRow("Lobby", icon: onlinePublic ? "globe" : "lock.fill", value: onlinePublic ? "Veřejné" : "Uzavřené") { onlineVisibilityGroup }
                }
                .setupCard()
            }
            VStack(spacing: 0) {
                switch draft.config.mode {
                case .x01:
                    ruleRow("Start", icon: "flag.fill", value: "\(draft.config.startingScore)") { scoreGroup }
                    ruleDivider
                    ruleRow("Zavření", icon: "checkmark.seal.fill") { outGroup }
                    ruleDivider
                    if !isOnline {
                        ruleRow("Otevření", icon: "lock.open.fill") { inGroup }
                        ruleDivider
                    }
                    ruleRow("Délka zápasu", icon: "trophy.fill") { lengthGroup }
                    if !isOnline {
                        ruleDivider
                        ruleRow("Limit šipek", icon: "timer", value: limitValue) { limitGroup }
                    }
                case .cricket:
                    ruleRow("Body", icon: "plus.forwardslash.minus") { cricketScoringGroup }
                    ruleDivider
                    ruleRow("Čísla", icon: "number", value: cricketNumbersValue) { cricketNumbersGroup }
                    ruleDivider
                    ruleRow("Délka zápasu", icon: "trophy.fill") { lengthGroup }
                case .countUp:
                    ruleRow("Počet kol", icon: "chart.bar.fill", value: "\(draft.config.settings.countUpRounds * 3) šipek") { countUpGroup }
                case .aroundClock:
                    ruleRow("Zásah", icon: "clock.fill") { clockGroup }
                }
            }
            .setupCard()
            if !isOnline, draft.config.mode == .x01, draft.seats.count > 1 {
                handicapCardSection
            }
        }
        .animation(sectionMotion, value: showHandicap)
    }

    private var ruleDivider: some View {
        Divider().padding(.leading, 56)
    }

    private func ruleRow<Content: View>(_ title: String, icon: String, value: String? = nil, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(Theme.action)
                    .frame(width: 30, height: 30)
                    .background(Theme.action.opacity(0.12), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                    .accessibilityHidden(true)
                Text(title)
                    .font(.headline)
                Spacer(minLength: 8)
                if let value {
                    Text(value)
                        .font(.subheadline.weight(.bold).monospacedDigit())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .contentTransition(.numericText())
                }
            }
            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func ruleNote(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .contentTransition(.opacity)
    }

    /// Handicap je výjimka. Hodnota je vidět pořád, editor až když ho chceš.
    private var handicapCardSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                hideKeyboard()
                withAnimation(sectionMotion) { showHandicap.toggle() }
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "scalemass.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(showHandicap ? Theme.onAccent : Theme.action)
                        .frame(width: 36, height: 36)
                        .background(showHandicap ? Theme.accentFill : Theme.action.opacity(0.12), in: Circle())
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Handicap")
                            .font(.subheadline.weight(.bold))
                        Text(handicapSummary)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.down")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(showHandicap ? 180 : 0))
                }
                .padding(16)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityValue(handicapSummary)
            .accessibilityHint(showHandicap ? "Sbalí handicap" : "Rozbalí handicap")
            if showHandicap {
                handicapGroup
                    .padding(.horizontal, 16)
                    .padding(.bottom, 16)
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(showHandicap ? Theme.action.opacity(0.45) : Theme.stroke, lineWidth: showHandicap ? 1.5 : 1)
        )
    }

    private var presetBlock: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle(isOn: $savePreset.animation(motion)) {
                HStack(spacing: 12) {
                    Image(systemName: savePreset ? "bookmark.fill" : "bookmark")
                        .font(.body.weight(.bold))
                        .foregroundStyle(savePreset ? Theme.onAccent : .secondary)
                        .frame(width: 40, height: 40)
                        .background(
                            savePreset ? Theme.accentFill : Color.primary.opacity(0.08),
                            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                        )
                        .contentTransition(.symbolEffect(.replace))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Uložit jako předvolbu")
                            .font(.subheadline.weight(.semibold))
                        Text("Najdeš ji příště hned na výběru hry")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .tint(Theme.accentFill)
            if savePreset {
                TextField("Název předvolby", text: $presetName)
                    .font(.headline)
                    .padding(.horizontal, 14)
                    .frame(minHeight: 46)
                    .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .transition(.opacity)
            }
        }
        .padding(.leading, 12)
        .padding(.trailing, 14)
        .padding(.vertical, 12)
        .setupCard()
    }


    private func hideKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }

    private var scoreGroup: some View {
        VStack(alignment: .leading, spacing: 12) {
            OptionSwitcher(
                options: presetScores.map { (id: $0, title: "\($0)") } + [(id: -1, title: "Vlastní")],
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
    }

    private var outGroup: some View {
        VStack(alignment: .leading, spacing: 10) {
            OptionSwitcher(
                options: OutRule.allCases.map { (id: $0, title: $0.shortTitle) },
                selection: draft.config.outRule
            ) { rule in
                withAnimation(motion) { draft.config.outRule = rule }
            }
            ruleNote(draft.config.outRule.detail)
        }
    }

    private var inGroup: some View {
        VStack(alignment: .leading, spacing: 10) {
            OptionSwitcher(
                options: [(id: false, title: "Hned"), (id: true, title: "Double in")],
                selection: draft.config.doubleIn
            ) { value in
                withAnimation(motion) { draft.config.doubleIn = value }
            }
            ruleNote(draft.config.doubleIn ? "Body se začnou počítat až od prvního doublu." : "Počítá se každý zásah od první šipky.")
        }
    }

    private var limitValue: String {
        guard let limit = draft.config.settings.dartLimit else { return "Vypnuto" }
        return "\(limit) šipek"
    }

    private var usingCustomLimit: Bool {
        guard let limit = draft.config.settings.dartLimit else { return false }
        return limitCustom || !MatchOptions.dartLimitChoices.contains(limit)
    }

    private var limitGroup: some View {
        VStack(alignment: .leading, spacing: 12) {
            OptionSwitcher(
                options: [(id: 0, title: "Vypnuto")]
                    + MatchOptions.dartLimitChoices.map { (id: $0, title: "\($0)") }
                    + [(id: -1, title: "Vlastní")],
                selection: usingCustomLimit ? -1 : draft.config.settings.dartLimit ?? 0
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
                .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .accessibilityValue("\(limit / 3) kol, \(limit) šipek")
            }
            ruleNote(draft.config.settings.dartLimit.map { "Když leg nikdo nezavře do \($0) šipek na hráče, rozhodne rozhoz na střed. Bližší šipka bere leg." }
                 ?? "Leg se hraje, dokud ho někdo nezavře.")
        }
    }

    private var cricketNumbersValue: String {
        let numbers = draft.config.settings.activeCricketNumbers
        return numbers == MatchOptions.standardCricketNumbers ? "Klasika" : "\(numbers.count) polí"
    }

    private var cricketScoringGroup: some View {
        VStack(alignment: .leading, spacing: 10) {
            OptionSwitcher(
                options: [(id: false, title: "S body"), (id: true, title: "Bez bodů")],
                selection: draft.config.settings.cricketNoScore
            ) { value in
                withAnimation(motion) { options.wrappedValue.cricketNoScore = value }
            }
            ruleNote(draft.config.settings.cricketNoScore
                     ? "Vyhrává, kdo první zavře všechna čísla."
                     : "Zásahy do zavřeného čísla přičítají body, dokud ho soupeř nezavře.")
        }
    }

    private var cricketNumbersGroup: some View {
        let selected = draft.config.settings.activeCricketNumbers
        return VStack(alignment: .leading, spacing: 12) {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 7), spacing: 6) {
                ForEach(Array(1...20) + [25], id: \.self) { number in
                    let on = selected.contains(number)
                    let last = on && selected.count == 1
                    Button {
                        toggleCricketNumber(number)
                    } label: {
                        Text(number == 25 ? "B" : "\(number)")
                            .font(.system(.subheadline, design: .rounded, weight: .bold))
                            .monospacedDigit()
                            .frame(maxWidth: .infinity, minHeight: 42)
                            .foregroundStyle(on ? Color.black : Color.primary)
                            .background(on ? Theme.brand : Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .disabled(last)
                    .accessibilityLabel(number == 25 ? "Bull" : "\(number)")
                    .accessibilityAddTraits(on ? .isSelected : [])
                }
            }
            .sensoryFeedback(.selection, trigger: selected)
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                ruleNote("Ve hře se ukážou jen zapnutá čísla.")
                Spacer(minLength: 8)
                if selected != MatchOptions.standardCricketNumbers {
                    Button("Klasika 20–15 a bull") {
                        withAnimation(motion) { options.wrappedValue.cricketNumbers = nil }
                    }
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Theme.action)
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func toggleCricketNumber(_ number: Int) {
        var selected = Set(draft.config.settings.activeCricketNumbers)
        if selected.contains(number) {
            guard selected.count > 1 else { return }
            selected.remove(number)
        } else {
            selected.insert(number)
        }
        let ordered = MatchOptions.orderedCricketNumbers(Array(selected))
        withAnimation(motion) {
            options.wrappedValue.cricketNumbers = ordered == MatchOptions.standardCricketNumbers ? nil : ordered
        }
    }

    private var countUpGroup: some View {
        VStack(alignment: .leading, spacing: 10) {
            OptionSwitcher(options: roundChoices.map { (id: $0, title: "\($0) kol") }, selection: draft.config.settings.countUpRounds) { rounds in
                withAnimation(motion) { options.wrappedValue.countUpRounds = rounds }
            }
            ruleNote("Po posledním kole vyhrává nejvyšší součet.")
        }
    }

    private var clockGroup: some View {
        VStack(alignment: .leading, spacing: 10) {
            OptionSwitcher(
                options: ClockStyle.allCases.map { style in
                    (id: style, title: style == .any ? "Cokoli" : style == .doubles ? "Doubly" : "Triply")
                },
                selection: draft.config.settings.clockStyle
            ) { style in
                withAnimation(motion) { options.wrappedValue.clockStyle = style }
            }
            ruleNote("\(draft.config.settings.clockStyle.title). Postupně 1–20 a nakonec bull. U doublů a triplů se bull bere jen jako 50.")
        }
    }

    private var onlineVisibilityGroup: some View {
        VStack(alignment: .leading, spacing: 10) {
            OptionSwitcher(
                options: [(id: true, title: "Veřejné"), (id: false, title: "Uzavřené")],
                selection: onlinePublic
            ) { open in
                withAnimation(motion) { onlinePublic = open }
            }
            ruleNote(onlinePublic
                     ? "Lobby uvidí všichni v seznamu a můžou se rovnou připojit."
                     : "V seznamu není. Vstoupí jen ten, kdo zná kód, nebo kamarád z pozvánky.")
        }
    }

    private var lengthGroup: some View {
        let bestOf = draft.config.format == .bestOf
        let stepSize = bestOf ? 2 : 1
        let legLimit = bestOf ? 15 : 11
        return VStack(alignment: .leading, spacing: 12) {
            OptionSwitcher(
                options: [(id: MatchFormat.firstTo, title: "First to"), (id: MatchFormat.bestOf, title: "Best of")],
                selection: draft.config.format
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
            ruleNote(draft.config.lengthDetail)
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

    private var openingHint: String {
        switch opening {
        case .random: return "Při startu se vylosuje, kdo hází první."
        case .pick: return pickedStarter == nil ? "Na další obrazovce vybereš hráče." : "Vybraný hráč hází první leg."
        case .bull: return "Každý hodí na střed. Blíž ke středu vyhrává."
        case nil: return "Vyber způsob. Bez toho se zápas nespustí."
        }
    }

    private var openingStep: some View {
        let waiting = opening == nil
        return VStack(alignment: .leading, spacing: 12) {
            pageHeader("Kdo začíná?", hint: openingHint) {
                if let opening {
                    Button { openingInfo = opening } label: {
                        Image(systemName: "info.circle")
                            .font(.title3)
                            .frame(width: 44, height: 32)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Jak funguje start")
                }
            }
            VStack(spacing: 10) {
                HStack(spacing: 8) {
                    openingTile("Náhodně", detail: "Los", symbol: "dice.fill", mode: .random)
                    openingTile("Vybrat", detail: "Určíš sám", symbol: "hand.point.up.fill", mode: .pick)
                    openingTile("Rozhoz", detail: "Hod na střed", symbol: "smallcircle.filled.circle", mode: .bull)
                }
                if opening == .pick, let starter = pickedStarter, draft.seats.indices.contains(starter) {
                    openingResult("Začíná \(seatName(starter))", action: "Změnit") { showStarterPicker = true }
                }
                if opening == .bull, let bullWinner {
                    openingResult("Začíná \(seatName(bullWinner))", action: "Hodit znovu") { showBullOff = true }
                }
            }
            .padding(10)
            .setupCard(highlight: waiting)
        }
    }

    private func openingTile(_ title: String, detail: String, symbol: String, mode: Opening) -> some View {
        let selected = opening == mode
        let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)
        return Button { applyOpening(mode) } label: {
            VStack(spacing: 6) {
                Image(systemName: symbol)
                    .font(.title3.weight(.semibold))
                    .frame(height: 26)
                Text(title)
                    .font(.subheadline.weight(.bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                Text(detail)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(selected ? Color.black.opacity(0.65) : Color.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .foregroundStyle(selected ? Color.black : Color.primary)
            .frame(maxWidth: .infinity, minHeight: 96)
            .background(selected ? Theme.brand : Color.primary.opacity(0.05), in: shape)
            .contentShape(shape)
        }
        .buttonStyle(PressScale())
        .accessibilityLabel("\(title), \(detail)")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func openingResult(_ title: String, action: String, perform: @escaping () -> Void) -> some View {
        HStack(spacing: 12) {
            Label(title, systemImage: "flag.checkered")
                .font(.subheadline.weight(.bold))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Spacer(minLength: 8)
            Button(action, action: perform)
                .font(.subheadline.weight(.semibold))
                .buttonStyle(.plain)
                .foregroundStyle(Theme.action)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(Theme.brand.opacity(0.16), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
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

    private func commitScore(_ value: Int) {
        draft.config.startingScore = value
        scoreText = "\(value)"
    }

    private func advance() {
        commitScoreFromField()
        hideKeyboard()
        if isOnline {
            guard !onlineSending else { return }
            onlineSending = true
            var setup = draft
            setup.config.doubleIn = false
            setup.config.handicaps = nil
            var options = setup.config.options ?? MatchOptions()
            options.dartLimit = nil
            setup.config.options = options
            for index in setup.seats.indices { setup.seats[index].handicap = nil }
            onlineNotice = nil
            let settings = OnlineLobbySettings(
                config: setup.config,
                isPublic: onlinePublic
            )
            Task {
                await online?.finish(setup, settings)
                onlineSending = false
            }
            return
        }
        if isSoloTraining {
            openSoloTraining = true
            return
        }
        if opening == .random, draft.seats.count > 1 {
            coinLaunched = false
            showCoinToss = true
        } else if store.activeMatch != nil {
            pregameSeen = false
            replace = true
        } else {
            presentPregameOrStart()
        }
    }

    private func commitScoreFromField() {
        if let value = Int(scoreText), (GameConfig.minimumScore...GameConfig.maximumScore).contains(value) {
            draft.config.startingScore = value
        }
        scoreText = "\(draft.config.startingScore)"
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

    /// Obrazovka bilance je mimo `body`, ať ji kompilátor stihne typově ověřit.
    private func pregameCover() -> some View {
        ZStack {
            if pregameLaunched {
                NavigationStack { MatchView() }
                    .transition(.opacity)
            } else if let series = pregameSeries {
                pregameScreen(series)
            }
        }
        .environmentObject(store)
    }

    private func pregameScreen(_ series: HeadToHead) -> some View {
        HeadToHeadPregameView(
            series: series,
            myName: store.profile?.name ?? "Já",
            myPhoto: store.profile?.photoJPEG,
            theirPhoto: pregameOpponentPhoto(series),
            onContinue: finishPregame,
            onCancel: cancelPregame,
            automatic: false
        )
        .transition(.opacity)
    }

    private func cancelPregame() {
        showPregame = false
        pregameLaunched = false
        pregameSeen = false
        pregameSeries = nil
    }

    /// H2H před zápasem, když už je jasné, kdo začíná (výběr hráče i rozhoz).
    private func presentPregameOrStart() {
        ensureFriendIDs()
        if let series = makePregameSeries() {
            pregameSeries = series
            pregameLaunched = false
            pregameSeen = true
            showPregame = true
        } else {
            start()
        }
    }

    private func confirmReplace() {
        if pregameSeen {
            pregameSeen = false
            start()
        } else {
            presentPregameOrStart()
        }
    }

    private func finishPregame() {
        guard makeMatch() else {
            showPregame = false
            pregameLaunched = false
            pregameSeries = nil
            return
        }
        withAnimation(.easeInOut(duration: 0.35)) { pregameLaunched = true }
    }

    private func finishAfterBull() {
        if let active = store.activeMatch, !active.finished {
            showBullOff = false
            showH2HAfterBull = false
            pregameSeries = nil
            pregameSeen = true
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 450_000_000)
                replace = true
            }
        } else if makeMatch() {
            withAnimation(.easeInOut(duration: 0.35)) { bullLaunched = true }
        } else {
            showBullOff = false
            showH2HAfterBull = false
            pregameSeries = nil
        }
    }

    private func finishAfterToss() {
        if let active = store.activeMatch, !active.finished {
            showCoinToss = false
            showH2HAfterToss = false
            pregameSeries = nil
            pregameSeen = true
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
        if series.isGhost { return store.profile?.photoJPEG }
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
                    adaptiveBot: resolved?.adaptive == true ? true : nil,
                    botAverage: resolved?.average,
                    botCheckout: resolved?.checkout,
                    botConsistency: resolved?.consistency,
                    botPressure: resolved?.pressure,
                    botIntelligence: resolved?.intelligence
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
        store.announceMoment(.matchStart)
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
        case .cricket: return "Čísla si vybereš v pravidlech. Výchozí jsou 20, 19, 18, 17, 16, 15 a bull. Každý zásah je jedna značka, triple jsou tři. Tři značky číslo zavřou. Další zásahy na číslo, které soupeř ještě nemá, přičítají body. Vyhrává, kdo zavře všechno a má aspoň tolik bodů jako soupeř."
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

    /// Společná karta nastavení zápasu.
    func setupCard(highlight: Bool = false) -> some View {
        let shape = RoundedRectangle(cornerRadius: 24, style: .continuous)
        return background(Theme.card, in: shape)
            .clipShape(shape)
            .overlay(shape.strokeBorder(highlight ? Theme.brand : Theme.stroke, lineWidth: highlight ? 1.5 : 1))
    }
}

/// Lehké zmenšení při stisku pro velké dlaždice.
private struct PressScale: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.smooth(duration: 0.18), value: configuration.isPressed)
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
