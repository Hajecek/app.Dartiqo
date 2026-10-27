import SwiftUI
import UIKit

private struct CameraHit {
    var dart: Dart
    /// Kde kamera hod viděla (obraz kamery 0…1).
    var point: SIMD2<Double>?
    var corrected = false
}

enum MatchColors {
    static let background = Color(red:0.055,green:0.10,blue:0.08)
    static let coral = Color(red:1,green:0.32,blue:0.20)
    static let amber = Color(red:1,green:0.60,blue:0.10)
    static let ink = Color(red:0.045,green:0.10,blue:0.075)
    static let green = Color(red:0.13,green:0.80,blue:0.49)
    /// Tmavší zelená pod bílým textem na tlačítku Dokončit.
    static let finish = Color(red: 0.05, green: 0.52, blue: 0.31)
    /// Solid tip tile for AI checkout suggestions (contrast on white strip).
    static let aiTip = Color(red: 0.02, green: 0.42, blue: 0.36)
    static let aiTipSoft = Color(red: 0.78, green: 0.95, blue: 0.90)
    /// Setup shot when a finish is impossible — amber, so it doesn't read as a checkout.
    static let setupTip = Color(red: 0.42, green: 0.24, blue: 0.02)
}
private struct LegCeremony: Equatable, Identifiable {
    var id = UUID()
    var winner: Int
    var leg: Int
    var matchFinished: Bool
    var legs: [Int]
    var sets: [Int] = []
    var names: [String]
    var checkoutScore: Int
    var checkoutDarts: [String]
    var isCheckout: Bool
    var legsToWin: Int
    var setsToWin: Int = 1
    /// Kolik teček se má ukázat. U best of je to celé pole, ne jen počet k výhře.
    var legSlots: Int = 0
    var setSlots: Int = 0
    var playsSets: Bool = false
    var setClosed: Bool
    var duration: Double
    var byBullOff = false
    var winnerPhoto: Data? = nil
    var winnerAsset: String? = nil
    /// Tříšipkový průměr profilu v právě dohraném legu. Jen X01, když uživatel házel.
    var userLegAverage: Double? = nil
}
private struct BoardDetailSelection: Identifiable {
    let player: Int
    var id: Int { player }
}

struct MatchView: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var surface = ScoringSurface.grid
    /// `onAppear` může proběhnout vícenásobně — výchozí režim nastavíme jen jednou.
    @State private var didSeedSurface = false
    @State private var multiplier = 1
    @State private var paused = false
    @State private var showLeave = false
    @State private var showLog = false
    @State private var showProgress = false
    @State private var showSettings = false
    @State private var sumText = ""
    @State private var finishPrompt = false
    @State private var bustPrompt = false
    @State private var error: String?
    @State private var revision = UUID()
    @State private var holdDarts: [Dart] = []
    @State private var isHoldingVisit = false
    /// Zruší čekání na dalšího hráče, když se kolo vrátí nebo začne nové.
    @State private var holdGeneration = 0
    @State private var holdSurface: ScoringSurface = .grid
    @State private var holdPlayer: Int?
    @State private var legCeremony: LegCeremony?
    /// Token oslavné animace 180 — `nil` = skrytá.
    @State private var oneEightyFlash: UUID?
    /// Další leg už sedí pod krytím a ceremonie se prolíná pryč.
    @State private var ceremonyLeaving = false
    /// Zavírání už běží — druhé klepnutí nesmí posunout další leg.
    @State private var ceremonyDismissing = false
    /// Horní inset hry, dokud je lišta vidět. Při ceremonii ho držíme, ať se skóre neposune.
    @State private var preservedChromeInset: CGFloat = 0
    @State private var currentChromeInset: CGFloat = 0
    /// Statistiky po konci zápasu jsou připravené, než ceremonie zmizí.
    @State private var resultShown = false
    @State private var boardDetail: BoardDetailSelection?
    @State private var statsPlayer: BoardDetailSelection?
    @State private var boardZoomed = false
    /// 0 = všechny legy, jinak číslo legu.
    @State private var detailLeg: Int? = 0
    @State private var cameraHits: [CameraHit] = []
    @State private var correcting: Int?
    /// Index šipky v aktuálním kole, kterou hráč upravuje.
    @State private var editingDart: Int?
    /// Pauza kola se při otevření opravy zastaví a po zavření bez změny zase naváže.
    @State private var pausedHoldForEdit = false
    @State private var decidingLeg = false
    /// Výběr startéra před rozhodujícím legem (např. 3:3).
    @State private var showDecidingStarter = false
    @State private var leavingHome = false
    /// Začátek právě běžícího úseku hry. Stopky stojí při pauze, mimo hru a na pozadí.
    @State private var clockStart: Date?
    /// Poslední hod, zápis nebo krok ve hře. Po dvou minutách ticha se zápas sám pozastaví.
    @State private var lastActivity = Date()
    private let idlePauseAfter: TimeInterval = 120
    @StateObject private var voice = VoiceScoreListener()
    /// Šipky po jedné, nebo součet celého kola.
    @State private var voiceMode: VoiceScoreMode = .darts
    @State private var showMatchXP = false
    @State private var showOnlineLeave = false
    @ObservedObject private var link: OnlineMatchLink
    /// Volá se po konci online zápasu, když se hráč vrací do seznamu lobby.
    private var onOnlineExit: () -> Void
    /// Zrušení online zápasu. Bez vlastní akce se chová jako návrat do lobby.
    private var onOnlineCancel: () -> Void

    init(online: OnlineMatchLink? = nil, onOnlineExit: @escaping () -> Void = {}, onOnlineCancel: (() -> Void)? = nil) {
        _link = ObservedObject(wrappedValue: online ?? .local)
        self.onOnlineExit = onOnlineExit
        self.onOnlineCancel = onOnlineCancel ?? onOnlineExit
    }

    /// Online zápas drží propojení se serverem. Lokální hra zůstává v `AppStore`.
    private var activeMatch: Match? {
        get { link.isOnline ? link.game : store.activeMatch }
        nonmutating set {
            if link.isOnline { link.propose(newValue) } else { store.activeMatch = newValue }
        }
    }

    var body: some View { clockTracking(screen) }
    private var screen: some View {
        matchPrompts
            .sheet(isPresented: $showLog) { visitLogSheet }
            .sheet(isPresented: $showSettings) { settingsSheet }
            .sheet(isPresented: correctionPresented, onDismiss: resumeHoldAfterCorrection) { correctionCover }
            .sheet(isPresented: dartEditPresented, onDismiss: resumeHoldAfterDartEdit) { dartEditCover }
            .task(id: botTaskKey) { await throwBotDart() }
            .onAppear(perform: prepareMatch)
            .onDisappear(perform: leaveMatch)
            .onChange(of: voice.lastError) { _, message in
                if let message { error = message }
            }
            .onChange(of: isHoldingVisit) { _, holding in
                if holding { voice.stop() } else { applyRemote() }
            }
            .onChange(of: link.remoteToken) { _, _ in applyRemote() }
            .onChange(of: legCeremony == nil) { _, idle in if idle { applyRemote() } }
            .onChange(of: link.resetToken) { _, _ in resetAfterServerSync() }
            .onChange(of: link.notice) { _, message in
                guard let message else { return }
                error = message
                link.notice = nil
            }
            .alert("Opustit zápas?", isPresented: $showOnlineLeave) {
                Button("Opustit zápas", role: .destructive) {
                    Task {
                        if await link.abandon() {
                            await DartiqoAccount.shared.refreshMatchCompletion(into: store)
                            onOnlineCancel()
                        }
                    }
                }
                Button("Zůstat", role: .cancel) {}
            } message: { Text("Zápas skončí a soupeř uvidí, že jsi odešel. Počítá se do % dokončených zápasů.") }
    }
    /// Šipky soupeře se ukážou stejně jako kolo bota. Během pauzy po kole nebo ceremonie počkají.
    private func applyRemote() {
        guard link.isOnline, !isHoldingVisit, legCeremony == nil, !leavingHome, let update = link.takeRemote() else { return }
        if let visit = update.visit, link.isRemote(visit.player) {
            if visit.bust {
                store.feedback(spoken: "Přehoz")
            } else {
                store.feedback(visit.credited, checkout: visit.checkout, matchWon: update.game.finished)
            }
            applyVisitHold(game: update.game, darts: visit.darts, player: visit.player, fromBot: true)
        } else {
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) { activeMatch = update.game }
        }
    }
    /// Telefon se srovnal se serverem. Rozjeté kolo, oprava ani ceremonie už neplatí.
    private func resetAfterServerSync() {
        holdGeneration += 1
        isHoldingVisit = false
        holdPlayer = nil
        holdDarts = []
        legCeremony = nil
        oneEightyFlash = nil
        ceremonyLeaving = false
        ceremonyDismissing = false
        editingDart = nil
        correcting = nil
        cameraHits = []
        sumText = ""
        multiplier = 1
        revision = UUID()
    }
    private var matchCanvas: some View {
        ZStack {
            Group {
                if leavingHome {
                    MatchSavedSplash()
                } else if let game = activeMatch {
                    if game.finished && !isHoldingVisit {
                        result(game)
                            .transition(.opacity)
                    } else {
                        live(game)
                            .transition(.opacity)
                    }
                } else {
                    EmptyCard(title: "Žádná rozehraná hra", subtitle: "Novou hru spustíš na záložce Hrát.")
                        .padding()
                }
            }
            .safeAreaPadding(.top, ceremonyChromeGap)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(MatchColors.background)
        .overlay {
            if let ceremony = legCeremony {
                legCeremonyScreen(ceremony)
                    .ignoresSafeArea()
            }
            if oneEightyFlash != nil {
                OneEightyCelebrationOverlay {
                    oneEightyFlash = nil
                }
                .zIndex(2)
            }
        }
        .onGeometryChange(for: CGFloat.self, of: { $0.safeAreaInsets.top }) { _, top in
            var quiet = Transaction(animation: nil)
            quiet.disablesAnimations = true
            withTransaction(quiet) {
                currentChromeInset = top
                if !hidesMatchChrome, top > 1 { preservedChromeInset = top }
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { if !leavingHome { matchToolbar } }
        .toolbarBackground(MatchColors.background, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .preferredColorScheme(.dark)
        .tint(.white)
        .toolbar(leavingHome || hidesMatchChrome ? .hidden : .automatic, for: .navigationBar)
        .statusBarHidden(hidesMatchChrome || leavingHome)
        .transaction(value: hidesMatchChrome) { transaction in
            transaction.animation = nil
            transaction.disablesAnimations = true
        }
    }
    /// Ceremonie legu i oslavná 180 — schovat lištu i stavový řádek.
    private var hidesMatchChrome: Bool { legCeremony != nil || oneEightyFlash != nil }
    /// Mezera po schované liště. Hra zůstane tam, kde bude i s toolbarem, a ceremonie se přes ni jen prolne.
    private var ceremonyChromeGap: CGFloat {
        guard hidesMatchChrome else { return 0 }
        let gap = preservedChromeInset - currentChromeInset
        return gap > 1 ? gap : 0
    }
    private var matchCovers: some View {
        matchCanvas
            .fullScreenCover(isPresented: $decidingLeg) {
                if let game = activeMatch {
                    BullOffView(
                        names: game.players.map(\.name),
                        bots: game.players.map(\.botLevel),
                        purpose: .decider,
                        onFinish: awardBullOff,
                        onCancel: { decidingLeg = false }
                    )
                }
            }
            .fullScreenCover(isPresented: $showDecidingStarter) {
                if let game = activeMatch {
                    DecidingLegStarterView(
                        names: game.players.map(\.name),
                        bots: game.players.map(\.botLevel),
                        picks: decidingStarterPicks(game),
                        openingStarter: game.resolvedOpeningStarter,
                        onFinish: resolveDecidingStarter
                    )
                }
            }
            .fullScreenCover(item: $boardDetail) { selection in
                if let game = activeMatch {
                    boardDetailScreen(game, player: selection.player)
                }
            }
            .sheet(item: $statsPlayer) { selection in
                if let game = activeMatch {
                    playerStatsSheet(game, player: selection.player)
                }
            }
            .sheet(isPresented: $showProgress) { progressSheet }
            .fullScreenCover(isPresented: pauseCoverPresented) {
                if let game = activeMatch {
                    pauseScreen(game)
                        .presentationBackground(MatchColors.background)
                        .preferredColorScheme(.dark)
                }
            }
    }
    private var matchPrompts: some View {
        matchCovers
            .alert("Přerušit zápas?", isPresented: $showLeave) {
                Button("Uložit a odejít") { saveAndLeave() }
                Button("Vymazat zápas", role: .destructive) {
                    activeMatch = nil
                    store.returnHome()
                    dismiss()
                }
                Button("Zrušit", role: .cancel) {}
            } message: { Text("Ukládá se i rozehrané kolo po jedné nebo dvou šipkách.") }
            .confirmationDialog("Kolik šipek jsi použil na zavření?", isPresented: $finishPrompt, titleVisibility: .visible) {
                ForEach(1...3, id: \.self) { count in Button("\(count) šipky · správné zavření") { submitTotal(darts: count) } }
                Button("Zrušit", role: .cancel) {}
            } message: { Text("Potvrď, že poslední šipka splnila pravidlo out.") }
            .confirmationDialog("Po kolika šipkách nastal přehoz?", isPresented: $bustPrompt, titleVisibility: .visible) {
                ForEach(1...3, id: \.self) { n in Button("\(n) šipky") { bust(n) } }
                Button("Zrušit", role: .cancel) {}
            }
            .alert("Zápis skóre", isPresented: scoreErrorPresented) { Button("OK") {} } message: { Text(error ?? "") }
    }
    private var scoreErrorPresented: Binding<Bool> {
        Binding(get: { error != nil }, set: { if !$0 { error = nil } })
    }
    private var correctionPresented: Binding<Bool> {
        Binding(get: { correcting != nil }, set: { if !$0 { correcting = nil } })
    }
    /// Průběh má vlastní sheet, ať se oprava neotevře pod ním.
    private var dartEditPresented: Binding<Bool> {
        Binding(get: { editingDart != nil && !showProgress }, set: { if !$0 { editingDart = nil } })
    }
    private var progressDartEditPresented: Binding<Bool> {
        Binding(get: { editingDart != nil && showProgress }, set: { if !$0 { editingDart = nil } })
    }
    @ViewBuilder
    private var visitLogSheet: some View {
        NavigationStack {
            if let game = activeMatch {
                VisitLog(game: game, onRewind: { visit in
                    if link.isOnline {
                        error = "V online zápase se kola nevracejí. Skóre drží server pro oba hráče."
                    } else {
                        rewind(to: visit)
                    }
                }).toolbar { ToolbarItem(placement: .confirmationAction) { Button("Hotovo") { showLog = false } } }
            }
        }
    }
    private var settingsSheet: some View {
        MatchSettingsSheet(
            options: matchOptions,
            mode: activeMatch?.config.mode ?? .x01,
            showsBotTempo: settingsShowsBotTempo
        )
    }
    private var settingsShowsBotTempo: Bool {
        guard let game = activeMatch else { return false }
        return game.players.contains { $0.botLevel != nil } || game.ghostVisits != nil
    }
    @ViewBuilder
    private var correctionCover: some View {
        if let correcting { correctionSheet(correcting) }
    }
    @ViewBuilder
    private var dartEditCover: some View {
        if let editingDart, let game = activeMatch {
            let darts = isHoldingVisit ? holdDarts : game.currentDarts
            if darts.indices.contains(editingDart) {
                DartEditSheet(
                    index: editingDart,
                    dart: darts[editingDart],
                    numbers: scorePadNumbers(game),
                    onPick: { replaceThrownDart(at: editingDart, with: $0) },
                    onCancel: { self.editingDart = nil }
                )
            }
        }
    }
    /// Člověk může přepsat šipku, dokud je kolo ještě na obrazovce. Bot, duch a součet kola ne.
    private func canEditThrownDarts(_ game: Match) -> Bool {
        guard !link.isOnline, !paused, legCeremony == nil, !showDecidingStarter, !game.finished else { return false }
        if isHoldingVisit {
            guard let player = holdPlayer, game.players.indices.contains(player) else { return false }
            guard game.players[player].botLevel == nil, !game.isGhost(player) else { return false }
            if holdSurface == .total || game.visits.last?.enteredAsTotal == true { return false }
            return !holdDarts.isEmpty
        }
        guard game.legWinner == nil, !game.needsBullOff, !game.needsDecidingStarter else { return false }
        guard game.currentPlayer.botLevel == nil, !game.isGhostTurn else { return false }
        return !game.currentDarts.isEmpty
    }
    private func beginDartEdit(_ index: Int) {
        store.selectionHaptic()
        pausedHoldForEdit = isHoldingVisit
        editingDart = index
    }
    private func resumeHoldAfterDartEdit() {
        guard pausedHoldForEdit else { return }
        pausedHoldForEdit = false
        guard isHoldingVisit else { return }
        scheduleVisitHold(darts: holdDarts, celebrate180: oneEightyFlash != nil)
    }
    private func prepareMatch() {
        if let game = activeMatch {
            seedSurface(for: game)
            UIApplication.shared.isIdleTimerDisabled = game.config.settings.keepAwake
            if game.currentPlayer.botLevel != nil || game.isGhostTurn { holdDarts = game.currentDarts }
            if game.needsDecidingStarter { showDecidingStarter = true }
        }
        syncClock()
        lastActivity = Date()
    }
    /// Pauza je celé okno nad zápasem. Lišta zápasu pod ním zůstává, proto při zavření nahoře neblikne.
    private var showsPauseScreen: Bool {
        guard paused, let game = activeMatch else { return false }
        return !(game.finished && !isHoldingVisit)
    }
    private var pauseCoverPresented: Binding<Bool> {
        Binding(
            get: { showsPauseScreen },
            set: { presented in
                if !presented { resumeFromPause() }
            }
        )
    }
    private func showPause() {
        guard !paused else { return }
        paused = true
    }
    private func resumeFromPause() {
        lastActivity = Date()
        guard paused else { return }
        paused = false
    }
    private func seedSurface(for game: Match) {
        guard !didSeedSurface else { return }
        didSeedSurface = true
        // Výchozí je klasická číselná klávesnice; terč jen po ručním přepnutí.
        if game.currentDarts.isEmpty && canUseTotal(game) && game.config.settings.entry == .total {
            surface = .total
        } else {
            surface = .grid
        }
    }
    private func leaveMatch() {
        voice.stop()
        flushClock()
        store.flushSave()
        UIApplication.shared.isIdleTimerDisabled = false
    }

    @ToolbarContentBuilder
    private var matchToolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .cancellationAction) {
            Button {
                if !link.isOnline {
                    showLeave = true
                } else if activeMatch?.finished == true {
                    onOnlineExit()
                } else {
                    showOnlineLeave = true
                }
            } label: { Image(systemName: "xmark") }
                .accessibilityLabel("Odejít ze hry")
            if !link.isOnline, activeMatch?.finished != true {
                Button { showPause() } label: { Image(systemName: "pause.fill") }
                    .accessibilityLabel("Pozastavit hru")
            }
        }
        ToolbarItem(placement: .principal) {
            if let game = activeMatch {
                Text(game.config.mode.shortTitle).font(.headline)
            } else {
                Text("Zápas").font(.headline)
            }
        }
        ToolbarItemGroup(placement: .topBarTrailing) {
            Button { showLog = true } label: { Image(systemName: "list.bullet") }
                .accessibilityLabel("Historie zápasu")
            Button { showSettings = true } label: { Image(systemName: "gearshape") }
                .accessibilityLabel("Nastavení hry")
        }
    }
    private var botTaskKey: String {
        guard let g = activeMatch else { return "none" }
        // isHoldingVisit / legCeremony intentionally omitted — must not cancel mid-throw.
        return "\(g.id)-\(g.active)-\(g.leg)-\(g.visits.last?.id.uuidString ?? "start")-\(g.currentDarts.map(\.label).joined())-\(paused)-\(showSettings)-\(showLog)-\(showProgress)-\(showLeave)-\(statsPlayer != nil)-\(scenePhase == .active)-\(g.finished)-\(g.legWinner ?? -1)-\(g.needsDecidingStarter)-\(showDecidingStarter)-\(revision)"
    }
    private var botIsThrowing: Bool {
        guard let game = activeMatch, !isHoldingVisit else { return false }
        // Bot čeká, dokud ceremonie úplně nezmizí — šipka nesmí naskočit v prolínání.
        if legCeremony != nil || showDecidingStarter || game.needsDecidingStarter { return false }
        return game.currentPlayer.botLevel != nil || game.isGhostTurn || (link.isRemote(game.active) && game.legWinner == nil && !game.finished)
    }
    private var holdingBotVisit: Bool {
        guard isHoldingVisit, let player = holdPlayer, let game = activeMatch else { return false }
        return game.players[player].botLevel != nil || game.isGhost(player) || link.isRemote(player)
    }
    private var showingBotBoard: Bool { botIsThrowing || holdingBotVisit }
    private func stripDarts(for game: Match) -> [Dart] {
        if isHoldingVisit { return holdDarts }
        if link.isRemote(game.active) { return game.currentDarts }
        if game.currentPlayer.botLevel != nil || game.isGhostTurn { return holdDarts.isEmpty ? game.currentDarts : holdDarts }
        return game.currentDarts
    }
    private func live(_ game: Match) -> some View {
        let shown = game.liveProjection
        let showThrowStrip = (!game.needsBullOff || isHoldingVisit)
            && (game.legWinner == nil || isHoldingVisit || legCeremony != nil)
        return ScrollView {
            VStack(spacing: 14) {
                VStack(spacing: 6) {
                    matchProgressStrip(game)
                    scoreboard(game, shown: shown)
                    if showThrowStrip {
                        if game.config.mode == .cricket || game.config.mode == .aroundClock {
                            gameStrip(game, shown: shown)
                        }
                        currentThrowStrip(game, shown: shown)
                    }
                    liveStatsStrip(game, shown: shown)
                    if game.tracksGhostAverage, let ghostAvg = game.ghostAverage,
                       let human = game.players.indices.first(where: { game.players[$0].botLevel == nil && !game.isGhost($0) }) {
                        ghostRaceStrip(human: shown.average(for: human), ghost: ghostAvg)
                    }
                }
                if game.needsBullOff && !isHoldingVisit {
                    bullOffCard(game)
                } else if game.legWinner != nil && !isHoldingVisit && legCeremony == nil {
                    // Ceremony overlay handles continuation; keep a quiet placeholder underneath.
                    Color.clear.frame(height: 1)
                } else {
                    if showingBotBoard {
                        let darts = stripDarts(for: game)
                        let playerIndex = holdPlayer ?? game.active
                        let name = game.players.indices.contains(playerIndex) ? game.players[playerIndex].name : game.currentPlayer.name
                        matchDartboard(marks: darts, interactive: false, markBeds: true)
                            .accessibilityElement(children: .contain)
                            .accessibilityLabel(holdingBotVisit ? "\(name) dokončil hod" : "\(name) hází")
                            .accessibilityValue(darts.map(\.label).joined(separator: ", "))
                            .padding(.top, 14)
                    } else {
                    Group {
                    if surface == .voice {
                        voiceInput(game)
                    } else if isHoldingVisit && !keepsNumberPad {
                        // Součet i terč: čísla nechávají mřížku na místě, ať se layout při třetí šipce nesloží.
                        if holdSurface != .total {
                            frozenHumanSurface(game)
                        }
                    } else if !isHoldingVisit && surface == .total && canUseTotal(game) {
                        totalInput(game)
                    } else if !isHoldingVisit && surface == .board {
                        boardInput(game)
                    } else if !isHoldingVisit && surface == .camera {
                        CameraScoreView(
                            calibration: store.boardCalibration,
                            labels: game.currentDarts.map(\.label),
                            dartCount: game.currentDarts.count,
                            onDart: { dart, point in recordCameraHit(dart, point: point) },
                            onCorrect: !link.isOnline && cameraHits.count == game.currentDarts.count ? { correcting = $0 } : nil
                        )
                    } else {
                        dartGrid(game, shown: shown)
                            .allowsHitTesting(!isHoldingVisit)
                    }
                    }
                    .padding(.top, surface == .grid ? 8 : 14)
                    }
                }
            }.padding(.horizontal, 16).padding(.vertical, surface == .grid ? 6 : 10).frame(maxWidth: 780)
        }
        .scrollIndicators(.hidden)
        .scrollDisabled(pinsScoringPad && !showingBotBoard && !liveStatsNeedRoom(game))
        .safeAreaInset(edge: .bottom, spacing: 0) { bottomBar(game) }
    }

    @ViewBuilder
    private func frozenHumanSurface(_ game: Match) -> some View {
        switch holdSurface {
        case .board:
            matchDartboard(marks: holdDarts, interactive: false)
        case .total, .grid:
            EmptyView()
        case .voice:
            if holdingBust(game) {
                let labels = game.visits.last?.enteredAsTotal == true ? [] : holdDarts.map(\.label)
                VisitHoldSummaryCard(title: "Přehoz", value: "BUST", labels: labels)
            } else {
                visitSummaryCard(title: "Hlasové kolo", value: holdDarts.map(\.label).joined(separator: " · "))
            }
        case .camera:
            VStack(spacing: 10) {
                Text("Kamera").font(AppFont.caption(13, weight: .semibold)).foregroundStyle(MatchColors.ink.opacity(0.55))
                Text(holdingBust(game) ? "BUST" : "\(holdDarts.reduce(0) { $0 + $1.score })")
                    .font(AppFont.display(48, weight: .bold))
                    .foregroundStyle(holdingBust(game) ? ScoringChrome.coral : MatchColors.ink)
                    .monospacedDigit()
                CameraHitChips(
                    labels: holdDarts.map(\.label),
                    ink: MatchColors.ink,
                    fill: MatchColors.ink.opacity(0.07),
                    onCorrect: !link.isOnline && cameraHits.count == holdDarts.count && legCeremony == nil ? { correcting = $0 } : nil
                )
                if !link.isOnline, cameraHits.count == holdDarts.count {
                    Text("Nesedí pole? Klepni a oprav ho.")
                        .font(AppFont.caption(12))
                        .foregroundStyle(MatchColors.ink.opacity(0.5))
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 24)
            .padding(.horizontal, 16)
            .background(.white, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
    }

    // MARK: Kamera: opravy a učení

    private func recordCameraHit(_ dart: Dart, point: SIMD2<Double>?) -> Bool {
        let visits = activeMatch?.visits.count ?? 0
        let pending = activeMatch?.currentDarts.count ?? 0
        if pending == 0, !isHoldingVisit { cameraHits = [] }
        hit(dart)
        let accepted = (activeMatch?.visits.count ?? 0) > visits || (activeMatch?.currentDarts.count ?? 0) > pending
        if accepted { cameraHits.append(CameraHit(dart: dart, point: point)) }
        return accepted
    }

    private func correctionSheet(_ index: Int) -> some View {
        let current = cameraHits.indices.contains(index) ? cameraHits[index].dart : nil
        return NavigationStack {
            VStack(spacing: 18) {
                Text("Klepni, kam \(index + 1). šipka opravdu dopadla. Kamera se z opravy doučí.")
                    .font(AppFont.body(15))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                TouchDartboard(marks: current.map { [$0] } ?? [], interactive: true) { dart in
                    correcting = nil
                    correctCameraHit(index, to: dart)
                }
                .aspectRatio(1, contentMode: .fit)
                .frame(maxWidth: 420)
                Button("Mimo terč") {
                    correcting = nil
                    correctCameraHit(index, to: .miss)
                }
                .buttonStyle(.glass)
                Spacer(minLength: 0)
            }
            .padding(20)
            .navigationTitle(current.map { "Oprava: \($0.label)" } ?? "Oprava hodu")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Zrušit") { correcting = nil } }
            }
        }
        .presentationDetents([.large])
    }

    /// Oprava přepíše hod v zápase a uloží se jako učební vzorek.
    private func correctCameraHit(_ index: Int, to dart: Dart) {
        guard legCeremony == nil, var game = activeMatch, cameraHits.indices.contains(index) else { return }
        let darts = isHoldingVisit ? holdDarts : game.currentDarts
        guard darts.count == cameraHits.count, darts.indices.contains(index) else { return }
        var hits = cameraHits
        if let point = hits[index].point {
            store.learnDarts([DartSample(x: point.x, y: point.y, segment: dart.segment, multiplier: dart.multiplier, corrected: true)])
        }
        hits[index].dart = dart
        hits[index].corrected = true
        guard dart != darts[index] else {
            cameraHits = hits
            return
        }
        isHoldingVisit = false
        holdPlayer = nil
        holdDarts = []
        for _ in index..<darts.count { game.undoLastInput() }
        activeMatch = game
        cameraHits = Array(hits[..<index])
        var replay = darts
        replay[index] = dart
        for offset in index..<replay.count {
            let visits = activeMatch?.visits.count ?? 0
            let pending = activeMatch?.currentDarts.count ?? 0
            hit(replay[offset])
            let finished = (activeMatch?.visits.count ?? 0) > visits
            guard finished || (activeMatch?.currentDarts.count ?? 0) > pending else { break }
            cameraHits.append(hits[offset])
            if finished { break }
        }
        revision = UUID()
    }

    /// Přepíše jednu šipku a zbytek kola zahraje znovu, ať sedí přehoz i zavření.
    private func replaceThrownDart(at index: Int, with dart: Dart) {
        guard legCeremony == nil, var game = activeMatch else {
            editingDart = nil
            return
        }
        let holding = isHoldingVisit
        let source = holding ? holdDarts : game.currentDarts
        guard source.indices.contains(index) else {
            editingDart = nil
            return
        }
        let player = holding ? (holdPlayer ?? game.active) : game.active
        guard game.players.indices.contains(player),
              game.players[player].botLevel == nil,
              !game.isGhost(player) else {
            editingDart = nil
            return
        }
        if holding, holdSurface == .total || game.visits.last?.enteredAsTotal == true {
            editingDart = nil
            return
        }
        editingDart = nil
        guard dart != source[index] else { return }

        if holding {
            pausedHoldForEdit = false
            holdGeneration += 1
            isHoldingVisit = false
            holdPlayer = nil
            oneEightyFlash = nil
            holdDarts = []
        }
        for _ in index..<source.count { game.undoLastInput() }
        activeMatch = game

        let previousHits = cameraHits
        var tailHits: [CameraHit] = []
        if cameraHits.count == source.count {
            var copy = cameraHits
            copy[index].dart = dart
            copy[index].corrected = true
            tailHits = Array(copy[index...])
            cameraHits = Array(copy.prefix(index))
        }

        var replay = source
        replay[index] = dart
        var landed = false
        for offset in index..<replay.count {
            let visits = activeMatch?.visits.count ?? 0
            let pending = activeMatch?.currentDarts.count ?? 0
            hit(replay[offset])
            let finished = (activeMatch?.visits.count ?? 0) > visits
            let advanced = finished || (activeMatch?.currentDarts.count ?? 0) > pending
            guard advanced else { break }
            landed = true
            let tailIndex = offset - index
            if tailHits.indices.contains(tailIndex) {
                cameraHits.append(tailHits[tailIndex])
            }
            if finished { break }
        }
        if !landed {
            cameraHits = previousHits
            for original in source[index...] {
                let visits = activeMatch?.visits.count ?? 0
                let pending = activeMatch?.currentDarts.count ?? 0
                hit(original)
                let finished = (activeMatch?.visits.count ?? 0) > visits
                let advanced = finished || (activeMatch?.currentDarts.count ?? 0) > pending
                guard advanced else { break }
                if finished { break }
            }
        }
        revision = UUID()
    }

    private func resumeHoldAfterCorrection() {
        guard isHoldingVisit else { return }
        scheduleVisitHold(darts: holdDarts)
    }

    /// Hody, které nikdo neopravil, drží naučenou mapu na místě.
    private func learnConfirmedHits() {
        let samples = cameraHits.compactMap { hit -> DartSample? in
            guard !hit.corrected, let point = hit.point else { return nil }
            return DartSample(x: point.x, y: point.y, segment: hit.dart.segment, multiplier: hit.dart.multiplier, corrected: false)
        }
        cameraHits = []
        store.learnDarts(samples)
    }

    private func visitSummaryCard(title: String, value: String) -> some View {
        VisitHoldSummaryCard(title: title, value: value, labels: holdDarts.map(\.label))
    }
    /// Vlastní obrazovka pauzy. Čas u terče už stojí, dole je jen pokračování.
    private func pauseScreen(_ game: Match) -> some View {
        let shown = game.liveProjection
        let seconds = frozenBoardSeconds(game)
        let turn = isHoldingVisit ? (holdPlayer ?? game.active) : game.active
        return ScrollView {
            VStack(spacing: 18) {
                pauseHero(game, seconds: seconds, turn: turn)
                VStack(spacing: 12) {
                    ForEach(game.players.indices, id: \.self) { index in
                        pausePlayerRow(game, shown: shown, index: index)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 16)
            .frame(maxWidth: 780)
            .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.hidden)
        .safeAreaInset(edge: .top, spacing: 0) { pauseTopBar }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            Button { resumeFromPause() } label: {
                Label("Pokračovat", systemImage: "play.fill")
                    .font(.headline)
                    .labelStyle(.titleAndIcon)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 54)
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .glassEffect(.regular.interactive(), in: Capsule())
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 8)
            .frame(maxWidth: 780)
            .frame(maxWidth: .infinity)
            .accessibilityHint("Vrátí tě do rozehrané hry")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            ZStack {
                MatchColors.background
                RadialGradient(
                    colors: [MatchColors.amber.opacity(0.28), .clear],
                    center: .top,
                    startRadius: 0,
                    endRadius: 420
                )
            }
            .ignoresSafeArea()
        }
    }

    private var pauseTopBar: some View {
        Label("Pozastaveno", systemImage: "pause.fill")
            .font(.subheadline.weight(.semibold))
            .labelStyle(.titleAndIcon)
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .glassEffect(.regular, in: Capsule())
            .accessibilityAddTraits(.isHeader)
            .frame(maxWidth: .infinity)
            .padding(.top, 6)
            .padding(.bottom, 4)
    }

    private func pauseHero(_ game: Match, seconds: TimeInterval, turn: Int) -> some View {
        let parts = pauseClockParts(seconds)
        return VStack(spacing: 14) {
            HStack(alignment: .top, spacing: 10) {
                ForEach(Array(parts.enumerated()), id: \.offset) { index, part in
                    if index > 0 {
                        Text(":")
                            .font(AppFont.display(44, weight: .bold))
                            .foregroundStyle(.white.opacity(0.28))
                            .padding(.top, 6)
                            .accessibilityHidden(true)
                    }
                    VStack(spacing: 2) {
                        Text(part.value)
                            .font(AppFont.display(56, weight: .bold))
                            .monospacedDigit()
                            .foregroundStyle(.white)
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                        Text(part.unit)
                            .font(AppFont.caption(12, weight: .bold))
                            .foregroundStyle(.white.opacity(0.45))
                    }
                    .frame(minWidth: 64)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Čas u terče \(pauseClockSpoken(seconds))")

            Text(pauseStatusLine(game, turn: turn))
                .font(AppFont.body(15, weight: .medium))
                .foregroundStyle(.white.opacity(0.62))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 18)
        .padding(.bottom, 4)
    }

    private func pauseStatusLine(_ game: Match, turn: Int) -> String {
        var parts: [String] = []
        if game.config.mode == .x01 {
            parts.append("\(game.config.startingScore)")
        } else {
            parts.append(game.config.mode.title)
        }
        if game.players.indices.contains(turn), game.legWinner == nil, !game.finished {
            parts.append(playerTurnCaption(game, player: turn))
        } else if showsMatchLength(game) {
            parts.append("Leg \(game.leg)")
        }
        return parts.joined(separator: " · ")
    }

    private func pausePlayerRow(_ game: Match, shown: Match, index: Int) -> some View {
        let player = game.players[index]
        let score = panelScore(game, shown: shown, state: shown.states[index], index: index)
        let onTurn = game.legWinner == nil && !game.finished && (isHoldingVisit ? holdPlayer == index : game.active == index)
        let facts = pauseFacts(game, shown: shown, index: index)
        let caption = pausePlayerCaption(game, index: index)
        let tint = onTurn ? MatchColors.coral : Color.white
        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 12) {
                playerAvatar(game, index: index, size: 46)
                    .overlay(Circle().strokeBorder(onTurn ? MatchColors.coral : Color.white.opacity(0.16), lineWidth: onTurn ? 2 : 1))
                VStack(alignment: .leading, spacing: 3) {
                    Text(player.name)
                        .font(AppFont.body(17, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    if !caption.isEmpty {
                        Text(caption)
                            .font(AppFont.caption(12, weight: .bold))
                            .foregroundStyle(.white.opacity(0.55))
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 8)
                if onTurn {
                    Text("Na tahu")
                        .font(AppFont.caption(11, weight: .heavy))
                        .foregroundStyle(MatchColors.ink)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(MatchColors.coral, in: Capsule())
                }
            }

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(score.headline)
                    .font(AppFont.display(48, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(tint)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Spacer(minLength: 8)
                Text(score.headline == "BUST" ? "přehoz" : pauseScoreCaption(game))
                    .font(AppFont.caption(12, weight: .bold))
                    .foregroundStyle(.white.opacity(0.45))
            }

            if !facts.isEmpty {
                Rectangle()
                    .fill(.white.opacity(0.08))
                    .frame(height: 1)
                HStack(spacing: 0) {
                    ForEach(facts, id: \.title) { fact in
                        VStack(spacing: 2) {
                            Text(fact.value)
                                .font(AppFont.body(16, weight: .bold))
                                .monospacedDigit()
                                .foregroundStyle(.white)
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                            Text(fact.title)
                                .font(AppFont.caption(11, weight: .bold))
                                .foregroundStyle(.white.opacity(0.45))
                                .lineLimit(1)
                        }
                        .frame(maxWidth: .infinity)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("\(player.name), \(fact.title) \(fact.value)")
                    }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            (onTurn ? MatchColors.coral.opacity(0.12) : Color.white.opacity(0.05)),
            in: RoundedRectangle(cornerRadius: 22, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(onTurn ? MatchColors.coral.opacity(0.55) : Color.white.opacity(0.08), lineWidth: onTurn ? 1.5 : 1)
        )
        .accessibilityElement(children: .combine)
    }

    private func pausePlayerCaption(_ game: Match, index: Int) -> String {
        guard showsMatchLength(game), game.states.indices.contains(index) else { return "" }
        return matchLengthLine(game, state: game.states[index])
    }

    private func pauseScoreCaption(_ game: Match) -> String {
        switch game.config.mode {
        case .x01: return "zbývá"
        case .cricket: return game.config.settings.cricketNoScore ? "zavřeno" : "body"
        case .countUp: return "body"
        case .aroundClock: return "cíl"
        }
    }

    private func pauseFacts(_ game: Match, shown: Match, index: Int) -> [(title: String, value: String)] {
        switch game.config.mode {
        case .x01:
            let darts = shown.thrownDarts(for: index)
            let average = darts == 0 ? "—" : String(format: "%.1f", shown.average(for: index))
            let best = shown.lastTurnScore(for: index).map(String.init) ?? "—"
            var facts = [("Ø", average), ("Max", best), ("Šipky", "\(darts)")]
            let finish = CheckoutStats.make(from: shown, player: index)
            if let percentage = finish.percentage {
                facts.append(("Double", "\(Int(percentage.rounded())) %"))
            }
            return facts
        case .cricket, .countUp:
            let best = shown.lastTurnScore(for: index).map(String.init) ?? "—"
            return [
                ("Kola", "\(shown.states[index].rounds)"),
                ("Max", best),
                ("Šipky", "\(shown.thrownDarts(for: index))")
            ]
        case .aroundClock:
            let done = min(21, max(0, shown.states[index].clockTarget - 1))
            return [
                ("Hotovo", "\(done)/21"),
                ("Šipky", "\(shown.thrownDarts(for: index))"),
                ("Návštěvy", "\(shown.visits.filter { $0.player == index }.count)")
            ]
        }
    }

    /// Už připsaný čas plus běžící úsek, dokud ho pauza nestačí uložit. Pak už se nehýbe.
    private func frozenBoardSeconds(_ game: Match) -> TimeInterval {
        var total = game.playSeconds ?? 0
        if let start = clockStart {
            total += Date().timeIntervalSince(start)
        }
        return max(0, total)
    }

    private func pauseClockParts(_ seconds: TimeInterval) -> [(value: String, unit: String)] {
        let total = max(0, Int(seconds.rounded()))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let secs = total % 60
        var parts: [(value: String, unit: String)] = []
        if hours > 0 {
            parts.append((String(hours), "hod"))
        }
        parts.append((String(format: hours > 0 ? "%02d" : "%d", minutes), "min"))
        parts.append((String(format: "%02d", secs), "s"))
        return parts
    }

    private func pauseClockSpoken(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded()))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let secs = total % 60
        var parts: [String] = []
        if hours > 0 { parts.append(czechCount(hours, one: "hodina", few: "hodiny", many: "hodin")) }
        if minutes > 0 || hours > 0 { parts.append(czechCount(minutes, one: "minuta", few: "minuty", many: "minut")) }
        parts.append(czechCount(secs, one: "sekunda", few: "sekundy", many: "sekund"))
        return parts.joined(separator: " a ")
    }

    private func scoreboard(_ game: Match,shown: Match) -> some View {
        let columns = min(2, game.players.count)
        let rows = stride(from: 0, to: game.players.count, by: columns).map { Array($0..<min($0 + columns, game.players.count)) }
        let activeIndex = isHoldingVisit ? (holdPlayer ?? game.active) : game.active
        return Grid(horizontalSpacing: 0, verticalSpacing: 0) {
            ForEach(rows, id: \.first) { row in
                GridRow {
                    ForEach(row, id: \.self) { i in
                        playerPanel(game, shown: shown, index: i)
                    }
                    if row.count < columns { Color.clear.gridCellUnsizedAxes([.horizontal, .vertical]) }
                }
            }
        }
        .clipShape(
            ScoreboardBottomCutout(
                centerX: ScoreboardBottomCutout.centerX(activeIndex: activeIndex, columns: columns)
            )
        )
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.28), value: activeIndex)
    }

    private func playerPanel(_ game: Match, shown: Match, index: Int) -> some View {
        let player = game.players[index]
        let ceremonyOpen = legCeremony != nil && !ceremonyLeaving
        let active = (!isHoldingVisit && !ceremonyOpen && game.active == index)
            || (isHoldingVisit && holdPlayer == index)
        let state = shown.states[index]
        let score = panelScore(game, shown: shown, state: state, index: index)
        let chips = panelChips(game, shown: shown, index: index, fallback: score)
        let perLeg = game.config.mode == .x01 && (store.data.matchDisplay ?? MatchDisplay()).scope == .perLeg
        let openStats = { statsPlayer = BoardDetailSelection(player: index) }
        return VStack(alignment: .leading, spacing: 0) {
            Button(action: openStats) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        playerAvatar(game, index: index, size: 22)
                        Text(player.name)
                            .font(AppFont.body(14, weight: .semibold))
                            .lineLimit(1)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        if player.botLevel != nil {
                            Image(systemName: "cpu").font(AppFont.caption(11, weight: .semibold))
                        } else if game.isGhost(index) {
                            Image(systemName: "person.fill.viewfinder").font(AppFont.caption(11, weight: .semibold))
                        }
                    }
                    if game.config.hasHandicap {
                        Text(game.config.ruleLine(for: index))
                            .font(AppFont.caption(11, weight: .bold))
                            .opacity(0.65)
                            .lineLimit(1)
                            .accessibilityLabel("Handicap \(game.config.ruleLine(for: index))")
                    }
                    Text(score.headline)
                        .font(AppFont.display(72, weight: .bold))
                        .monospacedDigit()
                        .minimumScaleFactor(0.5)
                        .lineLimit(1)
                        .foregroundStyle(active ? Color.white : MatchColors.ink)
                        .contentTransition(score.headline == "BUST" ? .opacity : .numericText(value: score.headlineNumber))
                        .animation(reduceMotion ? nil : .snappy(duration: 0.28), value: score.headline)
                        .accessibilityLabel(score.headline == "BUST" ? "Přehoz" : score.headline)
                        .frame(maxWidth: .infinity, minHeight: 80, maxHeight: 80, alignment: .leading)
                    if !chips.isEmpty, !perLeg {
                        panelChipRow(chips)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, perLeg && !chips.isEmpty ? 4 : 16)
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if perLeg, !chips.isEmpty {
                perLegChipRow(chips, open: openStats)
                    .padding(.bottom, 12)
            }
        }
        .foregroundStyle(MatchColors.ink)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(active ? MatchColors.coral : MatchColors.amber)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.25), value: active)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(active ? [.isSelected, .isButton] : .isButton)
        .accessibilityAction(.default, openStats)
        .accessibilityHint("Zobrazí statistiky ze zápasu")
        .accessibilityValue(active ? "Na tahu" : "")
    }

    /// X01 a Cricket jedou na legy. Kolem hodin a Count Up končí jedním během.
    private func showsMatchLength(_ game: Match) -> Bool {
        switch game.config.mode {
        case .x01, .cricket:
            return game.config.playsSets || game.config.legsToWin > 1
        case .aroundClock, .countUp:
            return false
        }
    }

    /// Textový stav na pauze. V zápase je skóre v horní liště.
    private func matchLengthLine(_ game: Match, state: PlayerState) -> String {
        let legs = czechCount(state.legs, one: "leg", few: "legy", many: "legů")
        guard game.config.playsSets else { return legs }
        let sets = czechCount(state.sets, one: "set", few: "sety", many: "setů")
        return "\(sets) · \(legs)"
    }

    private func playerLook(_ game: Match, index: Int) -> (photo: Data?, asset: String?) {
        guard game.players.indices.contains(index) else { return (nil, nil) }
        let player = game.players[index]
        if let level = player.botLevel { return (nil, BotLevel.get(level).photo) }
        if game.isGhost(index) { return (store.profile?.photoJPEG, nil) }
        if link.isOnline, let photo = link.photo(for: player.id) { return (photo, nil) }
        return (store.photo(for: player.id), nil)
    }

    private func playerAvatar(_ game: Match, index: Int, size: CGFloat) -> some View {
        let player = game.players.indices.contains(index) ? game.players[index] : nil
        let look = playerLook(game, index: index)
        return Avatar(
            name: player?.name ?? "Hráč",
            bot: player?.botLevel != nil,
            size: size,
            photo: look.photo,
            asset: look.asset
        )
    }

    private struct PanelChip: Identifiable {
        var id: String
        var title: String
        var value: String
        var number: Double
        var accessibility: String
        var prominent = false
        var compact = false
    }

    /// Čísla pod velkým skóre. U X01 záleží na volbě v nastavení zápasu.
    private func panelChips(_ game: Match, shown: Match, index: Int, fallback: (headline: String, headlineNumber: Double, statTitle: String, statValue: String, statNumber: Double, statAccessibility: String)) -> [PanelChip] {
        guard game.config.mode == .x01 else {
            return [PanelChip(id: "mode", title: fallback.statTitle, value: fallback.statValue, number: fallback.statNumber, accessibility: fallback.statAccessibility)]
        }
        let display = store.data.matchDisplay ?? MatchDisplay()
        var chips: [PanelChip] = []
        switch display.scope {
        case .match:
            chips.append(averageChip(shown, player: index, leg: nil, title: "Ø", accessibility: "Průměr zápasu"))
        case .leg:
            chips.append(averageChip(shown, player: index, leg: game.leg, title: "Leg", accessibility: "Průměr legu \(game.leg)"))
        case .both:
            chips.append(averageChip(shown, player: index, leg: nil, title: "Ø", accessibility: "Průměr zápasu"))
            chips.append(averageChip(shown, player: index, leg: game.leg, title: "Leg", accessibility: "Průměr legu \(game.leg)"))
        case .perLeg:
            let legs = Array(Set(shown.visits.map(\.leg)).union([game.leg])).sorted()
            for leg in legs {
                let current = leg == game.leg
                chips.append(averageChip(
                    shown,
                    player: index,
                    leg: leg,
                    title: "\(leg)",
                    accessibility: current ? "Průměr legu \(leg), aktuální" : "Průměr legu \(leg)",
                    prominent: current,
                    compact: true
                ))
            }
        case .hidden:
            break
        }
        return chips
    }

    private func averageChip(_ match: Match, player: Int, leg: Int?, title: String, accessibility: String, prominent: Bool = false, compact: Bool = false) -> PanelChip {
        let darts = match.thrownDarts(for: player, leg: leg)
        let average = match.average(for: player, leg: leg)
        let text = darts == 0 ? "—" : String(format: "%.1f", average)
        return PanelChip(
            id: leg.map { "leg-\($0)" } ?? "match",
            title: title,
            value: text,
            number: average,
            accessibility: darts == 0 ? "\(accessibility) zatím není" : "\(accessibility) \(text)",
            prominent: prominent,
            compact: compact
        )
    }

    private func panelChipRow(_ chips: [PanelChip]) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 4) { ForEach(chips) { panelChip($0) } }
            VStack(alignment: .leading, spacing: 4) { ForEach(chips) { panelChip($0) } }
        }
    }

    /// Rozehraný leg je první a zvýrazněný. Ostatní jsou vedle něj a řádek se posouvá do strany.
    private func perLegChipRow(_ chips: [PanelChip], open: @escaping () -> Void) -> some View {
        let current = chips.last(where: \.prominent) ?? chips.last
        var ordered: [PanelChip] = []
        if let current { ordered.append(current) }
        ordered.append(contentsOf: chips.filter { $0.id != current?.id })
        return ScrollView(.horizontal) {
            HStack(spacing: 4) {
                ForEach(ordered) { item in
                    Button(action: open) { panelChip(item) }
                        .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
        }
        .scrollIndicators(.hidden)
        .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func panelChip(_ chip: PanelChip) -> some View {
        HStack(spacing: 4) {
            Text(chip.title)
                .font(AppFont.caption(chip.compact ? 11 : 12, weight: .heavy))
                .opacity(chip.prominent ? 0.9 : 0.6)
            liveNumber(chip.value, number: chip.number, font: AppFont.body(chip.compact ? 14 : 15, weight: .bold))
        }
        .padding(.horizontal, chip.compact ? 7 : 10)
        .padding(.vertical, chip.compact ? 3 : 4)
        .background(MatchColors.ink.opacity(chip.prominent ? 0.22 : 0.12), in: Capsule())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(chip.accessibility)
    }

    /// Číslo v živém zápase. Mění se hned — přetáčení číslic při každé šipce zasekávalo další klepnutí.
    private func liveNumber(_ text: String, number _: Double, font: Font) -> some View {
        Text(text)
            .font(font)
            .monospacedDigit()
            .minimumScaleFactor(0.7)
            .lineLimit(1)
    }

    private func liveStatsNeedRoom(_ game: Match) -> Bool {
        guard game.config.mode == .x01 else { return false }
        let display = store.data.matchDisplay ?? MatchDisplay()
        return display.showsExtraNumbers
    }

    @ViewBuilder
    private func liveStatsStrip(_ game: Match, shown: Match) -> some View {
        if liveStatsNeedRoom(game) {
            let display = store.data.matchDisplay ?? MatchDisplay()
            extraNumberRows(game, shown: shown, display: display)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }

    private func extraNumberRows(_ game: Match, shown: Match, display: MatchDisplay) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(game.players.indices, id: \.self) { index in
                HStack(spacing: 6) {
                    Text(game.players[index].name)
                        .font(AppFont.caption(12, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.85))
                        .lineLimit(1)
                        .frame(width: 72, alignment: .leading)
                    ScrollView(.horizontal) {
                        HStack(spacing: 6) {
                            if display.first9 {
                                extraPill(
                                    title: "9",
                                    value: first9Text(shown, player: index, leg: game.leg),
                                    accessibility: "Prvních 9, leg \(game.leg)"
                                )
                            }
                            if display.lastVisit {
                                let last = shown.lastTurnScore(for: index)
                                extraPill(
                                    title: "Kolo",
                                    value: last.map(String.init) ?? "—",
                                    accessibility: "Poslední kolo"
                                )
                            }
                            if display.bestVisit {
                                let hasTurn = shown.lastTurnScore(for: index) != nil
                                extraPill(
                                    title: "Max",
                                    value: hasTurn ? "\(shown.bestTurn(for: index))" : "—",
                                    accessibility: "Nejlepší kolo"
                                )
                            }
                            if display.dartCount {
                                extraPill(
                                    title: "Šipky",
                                    value: "\(shown.thrownDarts(for: index, leg: game.leg))",
                                    accessibility: "Šipky v legu \(game.leg)"
                                )
                            }
                        }
                    }
                    .scrollIndicators(.hidden)
                }
            }
        }
    }

    private func first9Text(_ match: Match, player: Int, leg: Int) -> String {
        let opening = match.visits.filter { $0.player == player && $0.leg == leg }.prefix(3)
        let darts = opening.reduce(0) { $0 + $1.darts.count }
        guard darts > 0 else { return "—" }
        return String(format: "%.1f", match.first9Average(for: player, leg: leg))
    }

    private func extraPill(title: String, value: String, accessibility: String) -> some View {
        HStack(spacing: 4) {
            Text(title)
                .font(AppFont.caption(11, weight: .heavy))
                .foregroundStyle(.white.opacity(0.45))
            liveNumber(value, number: Double(value) ?? 0, font: AppFont.body(14, weight: .bold))
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(.white.opacity(0.08), in: Capsule())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(accessibility) \(value)")
    }

    /// Stejný panel hráče. Mění se jen číslo, které hra skutečně sleduje.
    private func panelScore(_ game: Match, shown: Match, state: PlayerState, index: Int) -> (headline: String, headlineNumber: Double, statTitle: String, statValue: String, statNumber: Double, statAccessibility: String) {
        switch game.config.mode {
        case .x01:
            let average = shown.average(for: index)
            let text = String(format: "%.1f", average)
            if holdingBust(game), holdPlayer == index {
                return ("BUST", Double(state.remaining), "Ø", text, average, "Přehoz, zbývá \(state.remaining), průměr \(text)")
            }
            return ("\(state.remaining)", Double(state.remaining), "Ø", text, average, "Průměr \(text)")
        case .aroundClock:
            let done = min(21, max(0, state.clockTarget - 1))
            let headline = state.clockTarget >= 21 ? "BULL" : "\(state.clockTarget)"
            return (headline, Double(min(state.clockTarget, 21)), "Hotovo", "\(done)/21", Double(done), "Hotovo \(done) z 21")
        case .cricket:
            let numbers = game.config.settings.activeCricketNumbers
            let closed = numbers.filter { state.marks[$0, default: 0] >= 3 }.count
            let total = numbers.count
            if game.config.settings.cricketNoScore {
                let rounds = game.states[index].rounds
                return ("\(closed)/\(total)", Double(closed), "Kola", "\(rounds)", Double(rounds), "\(rounds) kol, zavřeno \(closed) z \(total)")
            }
            return ("\(state.points)", Double(state.points), "Zavřeno", "\(closed)/\(total)", Double(closed), "\(state.points) bodů, zavřeno \(closed) z \(total)")
        case .countUp:
            let rounds = game.states[index].rounds
            let limit = game.config.settings.countUpRounds
            return ("\(state.points)", Double(state.points), "Kola", "\(rounds)/\(limit)", Double(rounds), "\(state.points) bodů, kolo \(rounds) z \(limit)")
        }
    }

    @ViewBuilder
    private func gameStrip(_ game: Match, shown: Match) -> some View {
        switch game.config.mode {
        case .cricket:
            let index = isHoldingVisit ? (holdPlayer ?? game.active) : game.active
            CricketMarksCard(
                names: game.players.map(\.name),
                marksByPlayer: shown.states.map(\.marks),
                numbers: game.config.settings.activeCricketNumbers,
                active: index
            )
        case .aroundClock:
            let index = isHoldingVisit ? (holdPlayer ?? game.active) : game.active
            ClockProgressStrip(
                current: shown.states[index].clockTarget,
                rule: game.config.settings.clockStyle.title
            )
        case .x01, .countUp:
            EmptyView()
        }
    }

    private func padFocus(_ game: Match, shown: Match) -> Int? {
        guard game.config.mode == .aroundClock else { return nil }
        let target = shown.states[game.active].clockTarget
        guard target <= 21 else { return nil }
        return target >= 21 ? 25 : target
    }

    private func playerStatsSheet(_ game: Match, player: Int) -> some View {
        let shown = game.liveProjection
        let name = game.players.indices.contains(player) ? game.players[player].name : "Hráč"
        let score = panelScore(game, shown: shown, state: shown.states[player], index: player)
        let onTurn = game.legWinner == nil && !game.finished && game.active == player
        let tint: Color = game.players.count <= 2
            ? (onTurn ? MatchColors.coral : MatchColors.amber)
            : Theme.playerColor(player)
        return ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                playerStatsHero(game, player: player, name: name, score: score, onTurn: onTurn, tint: tint)
                resultPlayerReport(game, index: player, card: false)
            }
            .padding(.horizontal, 16)
            .padding(.top, 28)
            .padding(.bottom, 28)
        }
        .scrollIndicators(.hidden)
        .scrollEdgeEffectHidden(true, for: .bottom)
        .background {
            ZStack {
                MatchColors.background
                RadialGradient(
                    colors: [tint.opacity(0.34), .clear],
                    center: .topLeading,
                    startRadius: 0,
                    endRadius: 380
                )
                RadialGradient(
                    colors: [MatchColors.green.opacity(0.12), .clear],
                    center: .bottomTrailing,
                    startRadius: 0,
                    endRadius: 280
                )
            }
            .ignoresSafeArea()
        }
        .background(PlayerStatsSheetLock())
        .presentationDetents([.fraction(0.5), .large])
        .presentationDragIndicator(.visible)
        .presentationBackground(MatchColors.background)
        .presentationCornerRadius(28)
        .preferredColorScheme(.dark)
    }

    /// Otevře kartu v půlce. Výš ji systém občas vytáhne sám, tažením nahoru ale půjde na celou.
    private struct PlayerStatsSheetLock: UIViewControllerRepresentable {
        func makeUIViewController(context: Context) -> PlayerStatsSheetController {
            let controller = PlayerStatsSheetController()
            controller.view.backgroundColor = .clear
            controller.view.isUserInteractionEnabled = false
            return controller
        }

        func updateUIViewController(_ controller: PlayerStatsSheetController, context: Context) {
            controller.lock()
        }
    }

    private final class PlayerStatsSheetController: UIViewController {
        private static let halfID = UISheetPresentationController.Detent.Identifier("player-stats-half")
        /// Po otevření chvíli držíme půlku, ať se list sám nevytáhne. Pak už výšku řídí prst.
        private var allowExpandAt = Date().addingTimeInterval(0.45)

        override func viewDidLayoutSubviews() {
            super.viewDidLayoutSubviews()
            lock()
        }

        func lock() {
            var current: UIViewController? = self
            while let viewController = current {
                if let sheet = viewController.sheetPresentationController {
                    let half = UISheetPresentationController.Detent.custom(identifier: Self.halfID) { context in
                        context.maximumDetentValue * 0.5
                    }
                    sheet.prefersGrabberVisible = true
                    sheet.prefersScrollingExpandsWhenScrolledToEdge = true
                    let hasHalf = sheet.detents.contains { $0.identifier == Self.halfID }
                    let hasLarge = sheet.detents.contains { $0.identifier == .large }
                    if !hasHalf || !hasLarge {
                        let selected = sheet.selectedDetentIdentifier
                        sheet.detents = [half, .large()]
                        if Date() < allowExpandAt {
                            sheet.selectedDetentIdentifier = Self.halfID
                        } else if let selected {
                            sheet.selectedDetentIdentifier = selected
                        }
                    } else if Date() < allowExpandAt, sheet.selectedDetentIdentifier != Self.halfID {
                        sheet.selectedDetentIdentifier = Self.halfID
                    }
                    // Okraj scrollu se hledá v celém listu. Bezprostřední rodič je jen pozadí a scroll v něm není.
                    hideBottomEdgeEffect(in: viewController.view)
                    return
                }
                current = viewController.parent
            }
        }

        /// Tmavý pruh nad čárou domů je okraj scrollu. Systém ho kreslí přes obsah karty.
        private func hideBottomEdgeEffect(in view: UIView) {
            if let scroll = view as? UIScrollView {
                scroll.bottomEdgeEffect.isHidden = true
            }
            for subview in view.subviews {
                hideBottomEdgeEffect(in: subview)
            }
        }
    }

    private func playerStatsHero(
        _ game: Match,
        player: Int,
        name: String,
        score: (headline: String, headlineNumber: Double, statTitle: String, statValue: String, statNumber: Double, statAccessibility: String),
        onTurn: Bool,
        tint: Color
    ) -> some View {
        let visits = game.visits.filter { $0.player == player }
        let darts = visits.reduce(0) { $0 + $1.darts.count }
        return VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 14) {
                playerAvatar(game, index: player, size: 64)
                    .overlay(Circle().strokeBorder(tint.opacity(0.9), lineWidth: 2))
                VStack(alignment: .leading, spacing: 4) {
                    Text(name)
                        .font(.title2.bold())
                        .foregroundStyle(.white)
                        .lineLimit(2)
                        .minimumScaleFactor(0.75)
                    Text(resultRecordLine(game, index: player, darts: darts))
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.62))
                    if let caption = completionCaption(game, player: player) {
                        Text(caption)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.78))
                    }
                    if onTurn {
                        Text("Na tahu")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(MatchColors.ink)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(tint, in: Capsule())
                    }
                }
                Spacer(minLength: 0)
            }

            HStack(alignment: .lastTextBaseline, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(statsHeadlineCaption(game))
                        .font(AppFont.caption(11, weight: .heavy))
                        .tracking(1.0)
                        .foregroundStyle(.white.opacity(0.5))
                    Text(score.headline)
                        .font(AppFont.display(52, weight: .bold))
                        .monospacedDigit()
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 2) {
                    Text(score.statValue)
                        .font(.system(.title2, design: .rounded).weight(.bold))
                        .monospacedDigit()
                        .foregroundStyle(MatchColors.green)
                    Text(score.statTitle == "Ø" ? "průměr" : score.statTitle)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.55))
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(name). \(statsHeadlineCaption(game)) \(score.headline). \(score.statAccessibility)")
    }

    private func statsHeadlineCaption(_ game: Match) -> String {
        switch game.config.mode {
        case .x01: return "Zbývá"
        case .cricket: return game.config.settings.cricketNoScore ? "Zavřeno" : "Body"
        case .countUp: return "Body"
        case .aroundClock: return "Cíl"
        }
    }
    /// Current throw: tři šipky, nebo jeden součet kola (hlas / číselný zápis).
    @ViewBuilder
    private func currentThrowStrip(_ game: Match, shown: Match) -> some View {
        if holdingBust(game) {
            bustScoreStrip(game)
        } else if let total = heldTotalScore(game) {
            totalScoreStrip(value: "\(total)", filled: true)
        } else if showsTotalScoreStrip(game) {
            let display = liveTotalDisplay()
            totalScoreStrip(value: display, filled: display != "—")
        } else {
            let darts = stripDarts(for: game)
            let guide = checkoutGuide(game, shown: shown, thrown: darts.count)
            HStack(spacing: 0) {
                ForEach(0..<3, id: \.self) { i in
                    let filled = darts.count > i
                    let suggested = (!filled && guide.route.indices.contains(i - darts.count)) ? guide.route[i - darts.count] : nil
                    let note = (!filled && suggested == nil && i == darts.count) ? guide.note : nil
                    if i > 0 {
                        Rectangle()
                            .fill(.white.opacity(0.18))
                            .frame(width: 1, height: 36)
                            .padding(.horizontal, 6)
                            .accessibilityHidden(true)
                    }
                    ThrowSlotTile(
                        index: i,
                        dart: filled ? darts[i] : nil,
                        suggestion: suggested,
                        note: note,
                        setupLeave: suggested == nil ? nil : guide.setupLeave,
                        onGlass: true,
                        plain: true,
                        onEdit: filled && canEditThrownDarts(game) ? {
                            beginDartEdit(i)
                        } : nil
                    )
                }
            }
            .frame(height: 72)
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .frame(minHeight: 36)
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Aktuální hod")
        }
    }

    /// Hlas·Součet nebo číselný součet kola — ne tři sloty šipek.
    private func showsTotalScoreStrip(_ game: Match) -> Bool {
        guard !botIsThrowing, !holdingBotVisit else { return false }
        if surface == .total { return true }
        if surface == .voice, effectiveVoiceMode(for: game) == .total { return true }
        return false
    }

    private func liveTotalDisplay() -> String {
        if !sumText.isEmpty { return sumText }
        if surface == .voice, let label = voice.lastCommandLabel, label.hasPrefix("Součet ") {
            return String(label.dropFirst("Součet ".count))
        }
        return "—"
    }

    /// Držené kolo je přehoz. Skóre se vrací a na ploše má být BUST, ne nula.
    private func holdingBust(_ game: Match) -> Bool {
        guard isHoldingVisit, let player = holdPlayer, let visit = game.visits.last else { return false }
        return visit.bust && visit.player == player && visit.leg == game.leg
    }

    /// Součet zadaný hlasem / číslem — ne syntetické T20 (60·60·60).
    private func heldTotalScore(_ game: Match) -> Int? {
        guard isHoldingVisit else { return nil }
        if holdSurface == .total {
            if let visit = game.visits.last,
               visit.enteredAsTotal == true,
               visit.player == holdPlayer {
                return visit.credited
            }
            return holdDarts.reduce(0) { $0 + $1.score }
        }
        if let visit = game.visits.last,
           visit.enteredAsTotal == true,
           visit.player == holdPlayer {
            return visit.credited
        }
        return nil
    }

    private func totalScoreStrip(value: String, filled: Bool) -> some View {
        let number = Double(value) ?? 0
        return HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text("SOUČET KOLA")
                    .font(AppFont.caption(10, weight: .heavy))
                    .tracking(1.0)
                    .foregroundStyle(.white.opacity(0.45))
                Text(filled ? "\(Int(number))" : "—")
                    .font(AppFont.display(34, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(filled ? Color.white : Color.white.opacity(0.28))
            }
            Spacer(minLength: 0)
            Image(systemName: "sum")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(Theme.brand.opacity(filled ? 1 : 0.45))
                .frame(width: 44, height: 44)
                .background(Color.white.opacity(0.10), in: Circle())
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity)
        .frame(height: 72)
        .frame(minHeight: 36)
        .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityLabel(filled ? "Součet kola \(value)" : "Součet kola")
    }

    private func bustScoreStrip(_ game: Match) -> some View {
        let enteredTotal = game.visits.last?.enteredAsTotal == true
        let darts = enteredTotal ? [] : holdDarts
        let canEdit = canEditThrownDarts(game) && !darts.isEmpty
        return HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                if canEdit {
                    HStack(spacing: 6) {
                        ForEach(Array(darts.enumerated()), id: \.offset) { index, dart in
                            Button {
                                beginDartEdit(index)
                            } label: {
                                Text(dart.label)
                                    .font(AppFont.caption(12, weight: .heavy))
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Color.white.opacity(0.12), in: Capsule())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("\(index + 1). šipka \(dart.label)")
                            .accessibilityHint("Upravit šipku")
                        }
                    }
                    .foregroundStyle(.white.opacity(0.7))
                } else {
                    Text(darts.isEmpty ? "PŘEHOZ" : darts.map(\.label).joined(separator: " · "))
                        .font(AppFont.caption(10, weight: .heavy))
                        .tracking(darts.isEmpty ? 1.0 : 0)
                        .foregroundStyle(.white.opacity(0.55))
                        .lineLimit(1)
                }
                Text("BUST")
                    .font(AppFont.display(34, weight: .bold))
                    .foregroundStyle(ScoringChrome.coral)
            }
            Spacer(minLength: 0)
            Image(systemName: "arrow.uturn.backward.circle.fill")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(ScoringChrome.coral)
                .frame(width: 44, height: 44)
                .background(Color.white.opacity(0.10), in: Circle())
                .accessibilityHidden(true)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity)
        .frame(height: 72)
        .frame(minHeight: 36)
        .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityElement(children: canEdit ? .contain : .combine)
        .accessibilityLabel(darts.isEmpty ? "Přehoz" : "Přehoz, \(darts.map(\.label).joined(separator: ", "))")
    }

    private func matchProgressStrip(_ game: Match) -> some View {
        let player = isHoldingVisit ? (holdPlayer ?? game.active) : game.active
        let showsLength = showsMatchLength(game)
        let showsSets = showsLength && game.config.playsSets
        return Button {
            showProgress = true
        } label: {
            HStack(spacing: 0) {
                Text(playerTurnCaption(game, player: player))
                    .font(AppFont.caption(12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.78))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.55)
                    .frame(maxWidth: .infinity)
                if showsSets {
                    progressDivider
                    progressScore(game, title: "Sety", values: game.states.map(\.sets), total: game.config.shownSets)
                }
                if showsLength {
                    progressDivider
                    progressScore(game, title: "Legy", values: game.states.map(\.legs), total: game.config.shownLegs)
                }
                Image(systemName: "chevron.down")
                    .font(AppFont.caption(10, weight: .bold))
                    .foregroundStyle(.white.opacity(0.55))
                    .padding(.leading, 6)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 8)
            .frame(minHeight: 36)
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.25), value: progressSignature(game))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(progressAccessibility(game, player: player))
        .accessibilityHint("Otevře okno se skóre a aktuální šipkou")
        .accessibilityAddTraits(.isButton)
    }

    private var progressDivider: some View {
        Rectangle()
            .fill(.white.opacity(0.18))
            .frame(width: 1, height: 16)
            .padding(.horizontal, 8)
            .accessibilityHidden(true)
    }

    private func progressScore(_ game: Match, title: String, values: [Int], total: Int) -> some View {
        HStack(spacing: 5) {
            Text(title)
                .font(AppFont.caption(13, weight: .semibold))
                .foregroundStyle(.white.opacity(0.78))
            HStack(spacing: 4) {
                ForEach(values.indices, id: \.self) { index in
                    if index > 0 {
                        Text(":")
                            .font(AppFont.body(15, weight: .bold))
                            .foregroundStyle(.white.opacity(0.38))
                    }
                    Text("\(values[index])")
                        .font(AppFont.body(16, weight: .heavy))
                        .monospacedDigit()
                        .foregroundStyle(progressTint(game, player: index))
                        .contentTransition(.numericText(value: Double(values[index])))
                }
            }
            Text("(z \(total))")
                .font(AppFont.caption(12, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(.white.opacity(0.42))
        }
        .lineLimit(1)
        .minimumScaleFactor(0.55)
        .frame(maxWidth: .infinity)
    }

    /// Stejné barvy jako karty hráčů, ať číslo patří ke své straně.
    private func progressTint(_ game: Match, player: Int) -> Color {
        guard game.players.indices.contains(player) else { return MatchColors.amber }
        if game.players.count <= 2 {
            let ceremonyOpen = legCeremony != nil && !ceremonyLeaving
            let active = (!isHoldingVisit && !ceremonyOpen && game.active == player)
                || (isHoldingVisit && holdPlayer == player)
            return active ? MatchColors.coral : MatchColors.amber
        }
        return Theme.playerColor(player)
    }

    private func progressSignature(_ game: Match) -> String {
        let active = isHoldingVisit ? (holdPlayer ?? game.active) : game.active
        let scores = game.states.map { "\($0.sets)-\($0.legs)" }.joined(separator: ",")
        return "\(active)-\(game.leg)-\(scores)"
    }

    private func progressAccessibility(_ game: Match, player: Int) -> String {
        var parts = [playerTurnCaption(game, player: player)]
        if showsMatchLength(game), game.config.playsSets {
            let sets = game.players.indices.map { "\(game.players[$0].name) \(game.states[$0].sets)" }.joined(separator: ", ")
            parts.append("Sety z \(game.config.shownSets): \(sets)")
        }
        if showsMatchLength(game) {
            let legs = game.players.indices.map { "\(game.players[$0].name) \(game.states[$0].legs)" }.joined(separator: ", ")
            parts.append("Legy z \(game.config.shownLegs): \(legs)")
        }
        return parts.joined(separator: ". ")
    }

    /// Kolo, šipka v návštěvě a případný limit šipek. Stejná čísla má lišta i okno průběhu.
    private struct TurnSnapshot {
        var round: Int
        var dartsThrown: Int
        var visitDone: Bool
        var isTotal: Bool
        var dartsUsed: Int?
        var dartLimit: Int?

        var isBust = false

        var dartTitle: String {
            if isBust { return "Přehoz" }
            if visitDone { return "Kolo hotovo" }
            if isTotal { return "Součet kola" }
            return "\(min(3, dartsThrown + 1)). šipka"
        }

        func detail(leg: Int) -> String {
            var parts = ["Kolo \(round)", "Leg \(leg)"]
            if let dartsUsed, let dartLimit {
                parts.append("\(dartsUsed) z \(dartLimit) šipek")
            }
            return parts.joined(separator: " · ")
        }
    }

    private func turnSnapshot(_ game: Match, player: Int) -> TurnSnapshot {
        let completedRounds = game.visits.lazy.filter { $0.leg == game.leg && $0.player == player }.count
        let round = isHoldingVisit ? max(1, completedRounds) : completedRounds + 1
        let heldDarts = isHoldingVisit ? holdDarts.count : game.currentDarts.count
        var dartsUsed: Int?
        var dartLimit: Int?
        if game.config.mode == .x01, let limit = game.config.settings.dartLimit {
            dartLimit = limit
            dartsUsed = min(limit, isHoldingVisit ? completedRounds * 3 : completedRounds * 3 + heldDarts)
        }
        return TurnSnapshot(
            round: round,
            dartsThrown: min(3, heldDarts),
            visitDone: isHoldingVisit,
            isTotal: showsTotalScoreStrip(game) || (isHoldingVisit && holdSurface == .total),
            dartsUsed: dartsUsed,
            dartLimit: dartLimit,
            isBust: holdingBust(game) && player == holdPlayer
        )
    }

    private func playerTurnCaption(_ game: Match, player: Int) -> String {
        let turn = turnSnapshot(game, player: player)
        if turn.isBust {
            return "Leg \(game.leg) · Kolo \(turn.round) · Přehoz"
        }
        if turn.isTotal {
            return "Leg \(game.leg) · Kolo \(turn.round) · Součet"
        }
        if let used = turn.dartsUsed, let limit = turn.dartLimit {
            return "Leg \(game.leg) · Kolo \(turn.round) · Šipky \(used)/\(limit)"
        }
        return "Leg \(game.leg) · Kolo \(turn.round) · Šipky \(turn.dartsThrown)/3"
    }

    @ViewBuilder
    private var progressSheet: some View {
        if let game = activeMatch {
            let shown = game.liveProjection
            let player = isHoldingVisit ? (holdPlayer ?? game.active) : game.active
            NavigationStack {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        progressHero(game, active: player)
                        if showsMatchLength(game) {
                            progressLengthCard(game)
                        }
                        progressSectionTitle("Aktuální skóre")
                        progressScoreGrid(game, shown: shown, active: player)
                        progressThrowCard(game, shown: shown, player: player)
                    }
                    .padding(16)
                    .padding(.bottom, 12)
                }
                .scrollIndicators(.hidden)
                .background {
                    ZStack {
                        MatchColors.background
                        RadialGradient(
                            colors: [MatchColors.coral.opacity(0.22), .clear],
                            center: .topLeading,
                            startRadius: 0,
                            endRadius: 360
                        )
                        RadialGradient(
                            colors: [MatchColors.amber.opacity(0.12), .clear],
                            center: .bottomTrailing,
                            startRadius: 0,
                            endRadius: 300
                        )
                    }
                    .ignoresSafeArea()
                }
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button { showProgress = false } label: {
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
                .toolbarColorScheme(.dark, for: .navigationBar)
                .sheet(isPresented: progressDartEditPresented, onDismiss: resumeHoldAfterDartEdit) { dartEditCover }
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
            .presentationBackground(MatchColors.background)
            .presentationCornerRadius(28)
            .preferredColorScheme(.dark)
        }
    }

    private func progressSectionTitle(_ title: String) -> some View {
        Text(title.uppercased())
            .font(AppFont.caption(11, weight: .heavy))
            .tracking(1.1)
            .foregroundStyle(.white.opacity(0.45))
    }

    private func progressHero(_ game: Match, active: Int) -> some View {
        let duo = game.players.count == 2
        let primary = game.config.playsSets
            ? game.states.map(\.sets)
            : game.states.map(\.legs)
        let primaryTotal = game.config.playsSets ? game.config.shownSets : game.config.shownLegs
        let primaryLabel = game.config.playsSets ? "Sety" : "Legy"
        return VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("Průběh")
                    .font(AppFont.caption(12, weight: .heavy))
                    .foregroundStyle(MatchColors.ink.opacity(0.5))
                Spacer(minLength: 8)
                Text(game.config.lengthLine)
                    .font(AppFont.caption(12, weight: .bold))
                    .foregroundStyle(MatchColors.ink.opacity(0.55))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }

            if duo {
                progressHeadToHead(game, values: primary, label: primaryLabel, total: primaryTotal, active: active)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    Text(primaryLabel)
                        .font(AppFont.caption(12, weight: .heavy))
                        .foregroundStyle(MatchColors.ink.opacity(0.5))
                    Text(primary.map(String.init).joined(separator: " : "))
                        .font(AppFont.display(42, weight: .bold))
                        .monospacedDigit()
                        .foregroundStyle(MatchColors.ink)
                        .minimumScaleFactor(0.6)
                        .lineLimit(1)
                    Text("z \(primaryTotal) · Leg \(game.leg)")
                        .font(AppFont.caption(13, weight: .semibold))
                        .foregroundStyle(MatchColors.ink.opacity(0.55))
                }
            }

            Text(game.config.lengthDetail)
                .font(AppFont.caption(13, weight: .medium))
                .foregroundStyle(MatchColors.ink.opacity(0.62))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(
                colors: [MatchColors.amber, MatchColors.coral.opacity(0.92)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 26, style: .continuous)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(progressHeroAccessibility(game, values: primary, label: primaryLabel, total: primaryTotal))
    }

    private func progressHeadToHead(
        _ game: Match,
        values: [Int],
        label: String,
        total: Int,
        active: Int
    ) -> some View {
        HStack(alignment: .center, spacing: 10) {
            progressHeroSide(game, index: 0, value: values.indices.contains(0) ? values[0] : 0, active: active)
            VStack(spacing: 4) {
                Text(label.uppercased())
                    .font(AppFont.caption(10, weight: .heavy))
                    .tracking(0.8)
                    .foregroundStyle(MatchColors.ink.opacity(0.45))
                Text(":")
                    .font(AppFont.display(28, weight: .bold))
                    .foregroundStyle(MatchColors.ink.opacity(0.28))
                Text("z \(total)")
                    .font(AppFont.caption(11, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(MatchColors.ink.opacity(0.45))
            }
            .frame(width: 52)
            progressHeroSide(game, index: 1, value: values.indices.contains(1) ? values[1] : 0, active: active)
        }
    }

    private func progressHeroSide(_ game: Match, index: Int, value: Int, active: Int) -> some View {
        let name = game.players.indices.contains(index) ? game.players[index].name : "Hráč"
        let onTurn = index == active
        return VStack(spacing: 6) {
            playerAvatar(game, index: index, size: 36)
                .overlay {
                    if onTurn {
                        Circle()
                            .strokeBorder(MatchColors.ink.opacity(0.35), lineWidth: 2)
                            .frame(width: 40, height: 40)
                    }
                }
            Text("\(value)")
                .font(AppFont.display(44, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(MatchColors.ink)
                .contentTransition(.numericText(value: Double(value)))
                .minimumScaleFactor(0.6)
                .lineLimit(1)
            Text(name)
                .font(AppFont.caption(12, weight: onTurn ? .heavy : .semibold))
                .foregroundStyle(MatchColors.ink.opacity(onTurn ? 0.85 : 0.55))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
    }

    private func progressHeroAccessibility(_ game: Match, values: [Int], label: String, total: Int) -> String {
        let scores = game.players.indices.map { index in
            let value = values.indices.contains(index) ? values[index] : 0
            return "\(game.players[index].name) \(value)"
        }.joined(separator: ", ")
        return "Průběh. \(label) z \(total): \(scores). \(game.config.lengthDetail)"
    }

    private func progressScoreGrid(_ game: Match, shown: Match, active: Int) -> some View {
        let columns = min(2, max(1, game.players.count))
        let rows = stride(from: 0, to: game.players.count, by: columns).map { Array($0..<min($0 + columns, game.players.count)) }
        return Grid(horizontalSpacing: 10, verticalSpacing: 10) {
            ForEach(rows, id: \.first) { row in
                GridRow {
                    ForEach(row, id: \.self) { index in
                        progressScoreCell(game, shown: shown, index: index, active: active)
                    }
                    if row.count < columns {
                        Color.clear.gridCellUnsizedAxes([.horizontal, .vertical])
                    }
                }
            }
        }
    }

    private func progressScoreCell(_ game: Match, shown: Match, index: Int, active: Int) -> some View {
        let name = game.players.indices.contains(index) ? game.players[index].name : "Hráč"
        let state = shown.states.indices.contains(index) ? shown.states[index] : PlayerState(config: game.config, player: index)
        let score = panelScore(game, shown: shown, state: state, index: index)
        let onTurn = index == active
        let badge = isHoldingVisit && onTurn ? "hotovo" : (onTurn ? "na tahu" : nil)
        let shape = RoundedRectangle(cornerRadius: 20, style: .continuous)
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                playerAvatar(game, index: index, size: 26)
                Text(name)
                    .font(AppFont.body(14, weight: .semibold))
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if let badge {
                    Text(badge)
                        .font(AppFont.caption(10, weight: .heavy))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(onTurn ? Color.white.opacity(0.22) : Color.white.opacity(0.14), in: Capsule())
                }
            }
            Text(score.headline)
                .font(AppFont.display(42, weight: .bold))
                .monospacedDigit()
                .minimumScaleFactor(0.5)
                .lineLimit(1)
                .foregroundStyle(.white)
                .contentTransition(score.headline == "BUST" ? .opacity : .numericText(value: score.headlineNumber))
            HStack(spacing: 6) {
                Text(score.headline == "BUST" ? "přehoz" : progressScoreUnit(game))
                    .font(AppFont.caption(11, weight: .semibold))
                    .opacity(0.65)
                Text("·")
                    .opacity(0.35)
                HStack(spacing: 4) {
                    Text(score.statTitle)
                    liveNumber(score.statValue, number: score.statNumber, font: AppFont.caption(12, weight: .bold))
                }
                .font(AppFont.caption(12, weight: .bold))
                .opacity(0.85)
            }
        }
        .foregroundStyle(.white)
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background {
            if onTurn {
                LinearGradient(
                    colors: [MatchColors.coral, MatchColors.coral.opacity(0.82)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            } else {
                Color.white.opacity(0.07)
            }
        }
        .clipShape(shape)
        .overlay(shape.strokeBorder(onTurn ? Color.white.opacity(0.18) : Color.white.opacity(0.08), lineWidth: 1))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(name), \(score.headline == "BUST" ? "přehoz" : progressScoreUnit(game)) \(score.headline), \(score.statAccessibility)\(badge.map { ", \($0)" } ?? "")")
    }

    private func progressScoreUnit(_ game: Match) -> String {
        switch game.config.mode {
        case .x01: return "zbývá"
        case .cricket: return game.config.settings.cricketNoScore ? "zavřeno" : "body"
        case .aroundClock: return "cíl"
        case .countUp: return "body"
        }
    }

    private func progressThrowCard(_ game: Match, shown: Match, player: Int) -> some View {
        let turn = turnSnapshot(game, player: player)
        let darts = stripDarts(for: game)
        let guide = checkoutGuide(game, shown: shown, thrown: darts.count)
        let name = game.players.indices.contains(player) ? game.players[player].name : "Hráč"
        let suggestion = (!turn.visitDone && !turn.isTotal) ? guide.route.first : nil
        let title = suggestion.map { "\(turn.dartTitle) · \($0.label)" } ?? turn.dartTitle
        let visitSum = progressVisitSum(game)
        let totalValue = visitSum?.value ?? "—"
        let shape = RoundedRectangle(cornerRadius: 24, style: .continuous)
        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 12) {
                playerAvatar(game, index: player, size: 34)
                VStack(alignment: .leading, spacing: 2) {
                    Text(name)
                        .font(AppFont.caption(12, weight: .heavy))
                        .foregroundStyle(MatchColors.ink.opacity(0.45))
                        .lineLimit(1)
                    Text(title)
                        .font(AppFont.display(26, weight: .bold))
                        .foregroundStyle(MatchColors.ink)
                        .minimumScaleFactor(0.7)
                        .lineLimit(1)
                    Text(turn.detail(leg: game.leg))
                        .font(AppFont.caption(13, weight: .semibold))
                        .foregroundStyle(MatchColors.ink.opacity(0.55))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if !turn.isTotal, let sum = visitSum {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(sum.title)
                            .font(AppFont.caption(11, weight: .heavy))
                            .tracking(0.6)
                            .foregroundStyle(MatchColors.ink.opacity(0.45))
                        Text(sum.value)
                            .font(AppFont.display(30, weight: .bold))
                            .monospacedDigit()
                            .foregroundStyle(MatchColors.ink)
                            .contentTransition(.numericText())
                    }
                }
            }
            if turn.isTotal {
                Text(totalValue)
                    .font(AppFont.display(48, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(totalValue == "—" ? MatchColors.ink.opacity(0.28) : MatchColors.ink)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                HStack(spacing: 8) {
                    ForEach(0..<3, id: \.self) { index in
                        let filled = darts.count > index
                        let suggested = (!filled && !turn.visitDone && guide.route.indices.contains(index - darts.count))
                            ? guide.route[index - darts.count] : nil
                        let note = (!filled && suggested == nil && index == darts.count && !turn.visitDone) ? "teď" : nil
                        ThrowSlotTile(
                            index: index,
                            dart: filled ? darts[index] : nil,
                            suggestion: suggested,
                            note: note,
                            setupLeave: suggested == nil ? nil : guide.setupLeave,
                            plain: true,
                            onEdit: filled && canEditThrownDarts(game) ? {
                                beginDartEdit(index)
                            } : nil
                        )
                    }
                }
                .frame(height: 88)
            }
            if !turn.visitDone, !turn.isTotal, let line = progressCheckoutLine(guide) {
                Text(line)
                    .font(AppFont.caption(13, weight: .semibold))
                    .foregroundStyle(guide.setupLeave != nil ? MatchColors.setupTip : (guide.route.isEmpty ? MatchColors.ink.opacity(0.7) : MatchColors.aiTip))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white, in: shape)
        .overlay(shape.strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(name), \(title), \(turn.detail(leg: game.leg))")
    }

    private func progressVisitSum(_ game: Match) -> (title: String, value: String)? {
        if isHoldingVisit, let visit = game.visits.last, visit.player == holdPlayer, visit.leg == game.leg {
            if visit.bust { return ("Kolo", "Přehoz") }
            return ("V kole", "\(visit.credited)")
        }
        if showsTotalScoreStrip(game) {
            let display = liveTotalDisplay()
            guard display != "—" else { return nil }
            return ("Součet", display)
        }
        let darts = stripDarts(for: game)
        guard !darts.isEmpty else { return nil }
        return ("V kole", "\(darts.reduce(0) { $0 + $1.score })")
    }

    private func progressCheckoutLine(_ guide: ScoringChrome.CheckoutGuide) -> String? {
        if let leave = guide.setupLeave, !guide.route.isEmpty {
            return "Sehrávka \(guide.route.map(\.label).joined(separator: " · ")) na \(leave)"
        }
        if !guide.route.isEmpty {
            return "Zavření \(guide.route.map(\.label).joined(separator: " · "))"
        }
        if guide.note == "double in" { return "Nejdřív double in" }
        return guide.note
    }

    private func progressLengthCard(_ game: Match) -> some View {
        let shape = RoundedRectangle(cornerRadius: 22, style: .continuous)
        return VStack(alignment: .leading, spacing: 16) {
            if game.config.playsSets {
                progressLengthBlock(
                    game,
                    title: "Sety",
                    values: game.states.map(\.sets),
                    total: game.config.shownSets,
                    icon: "square.stack.3d.up.fill"
                )
                Divider().overlay(.white.opacity(0.1))
            }
            progressLengthBlock(
                game,
                title: game.config.playsSets ? "Legy v setu" : "Legy",
                values: game.states.map(\.legs),
                total: game.config.shownLegs,
                icon: "flag.checkered"
            )
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.06), in: shape)
        .overlay(shape.strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
    }

    private func progressLengthBlock(
        _ game: Match,
        title: String,
        values: [Int],
        total: Int,
        icon: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(MatchColors.amber)
                Text(title)
                    .font(AppFont.body(15, weight: .bold))
                    .foregroundStyle(.white)
                Spacer(minLength: 8)
                Text("z \(total)")
                    .font(AppFont.caption(12, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(.white.opacity(0.45))
            }
            ForEach(game.players.indices, id: \.self) { index in
                progressLengthRow(
                    game,
                    index: index,
                    value: values.indices.contains(index) ? values[index] : 0,
                    total: total
                )
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(progressLengthAccessibility(game, title: title, values: values, total: total))
    }

    private func progressLengthRow(_ game: Match, index: Int, value: Int, total: Int) -> some View {
        let tint = progressTint(game, player: index)
        let showPips = total <= 7
        return HStack(spacing: 10) {
            playerAvatar(game, index: index, size: 28)
            Text(game.players[index].name)
                .font(AppFont.body(15, weight: .semibold))
                .foregroundStyle(.white.opacity(0.92))
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            if showPips {
                HStack(spacing: 5) {
                    ForEach(0..<total, id: \.self) { n in
                        Circle()
                            .fill(n < value ? tint : Color.white.opacity(0.14))
                            .frame(width: 9, height: 9)
                    }
                }
                .accessibilityHidden(true)
            }
            Text("\(value)")
                .font(AppFont.display(22, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(tint)
                .frame(minWidth: 22, alignment: .trailing)
                .contentTransition(.numericText(value: Double(value)))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func progressLengthAccessibility(_ game: Match, title: String, values: [Int], total: Int) -> String {
        let scores = game.players.indices.map { index in
            let value = values.indices.contains(index) ? values[index] : 0
            return "\(game.players[index].name) \(value)"
        }.joined(separator: ", ")
        return "\(title) z \(total): \(scores)"
    }

    /// Spodní lišta: Liquid Glass — Zpět, režim hlasu a způsob zápisu.
    @ViewBuilder
    private func bottomBar(_ game: Match) -> some View {
        let humanInput = !paused && game.legWinner == nil && !game.needsBullOff && !game.needsDecidingStarter && !showingBotBoard && !isHoldingVisit && !showDecidingStarter
        let canUndo = isHoldingVisit || !game.currentDarts.isEmpty || !game.visits.isEmpty
        let showTotalConfirm = humanInput && surface == .total && canUseTotal(game)
        let showVoiceModes = surface == .voice && canUseTotal(game) && !isHoldingVisit
        if !paused && (game.legWinner == nil || isHoldingVisit) {
            // Menu držíme mimo GlassEffectContainer — jinak iOS 26 při změně ikony/layoutu glitchuje výběr.
            HStack(spacing: 10) {
                GlassEffectContainer(spacing: 10) {
                    HStack(spacing: 10) {
                        if link.isOnline {
                            onlineTurnBadge(game)
                        } else {
                        Button { undo() } label: {
                            Label("Zpět", systemImage: "arrow.uturn.backward")
                                .font(.headline)
                                .labelStyle(.titleAndIcon)
                                .foregroundStyle(.primary)
                                .padding(.horizontal, 16)
                                .frame(minHeight: 52)
                                .contentShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        .glassEffect(.regular.interactive(), in: Capsule())
                        .disabled(!canUndo)
                        .opacity(canUndo ? 1 : 0.45)
                        .accessibilityHint("Vrátí poslední šipku, včetně hodů bota")
                        }

                        if showTotalConfirm {
                            Button { resolveTotal(game) } label: {
                                Label(sumText.isEmpty ? "Potvrdit" : "Potvrdit \(sumText)", systemImage: "checkmark")
                                    .font(.headline)
                                    .foregroundStyle(sumText.isEmpty ? Color.secondary : Theme.onAccent)
                                    .frame(maxWidth: .infinity, minHeight: 52)
                                    .contentShape(Capsule())
                            }
                            .buttonStyle(.plain)
                            .glassEffect(
                                sumText.isEmpty ? .regular : .regular.tint(MatchColors.finish).interactive(),
                                in: Capsule()
                            )
                            .disabled(sumText.isEmpty)
                            .accessibilityHint("Odečte zadaný součet kola")
                        } else if showVoiceModes {
                            voiceModeBottomToggle(game)
                        } else {
                            Spacer(minLength: 0)
                        }
                    }
                }

                Menu {
                    scoringSurfaceMenu(game)
                } label: {
                    Image(systemName: surface.icon)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.primary)
                        .frame(width: 52, height: 52)
                        .contentShape(Circle())
                        .glassEffect(.regular.interactive(), in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Způsob zápisu")
                .accessibilityValue(surfaceMenuTitle(game))
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 6)
            .frame(maxWidth: 780)
            .frame(maxWidth: .infinity)
            .animation(reduceMotion ? nil : .snappy(duration: 0.22), value: surface)
        }
    }

    /// Online místo vracení šipek: kdo je na tahu.
    private func onlineTurnBadge(_ game: Match) -> some View {
        let mine = link.yourTurn
        let name = game.players.indices.contains(game.active) ? game.players[game.active].name : "Soupeř"
        return HStack(spacing: 8) {
            Circle()
                .fill(mine ? MatchColors.finish : Color.white.opacity(0.4))
                .frame(width: 8, height: 8)
            Text(mine ? "Jsi na tahu" : "Hází \(name)")
                .font(.headline)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .contentTransition(.opacity)
        }
        .foregroundStyle(.primary)
        .padding(.horizontal, 16)
        .frame(minHeight: 52)
        .glassEffect(.regular, in: Capsule())
        .animation(reduceMotion ? nil : .smooth(duration: 0.25), value: mine)
        .accessibilityElement(children: .combine)
    }

    private func boardInput(_ game: Match) -> some View {
        let guide = checkoutGuide(game, shown: game.liveProjection, thrown: game.currentDarts.count)
        return matchDartboard(marks: game.currentDarts, interactive: true, suggestion: guide.route.first, onHit: hit)
    }

    /// Stejný rám pro živý i zmrazený terč — ať po odhodu neposkočí layout.
    private func matchDartboard(marks: [Dart], interactive: Bool, suggestion: Dart? = nil, markBeds: Bool = false, onHit: @escaping (Dart) -> Void = { _ in }) -> some View {
        ScoringDartboard(marks: marks, interactive: interactive, suggestion: suggestion, markBeds: markBeds, onHit: onHit)
    }

    private func checkoutGuide(_ game: Match, shown: Match, thrown: Int) -> ScoringChrome.CheckoutGuide {
        guard !isHoldingVisit, game.currentPlayer.botLevel == nil else { return ScoringChrome.CheckoutGuide() }
        guard game.config.mode == .x01 else { return ScoringChrome.CheckoutGuide() }
        let state = shown.states[game.active]
        return ScoringChrome.checkoutGuide(
            remaining: state.remaining,
            rule: game.config.outRule(for: game.active),
            thrown: thrown,
            opened: state.opened,
            enabled: game.config.settings.checkoutHints
        )
    }
    private func dartGrid(_ game: Match, shown: Match) -> some View {
        ManualScorePad(
            multiplier: $multiplier,
            focus: padFocus(game, shown: shown),
            numbers: scorePadNumbers(game),
            onSelect: { store.selectionHaptic() },
            onHit: hit
        )
    }

    /// Cricket ukáže jen zvolená pole. Ostatní režimy nechají celou klávesnici.
    private func scorePadNumbers(_ game: Match) -> [Int]? {
        game.config.mode == .cricket ? game.config.settings.activeCricketNumbers : nil
    }

    /// Číselník i součet nemají čekat, než scroll rozhodne, jestli jde o posun.
    private var pinsScoringPad: Bool {
        if isHoldingVisit { return holdSurface == .grid || holdSurface == .total }
        return surface == .grid || surface == .total
    }

    /// Číselná mřížka zůstane na obrazovce i v krátké pauze po třetí šipce.
    private var keepsNumberPad: Bool {
        if isHoldingVisit { return holdSurface == .grid }
        return surface == .grid
    }
    /// Online server potřebuje každou šipku zvlášť, součet kola tam nejde.
    private func canUseTotal(_ game: Match) -> Bool { !link.isOnline && game.config.mode == .x01 && !game.config.anyDoubleIn(players: game.players.count) }

    /// Mikrofon smí běžet jen při tvém zápisu — ne během bota, holdu ani pauzy.
    private func isVoiceArmed(_ game: Match) -> Bool {
        surface == .voice
            && !paused
            && !isHoldingVisit
            && legCeremony == nil
            && game.legWinner == nil
            && !game.needsBullOff
            && !game.needsDecidingStarter
            && !game.finished
            && game.currentPlayer.botLevel == nil
            && !game.isGhostTurn
            && (!link.isOnline || link.yourTurn)
            && !showProgress
            && !showDecidingStarter
    }

    private var voiceSyncKey: String {
        guard let game = activeMatch else { return "none" }
        return "\(surface.rawValue)-\(game.active)-\(isHoldingVisit)-\(paused)-\(showProgress)-\(game.finished)-\(game.legWinner ?? -1)-\(game.needsBullOff)-\(game.needsDecidingStarter)-\(botIsThrowing)"
    }

    private func effectiveVoiceMode(for game: Match) -> VoiceScoreMode {
        guard canUseTotal(game), game.currentDarts.isEmpty else { return .darts }
        return voiceMode
    }

    private func voiceInput(_ game: Match) -> some View {
        let armed = isVoiceArmed(game)
        let live = voice.transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        let listening = armed && voice.isListening
        let recognizing = armed && voice.phase == .recognizing
        let mode = effectiveVoiceMode(for: game)
        let unavailable: String? = {
            if case .unavailable(let message) = voice.phase { return message }
            return nil
        }()
        let headline: String = {
            if unavailable != nil { return "Nedostupné" }
            if isHoldingVisit { return holdingBust(game) ? "Přehoz" : (holdSurface == .total ? "Součet zapsán" : "Kolo hotovo") }
            if botIsThrowing || holdingBotVisit { return "Vypnuto" }
            if paused { return "Pauza" }
            if recognizing { return "Zapisuju" }
            if listening { return "Poslouchám" }
            return "Připraven"
        }()
        let detail: String? = {
            if let unavailable { return unavailable }
            if isHoldingVisit {
                if holdingBust(game) { return "BUST" }
                if holdSurface == .total {
                    return "Součet \(holdDarts.reduce(0) { $0 + $1.score })"
                }
                let labels = holdDarts.map(\.label).joined(separator: " · ")
                return labels.isEmpty ? nil : labels
            }
            if botIsThrowing || holdingBotVisit {
                let name = holdPlayer.map { game.players[$0].name } ?? game.currentPlayer.name
                return name
            }
            if paused { return nil }
            if recognizing { return live.isEmpty ? nil : live }
            if let command = voice.lastCommandLabel { return command }
            switch voice.phase {
            case .listening:
                if live.isEmpty || live == "Poslouchám…" || live == "Slyším…" { return nil }
                return live
            case .askingPermission, .preparing:
                return "Zapínám…"
            case .idle:
                return voice.lastHeard.isEmpty ? nil : voice.lastHeard
            case .unavailable(let message):
                return message
            case .recognizing:
                return live.isEmpty ? nil : live
            }
        }()

        return VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 16) {
                voiceMicBadge(armed: armed, listening: listening, recognizing: recognizing, unavailable: unavailable != nil)
                    .accessibilityLabel(listening ? "Mikrofon zapnutý" : "Mikrofon vypnutý")
                    .accessibilityValue(headline)

                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Text(headline.uppercased())
                            .font(AppFont.caption(11, weight: .heavy))
                            .tracking(1.0)
                            .foregroundStyle(listening ? MatchColors.ink.opacity(0.5) : MatchColors.ink.opacity(0.32))
                        if armed && listening && !recognizing {
                            Text("ŽIVĚ")
                                .font(AppFont.caption(10, weight: .heavy))
                                .foregroundStyle(MatchColors.coral)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(MatchColors.coral.opacity(0.14), in: Capsule())
                        }
                        Text(mode.title)
                            .font(AppFont.caption(10, weight: .bold))
                            .foregroundStyle(MatchColors.ink.opacity(0.4))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(MatchColors.ink.opacity(0.06), in: Capsule())
                    }
                    if let detail {
                        Text(detail)
                            .font(AppFont.body(16, weight: .semibold))
                            .foregroundStyle(MatchColors.ink.opacity(armed || unavailable != nil ? 1 : 0.5))
                            .lineLimit(2)
                            .minimumScaleFactor(0.82)
                            .contentTransition(.opacity)
                            .animation(.easeOut(duration: 0.16), value: detail)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 18)
            .padding(.top, 18)
            .padding(.bottom, armed ? 12 : 16)

            if armed {
                voiceLevelMeter(level: voice.inputLevel, active: listening && !recognizing)
                    .padding(.horizontal, 18)
                    .padding(.bottom, 16)
            } else if unavailable == nil {
                Text(botIsThrowing || holdingBotVisit ? "Zapne se na tvoje hody" : "Čekám")
                    .font(AppFont.caption(12, weight: .semibold))
                    .foregroundStyle(MatchColors.ink.opacity(0.38))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 18)
                    .padding(.bottom, 16)
            }
        }
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: listening
                            ? [Color.white, Theme.brand.opacity(0.12)]
                            : [Color.white, Color.white],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .strokeBorder(
                            listening ? Theme.brand.opacity(0.65) : MatchColors.ink.opacity(0.06),
                            lineWidth: listening ? 1.5 : 1
                        )
                }
        )
        .opacity(unavailable != nil ? 0.92 : (armed ? 1 : 0.86))
        .animation(.easeInOut(duration: 0.22), value: armed)
        .animation(.easeInOut(duration: 0.22), value: listening)
        .onAppear {
            syncVoiceListening(for: game)
        }
        .onChange(of: voiceSyncKey) { _, _ in
            if let live = activeMatch {
                syncVoiceListening(for: live)
            }
        }
        .onChange(of: voiceMode) { _, _ in
            voice.updateMode(effectiveVoiceMode(for: game))
        }
        .onChange(of: game.currentDarts.count) { _, _ in
            voice.updateMode(effectiveVoiceMode(for: game))
        }
        // stop řeší changeSurface / isVoiceArmed — dvojité stop() při zmizení race-uje s novým startem.
    }

    private func voiceMicBadge(armed: Bool, listening: Bool, recognizing: Bool, unavailable: Bool) -> some View {
        let size: CGFloat = armed ? 76 : 58
        let symbol = unavailable || !armed ? "mic.slash.fill" : (recognizing ? "waveform" : "mic.fill")
        return ZStack {
            if listening && !recognizing && !reduceMotion {
                Circle()
                    .stroke(Theme.brand.opacity(0.35), lineWidth: 2)
                    .frame(width: size + 18 + voice.inputLevel * 16, height: size + 18 + voice.inputLevel * 16)
                    .opacity(0.55)
            }
            Circle()
                .fill(
                    listening
                        ? (recognizing ? MatchColors.amber : Theme.brand)
                        : (armed ? MatchColors.ink.opacity(0.08) : Color.black.opacity(0.05))
                )
                .frame(width: size, height: size)
                .shadow(color: listening ? Theme.brand.opacity(0.4) : .clear, radius: 14, y: 5)
                .overlay {
                    Image(systemName: symbol)
                        .font(.system(size: armed ? 28 : 22, weight: .bold))
                        .foregroundStyle(
                            listening ? MatchColors.ink : MatchColors.ink.opacity(armed ? 0.48 : 0.22)
                        )
                        .symbolEffect(.pulse, options: .repeating, isActive: listening && !recognizing && !reduceMotion)
                }
        }
        .frame(width: armed ? 96 : 64, height: armed ? 96 : 64)
    }

    private func voiceLevelMeter(level: CGFloat, active: Bool) -> some View {
        HStack(spacing: 3) {
            ForEach(0..<12, id: \.self) { i in
                let threshold = CGFloat(i) / 12
                let on = active && level > threshold
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(on ? Theme.brand : MatchColors.ink.opacity(0.08))
                    .frame(height: 6 + CGFloat(i) * 1.4)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 28, alignment: .bottom)
        .opacity(active ? 1 : 0.45)
        .animation(.easeOut(duration: 0.08), value: level)
    }

    private func syncVoiceListening(for game: Match) {
#if targetEnvironment(simulator)
        if case .unavailable = voice.phase { return }
        voice.start(mode: .darts) { _ in }
        return
#endif
        guard isVoiceArmed(game) else {
            if voice.isListening || voice.phase != .idle {
                if case .unavailable = voice.phase { return }
                voice.stop()
            }
            return
        }
        if voice.isListening {
            voice.updateMode(effectiveVoiceMode(for: game))
            return
        }
        startVoiceListening(for: game)
    }

    private func startVoiceListening(for game: Match) {
        let mode = effectiveVoiceMode(for: game)
        voice.start(mode: mode) { command in
            guard let live = activeMatch, isVoiceArmed(live) else { return }
            applyVoiceCommand(command, gameCanTotal: canUseTotal(live))
            if let updated = activeMatch {
                voice.updateMode(effectiveVoiceMode(for: updated))
            }
        }
    }

    private func applyVoiceCommand(_ command: VoiceScoreCommand, gameCanTotal: Bool) {
        guard !paused, !isHoldingVisit, legCeremony == nil else { return }
        switch command {
        case .bust:
            guard gameCanTotal else {
                error = "Přehoz hlasem jde jen u X01 bez double-in."
                return
            }
            bustPrompt = true
        case .total(let score):
            guard gameCanTotal else {
                error = "Součet \(score) hlasem jde jen v X01 bez double-in."
                return
            }
            guard let game = activeMatch else { return }
            if !game.currentDarts.isEmpty {
                error = "Součet jde jen na začátku kola. Dokonči nebo vrať šipky."
                return
            }
            sumText = "\(score)"
            resolveTotal(game)
            // Zobraz „180“, ne syntetické T20 (60·60·60).
            if isHoldingVisit { holdSurface = .total }
        case .darts(let darts):
            for dart in darts {
                if isHoldingVisit { break }
                hit(dart)
            }
        }
    }

    private func surfaceMenuTitle(_ game: Match) -> String {
        if surface == .voice {
            return "Hlas · \(effectiveVoiceMode(for: game).title)"
        }
        return surface.title
    }

    /// Vedle mikrofonu: Šipky / Součet jako liquid glass pilulky.
    private func voiceModeBottomToggle(_ game: Match) -> some View {
        let mode = effectiveVoiceMode(for: game)
        let totalLocked = !game.currentDarts.isEmpty
        return HStack(spacing: 8) {
            ForEach(VoiceScoreMode.allCases) { item in
                let selected = mode == item
                let locked = item == .total && totalLocked
                Button {
                    guard !locked else { return }
                    selectVoiceMode(item)
                } label: {
                    Text(item.title)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(selected ? Theme.onAccent : (locked ? Color.secondary.opacity(0.45) : .primary))
                        .padding(.horizontal, 14)
                        .frame(minHeight: 52)
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .glassEffect(
                    selected ? .regular.tint(Theme.brand).interactive() : .regular.interactive(),
                    in: Capsule()
                )
                .disabled(locked)
                .opacity(locked ? 0.55 : 1)
                .accessibilityAddTraits(selected ? .isSelected : [])
                .accessibilityLabel(item.title)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Režim hlasu")
        .accessibilityValue(mode.title)
    }

    @ViewBuilder
    private func scoringSurfaceMenu(_ game: Match) -> some View {
        surfaceMenuButton(.grid, selected: surface == .grid)
        surfaceMenuButton(.board, selected: surface == .board)
        if canUseTotal(game) {
            surfaceMenuButton(.total, selected: surface == .total, disabled: !game.currentDarts.isEmpty)
        }
        surfaceMenuButton(.voice, selected: surface == .voice)
        surfaceMenuButton(.camera, selected: surface == .camera)
    }

    private func surfaceMenuButton(_ item: ScoringSurface, selected: Bool, disabled: Bool = false) -> some View {
        Button {
            changeSurface(item)
        } label: {
            Label(item.title, systemImage: selected ? "checkmark" : item.icon)
        }
        .disabled(disabled)
    }

    private func selectVoiceMode(_ mode: VoiceScoreMode) {
        guard voiceMode != mode || surface != .voice else { return }
        store.selectionHaptic()
        voiceMode = mode
        if surface != .voice {
            changeSurface(.voice)
            return
        }
        if let game = activeMatch {
            voice.updateMode(effectiveVoiceMode(for: game))
        }
    }

    private func changeSurface(_ value: ScoringSurface) {
        guard let live = activeMatch else { return }
        if value == .total && !live.currentDarts.isEmpty {
            error = "Součet lze zapnout na začátku kola. Dokonči nebo vrať rozehrané šipky."
            return
        }
        if value == surface { return }
        store.selectionHaptic()
        if surface == .voice, value != .voice { voice.stop() }

        withAnimation(reduceMotion ? nil : .snappy(duration: 0.22)) {
            surface = value
            sumText = ""
        }

        // Preferenci entry ulož bez zbytečného přepisu, ať Menu stihne dismiss bez remountu celého zápasu.
        let entry: EntryStyle = value == .total ? .total : .darts
        if live.config.settings.entry != entry {
            Task { @MainActor in
                guard var game = activeMatch else { return }
                var options = game.config.settings
                guard options.entry != entry else { return }
                options.entry = entry
                game.config.options = options
                activeMatch = game
            }
        }
    }
    private func hit(_ dart: Dart) {
        guard !paused, !isHoldingVisit, legCeremony == nil, !showDecidingStarter, var game = activeMatch, game.currentPlayer.botLevel == nil, !game.finished, game.legWinner == nil, !game.needsBullOff, !game.needsDecidingStarter else { return }
        guard !link.isOnline || link.yourTurn else { return }
        let thrower = game.active
        let count = game.visits.count
        do {
            try game.recordDart(dart)
            let visitFinished = game.visits.count > count
            if visitFinished, let visit = game.visits.last {
                if visit.bust {
                    store.feedback(announce: surface != .voice, spoken: "Přehoz")
                } else {
                    store.feedback(visit.credited, announce: surface != .voice, checkout: visit.checkout, matchWon: game.finished)
                }
                multiplier = 1
                applyVisitHold(game: game, darts: visit.darts, player: thrower, fromBot: false)
            } else {
                store.tapHaptic(.light)
                activeMatch = game
            }
        } catch { self.error = error.localizedDescription }
    }
    private func rewind(to visit: Visit) {
        guard var game = activeMatch else { return }
        guard game.rewind(before: visit.id) else {
            error = "Na toto kolo se už nejde vrátit. Starší zápis nemá uložený stav."
            return
        }
        holdGeneration += 1
        isHoldingVisit = false
        holdPlayer = nil
        legCeremony = nil
        oneEightyFlash = nil
        ceremonyLeaving = false
        ceremonyDismissing = false
        holdDarts = []
        sumText = ""
        multiplier = 1
        withAnimation(reduceMotion ? nil : .snappy(duration: 0.35)) { activeMatch = game }
        revision = UUID()
        showLog = false
        store.feedback(nil)
    }
    private func undo() {
        guard !link.isOnline, legCeremony == nil, var game = activeMatch else { return }
        store.tapHaptic(.soft)
        if isHoldingVisit {
            holdGeneration += 1
            isHoldingVisit = false
            holdPlayer = nil
            oneEightyFlash = nil
        }
        game.undoLastInput()
        withAnimation(reduceMotion ? nil : .snappy(duration: 0.35)) { activeMatch = game }
        if cameraHits.count > game.currentDarts.count { cameraHits = Array(cameraHits.prefix(game.currentDarts.count)) }
        sumText = ""
        multiplier = 1
        revision = UUID()
        holdDarts = game.currentPlayer.botLevel != nil || game.isGhostTurn || !game.currentDarts.isEmpty ? game.currentDarts : []
        if !game.currentDarts.isEmpty && surface == .total { surface = .grid }
    }
    /// Arm hold *before* publishing the advanced match so the UI never flashes the next player's surface.
    private func applyVisitHold(game: Match, darts: [Dart], player: Int, fromBot: Bool) {
        holdDarts = darts
        holdPlayer = player
        holdSurface = fromBot ? .board : surface
        let celebrate180 = game.visits.last.map {
            OneEightyCelebration.shouldPlay(credited: $0.credited, bust: $0.bust, reduceMotion: reduceMotion)
        } == true
        if celebrate180 {
            oneEightyFlash = UUID()
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        } else if game.visits.last?.bust == true {
            UINotificationFeedbackGenerator().notificationOccurred(.error)
        }
        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            isHoldingVisit = true
        }
        // Skóre se odečítá vlastní animací čísla. Zbytek hřiště se při tom nehýbe, ať rychlé šipky nezaseknou přepnutí tahu.
        if !fromBot && holdSurface == .grid {
            activeMatch = game
        } else {
            withAnimation(reduceMotion ? nil : .snappy(duration: 0.35)) {
                activeMatch = game
            }
        }
        scheduleVisitHold(darts: darts, celebrate180: celebrate180)
    }
    @MainActor private func scheduleVisitHold(darts: [Dart], celebrate180: Bool = false) {
        let delay = activeMatch?.config.settings.botDelay ?? 1.5
        let legOver = activeMatch?.legWinner != nil
        // Keep the whole throw screen visible long enough to read before the turn flips.
        // A winning visit goes straight to the ceremony, which shows the checkout itself.
        // Čísla: bez náhledu terče, jen krátká odezva.
        var hold: Double
        if legOver {
            hold = 0.35
        } else if holdSurface == .grid {
            hold = ScoringChrome.gridVisitHoldSeconds(reduceMotion: reduceMotion)
        } else {
            hold = ScoringChrome.visitHoldSeconds(botDelay: delay, reduceMotion: reduceMotion)
        }
        // 180 GIF (~2,9 s) — hold nesmí skončit uprostřed animace.
        if celebrate180 {
            hold = max(hold, OneEightyCelebration.duration)
        }
        if activeMatch?.visits.last?.bust == true {
            hold = max(hold, reduceMotion ? 0.9 : 1.6)
        }
        holdGeneration += 1
        let generation = holdGeneration
        Task { @MainActor in
            // Nejdřív vykresli tři šipky, teprve potom odpočítávej. Jinak pauza vyprší během záseku a tah skočí naslepo.
            await Task.yield()
            try? await Task.sleep(nanoseconds: UInt64(hold * 1_000_000_000))
            guard generation == holdGeneration, isHoldingVisit, holdDarts == darts, correcting == nil, editingDart == nil else { return }
            finishVisitHold()
        }
    }
    @MainActor private func finishVisitHold() {
        if holdSurface == .camera { learnConfirmedHits() }
        guard let game = activeMatch else {
            isHoldingVisit = false
            holdDarts = []
            holdPlayer = nil
            return
        }
        if let winner = game.legWinner {
            // Poslední hod zůstane pod ceremonií, ať obrazovka neskočí do prázdna.
            presentLegCeremony(game, winner: winner)
            return
        }
        if holdSurface == .grid {
            var quiet = Transaction(animation: nil)
            quiet.disablesAnimations = true
            withTransaction(quiet) {
                isHoldingVisit = false
                holdDarts = []
                holdPlayer = nil
            }
        } else {
            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.28)) {
                isHoldingVisit = false
                holdDarts = []
                holdPlayer = nil
            }
        }
        if game.needsBullOff {
            showProgress = false
            decidingLeg = true
        } else {
            revision = UUID()
        }
    }
    /// Průměr uživatele za právě dohraný leg. U jiných režimů než X01 se neukazuje.
    private func userLegAverage(_ game: Match) -> Double? {
        guard game.config.mode == .x01,
              let id = store.profile?.id,
              let index = game.players.firstIndex(where: { $0.id == id }),
              game.thrownDarts(for: index, leg: game.leg) > 0 else { return nil }
        return game.average(for: index, leg: game.leg)
    }
    private func presentLegCeremony(_ game: Match, winner: Int) {
        let visit = game.visits.last { $0.player == winner && $0.leg == game.leg && $0.checkout }
            ?? game.visits.last { $0.player == winner && $0.leg == game.leg }
        let auto = game.finished ? 4.5 : 3.5
        let ceremony = LegCeremony(
            winner: winner,
            leg: game.leg,
            matchFinished: game.finished,
            legs: game.states.map(\.legs),
            sets: game.states.map(\.sets),
            names: game.players.map(\.name),
            checkoutScore: visit?.credited ?? 0,
            checkoutDarts: visit?.darts.map(\.label) ?? [],
            isCheckout: visit?.checkout == true,
            legsToWin: game.config.legsToWin,
            setsToWin: game.config.setsToWin,
            legSlots: game.config.shownLegs,
            setSlots: game.config.shownSets,
            playsSets: game.config.playsSets,
            setClosed: !game.finished && game.config.playsSets && game.states.contains { $0.legs >= game.config.legsToWin },
            duration: auto,
            byBullOff: game.bullOffLegs?[game.leg] == winner,
            winnerPhoto: playerLook(game, index: winner).photo,
            winnerAsset: playerLook(game, index: winner).asset,
            userLegAverage: userLegAverage(game)
        )
        performWithoutAnimation {
            ceremonyLeaving = false
            ceremonyDismissing = false
            resultShown = false
            showProgress = false
            legCeremony = ceremony
        }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        let ceremonyID = ceremony.id
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(auto * 1_000_000_000))
            guard legCeremony?.id == ceremonyID else { return }
            dismissLegCeremony()
        }
    }
    private func dismissLegCeremony() {
        guard let ceremony = legCeremony, !ceremonyDismissing else { return }
        ceremonyDismissing = true
        performWithoutAnimation {
            if ceremony.matchFinished { revealMatchResult() } else { revealNextLeg() }
        }
        if reduceMotion {
            commitLegCeremonyDismiss()
            return
        }
        let ceremonyID = ceremony.id
        Task { @MainActor in
            // Další leg se usadí ještě pod neprůhlednou ceremonií. Pak jen průhlednost, lišta zůstane schovaná.
            try? await Task.sleep(nanoseconds: 50_000_000)
            guard legCeremony?.id == ceremonyID else { return }
            ceremonyLeaving = true
            try? await Task.sleep(nanoseconds: UInt64(CeremonyFade.seconds * 1_000_000_000))
            guard ceremonyLeaving, legCeremony?.id == ceremonyID else { return }
            commitLegCeremonyDismiss()
        }
    }
    /// Skóre se přepne na start dalšího legu bez vlastního pohybu — pohyb obstará prolínání.
    private func revealNextLeg() {
        guard var game = activeMatch, game.legWinner != nil, !game.finished else { return }
        let newSet = legCeremony?.setClosed == true
        if link.isOnline { OnlineMatchLink.advanceLeg(&game) } else { game.nextLeg() }
        var quiet = Transaction(animation: nil)
        quiet.disablesAnimations = true
        withTransaction(quiet) {
            activeMatch = game
            isHoldingVisit = false
            holdDarts = []
            holdPlayer = nil
            multiplier = 1
            sumText = ""
        }
        if game.needsDecidingStarter {
            showDecidingStarter = true
            return
        }
        announceLegStart(game, newSet: newSet)
    }
    private func announceLegStart(_ game: Match, newSet: Bool) {
        let starter = game.players.indices.contains(game.active) ? game.players[game.active].name : "Hráč"
        let announcement = "\(newSet ? "Nový set" : "Nový leg") \(game.leg). Začíná \(starter)."
        let delay = reduceMotion ? 0 : CeremonyFade.seconds
        Task { @MainActor in
            if delay > 0 { try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000)) }
            UIAccessibility.post(notification: .announcement, argument: announcement)
            if newSet {
                store.announceMoment(.newSet, fallback: .newLeg)
            } else {
                store.announceMoment(.newLeg)
            }
        }
    }
    private func decidingStarterPicks(_ game: Match) -> [StarterPick] {
        game.players.indices.map { index in
            let player = game.players[index]
            let look = playerLook(game, index: index)
            let detail: String = {
                if game.isGhost(index) { return "Ghost" }
                if player.botLevel != nil { return "Bot" }
                if player.id == store.profile?.id { return "Ty" }
                return "Hráč"
            }()
            return StarterPick(
                id: index,
                name: player.name,
                detail: detail,
                photo: look.photo,
                asset: look.asset,
                bot: player.botLevel != nil,
                tint: Theme.playerColor(index)
            )
        }
    }
    private func resolveDecidingStarter(_ player: Int) {
        guard var game = activeMatch, game.needsDecidingStarter else {
            showDecidingStarter = false
            return
        }
        game.resolveDecidingStarter(to: player)
        activeMatch = game
        showDecidingStarter = false
        revision = UUID()
        announceLegStart(game, newSet: false)
    }
    /// Statistiky jsou celé vidět ještě pod ceremonií, ať po prolínání nic nedojíždí.
    private func revealMatchResult() {
        var quiet = Transaction(animation: nil)
        quiet.disablesAnimations = true
        withTransaction(quiet) {
            resultShown = true
            isHoldingVisit = false
            holdDarts = []
            holdPlayer = nil
        }
    }
    private func animateResultIn() {
        guard !resultShown else { return }
        resultShown = true
    }
    private func commitLegCeremonyDismiss() {
        performWithoutAnimation {
            legCeremony = nil
            ceremonyLeaving = false
            ceremonyDismissing = false
        }
    }
    /// Lišta a safe area se nesmí animovat. Rozjetý toolbar nechá hru viset nahoře pod lištou.
    private func performWithoutAnimation(_ updates: () -> Void) {
        UIView.setAnimationsEnabled(false)
        var quiet = Transaction(animation: nil)
        quiet.disablesAnimations = true
        withTransaction(quiet, updates)
        DispatchQueue.main.async {
            UIView.setAnimationsEnabled(true)
        }
    }
    private func saveAndLeave() {
        guard !leavingHome else { return }
        leavingHome = true
        flushClock()
        let wait = MatchSavedSplash.hold(reduceMotion: reduceMotion)
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000))
            store.returnHome()
            dismiss()
        }
    }

    private func leaveToHome() {
        saveAndLeave()
    }
    private func clockTracking(_ content: some View) -> some View {
        content
            .task {
                while !Task.isCancelled {
                    try? await Task.sleep(nanoseconds: 30_000_000_000)
                    if clockStart != nil { flushClock(keepRunning: true) }
                }
            }
            .task {
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(1))
                    guard let game = activeMatch, !game.finished else { continue }
                    publishLiveClock(game)
                }
            }
            .task(id: shouldWatchIdle) { await pauseWhenIdle() }
            .onChange(of: playActivity) { _, _ in lastActivity = Date() }
            .onChange(of: scenePhase) { _, phase in syncClock(phase) }
            .onChange(of: paused) { _, isPaused in
                syncClock()
                if !isPaused { lastActivity = Date() }
            }
            .onChange(of: activeMatch?.finished ?? true) { _, _ in syncClock() }
    }
    /// Živá hra v popředí. Ceremonie a hotový zápas se samy nepauzují.
    private var shouldWatchIdle: Bool {
        !link.isOnline && scenePhase == .active && !paused && !leavingHome && legCeremony == nil && activeMatch.map { !$0.finished } == true
    }
    /// Cokoli, čím hra postupuje: šipka, kolo, hráč, leg, rozepsaný součet nebo přepnutí zápisu.
    private var playActivity: String {
        guard let game = activeMatch else { return "none" }
        let darts = game.currentDarts.map(\.label).joined(separator: ",")
        return "\(game.visits.count)|\(darts)|\(game.active)|\(game.leg)|\(game.legWinner ?? -1)|\(sumText)|\(multiplier)|\(surface.rawValue)"
    }
    private func pauseWhenIdle() async {
        guard shouldWatchIdle else { return }
        while !Task.isCancelled && shouldWatchIdle {
            if Date().timeIntervalSince(lastActivity) >= idlePauseAfter {
                showPause()
                return
            }
            try? await Task.sleep(nanoseconds: 1_000_000_000)
        }
    }
    private var clockRuns: Bool {
        scenePhase == .active && !paused && activeMatch.map { !$0.finished } == true
    }
    private func syncClock(_ phase: ScenePhase? = nil) {
        let phase = phase ?? scenePhase
        let runs = phase == .active && !paused && activeMatch?.finished != true
        if runs {
            if clockStart == nil { clockStart = Date() }
            publishLiveClock(activeMatch, phase: phase)
        } else if clockStart != nil {
            flushClock(for: phase)
        } else {
            publishLiveClock(activeMatch, phase: phase)
        }
    }
    /// Připíše uběhlý úsek do zápasu. Průběžně, aby se čas neztratil ani při pádu appky.
    private func flushClock(keepRunning: Bool = false, for phase: ScenePhase? = nil) {
        guard let start = clockStart else { return }
        let now = Date()
        let running = keepRunning && clockRuns
        clockStart = running ? now : nil
        guard var game = activeMatch else { return }
        game.addPlayTime(from: start, to: now)
        publishLiveClock(game, phase: phase)
        activeMatch = game
    }
    /// Web dostane stejný čas jako tabule. Pauza na telefonu i odchod z aplikace ten čas zastaví, web ukáže pauzu.
    private func publishLiveClock(_ game: Match?, phase: ScenePhase? = nil) {
        // Online zápas na web posílá server, ne tahle tabule.
        guard !link.isOnline else { return }
        guard let game else {
            DartiqoAccount.shared.noteLiveClock(paused: false, played: 0, running: false, match: nil, store: store)
            return
        }
        let leftApp = (phase ?? scenePhase) != .active
        let hold = !game.finished && (paused || leftApp)
        let running = clockStart != nil && !hold
        DartiqoAccount.shared.noteLiveClock(
            paused: hold,
            played: frozenBoardSeconds(game),
            running: running,
            match: game,
            store: store
        )
    }
    private func awardBullOff(_ winner: Int) {
        guard var game = activeMatch, game.needsBullOff else { decidingLeg = false; return }
        game.awardBullOff(to: winner)
        activeMatch = game
        decidingLeg = false
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 450_000_000)
            guard let current = activeMatch, current.legWinner == winner, legCeremony == nil else { return }
            presentLegCeremony(current, winner: winner)
        }
    }
    private func continuePastDartLimit() {
        guard var game = activeMatch, game.needsBullOff else { return }
        game.continuePastDartLimit()
        activeMatch = game
        revision = UUID()
    }
    private func bullOffCard(_ game: Match) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "scope").font(.system(size: 34, weight: .semibold)).foregroundStyle(MatchColors.amber)
            Text("Limit \(game.config.settings.dartLimit ?? 0) šipek vypršel")
                .font(AppFont.title(20))
            Text("Nikdo leg nezavřel. Jak ho chceš rozhodnout?")
                .font(AppFont.body(15))
                .foregroundStyle(.white.opacity(0.7))
                .multilineTextAlignment(.center)
            VStack(spacing: 10) {
                Button { continuePastDartLimit() } label: {
                    HStack(spacing: 13) {
                        Image(systemName: "play.fill")
                            .font(.subheadline.weight(.bold))
                            .frame(width: 34, height: 34)
                            .background(.white.opacity(0.10), in: Circle())
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Dohrát leg")
                                .font(.headline)
                            Text("Pokračovat bez limitu")
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.58))
                        }
                        Spacer(minLength: 8)
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.white.opacity(0.35))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .frame(maxWidth: .infinity, minHeight: 62)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .glassEffect(.regular.interactive(), in: RoundedRectangle(cornerRadius: 16, style: .continuous))

                Button { decidingLeg = true } label: {
                    HStack(spacing: 13) {
                        Image(systemName: "scope")
                            .font(.subheadline.weight(.bold))
                            .frame(width: 34, height: 34)
                            .background(.black.opacity(0.10), in: Circle())
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Rozhoz na střed")
                                .font(.headline)
                            Text("Bližší šipka bere leg")
                                .font(.caption)
                                .foregroundStyle(.black.opacity(0.58))
                        }
                        Spacer(minLength: 8)
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.black.opacity(0.35))
                    }
                    .foregroundStyle(.black)
                    .padding(.horizontal, 14)
                    .frame(maxWidth: .infinity, minHeight: 62)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .glassEffect(.regular.tint(MatchColors.amber).interactive(), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
        }
        .frame(maxWidth: .infinity)
        .padding(24)
        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }
    /// Celá obrazovka přes lištu i stavový řádek. Krátké shrnutí legu se skóre.
    private func legCeremonyScreen(_ ceremony: LegCeremony) -> some View {
        LegCeremonyView(
            ceremony: ceremony,
            reduceMotion: reduceMotion,
            leaving: ceremonyLeaving,
            onContinue: dismissLegCeremony
        )
    }
    private func ghostRaceStrip(human: Double, ghost: Double) -> some View {
        let ahead = human > ghost && human > 0
        return HStack(spacing: 8) {
            HStack(spacing: 4) {
                Text("Ty")
                liveNumber(String(format: "%.1f", human), number: human, font: AppFont.caption(12, weight: .bold))
            }
            .font(AppFont.caption(12, weight: .bold))
            Text("·")
                .foregroundStyle(.white.opacity(0.45))
            Text(String(format: "Ghost %.1f", ghost))
                .font(AppFont.caption(12, weight: .bold))
                .monospacedDigit()
            Spacer(minLength: 0)
            Text(ahead ? "vedeš" : "dožeň PB")
                .font(AppFont.caption(11, weight: .heavy))
                .foregroundStyle(.black)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(ahead ? MatchColors.amber : Color.white.opacity(0.85), in: Capsule())
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(String(format: "Tvůj průměr %.1f, ghost %.1f", human, ghost))
    }

    /// Ceremonie i držení kola botovi úkol neseberou — počká a hodí, až je hřiště volné.
    private func waitUntilThrowIsClear() async -> Bool {
        let key = botTaskKey
        while isHoldingVisit || legCeremony != nil {
            if paused || showSettings || showLog || showProgress || showLeave || statsPlayer != nil { return false }
            do { try await Task.sleep(nanoseconds: 40_000_000) } catch { return false }
            if Task.isCancelled || key != botTaskKey { return false }
        }
        return true
    }
    @MainActor private func throwBotDart() async {
        guard scenePhase == .active, !paused, !showSettings, !showLog, !showProgress, !showLeave, statsPlayer == nil else { return }
        guard let game = activeMatch, !game.finished, game.legWinner == nil, !game.needsBullOff, !game.needsDecidingStarter, !showDecidingStarter else { return }
        let auto = game.currentPlayer.botLevel != nil || game.isGhostTurn
        guard auto else { return }
        guard await waitUntilThrowIsClear() else { return }
        guard scenePhase == .active, !paused, !showSettings, !showLog, !showProgress, !showLeave, statsPlayer == nil, !isHoldingVisit, legCeremony == nil, !showDecidingStarter else { return }
        guard let ready = activeMatch, !ready.finished, ready.legWinner == nil, !ready.needsBullOff, !ready.needsDecidingStarter else { return }
        guard ready.currentPlayer.botLevel != nil || ready.isGhostTurn else { return }
        if holdDarts.count != ready.currentDarts.count { holdDarts = ready.currentDarts }
        let key = botTaskKey
        let thrower = ready.active
        let pending = ready.currentDarts.count
        let visits = ready.visits.count
        let delay = ready.config.settings.botDelay
        do { try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000)) } catch { return }
        guard !Task.isCancelled, key == botTaskKey, !isHoldingVisit, legCeremony == nil, var current = activeMatch else { return }
        guard current.currentPlayer.botLevel != nil || current.isGhostTurn else { return }
        guard current.active == thrower, current.currentDarts.count == pending, current.visits.count == visits else { return }
        let dart: Dart
        if current.isGhostTurn {
            dart = GhostMode.nextDart(in: current)
        } else {
            var rng = SystemRandomNumberGenerator()
            dart = BotGameController.nextDart(in: current, using: &rng)
        }
        let oldCount = current.visits.count
        do {
            try current.recordDart(dart)
            let visitFinished = current.visits.count > oldCount
            let shownDarts = visitFinished ? (current.visits.last?.darts ?? []) : current.currentDarts
            if visitFinished {
                if let visit = current.visits.last, visit.bust {
                    store.feedback(spoken: "Přehoz")
                } else {
                    store.feedback(current.visits.last?.credited, checkout: current.visits.last?.checkout == true, matchWon: current.finished)
                }
                applyVisitHold(game: current, darts: shownDarts, player: thrower, fromBot: true)
            } else {
                holdDarts = shownDarts
                withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) { activeMatch = current }
            }
        } catch { self.error = error.localizedDescription }
    }
    private func totalInput(_ game: Match) -> some View {
        TotalScorePad(
            sumText: $sumText,
            showBust: true,
            onQuick: { score in
                store.tapHaptic(.medium)
                sumText = "\(score)"
                resolveTotal(game)
            },
            onBust: { bustPrompt = true },
            onTap: { store.tapHaptic(.light) }
        )
    }
    private func resolveTotal(_ game: Match) {
        if Int(sumText) == game.currentState.remaining { finishPrompt = true }
        else { submitTotal(darts:3) }
    }
    private func submitTotal(darts: Int) {
        guard !isHoldingVisit, legCeremony == nil, let score = Int(sumText), var game = activeMatch, game.currentPlayer.botLevel == nil else { return }
        let thrower = game.active
        do {
            try game.submitTotal(score, checkoutDarts: darts)
            if let visit = game.visits.last {
                sumText = ""
                if visit.bust {
                    store.feedback(announce: surface != .voice, spoken: "Přehoz")
                } else {
                    store.feedback(score, announce: surface != .voice, checkout: visit.checkout, matchWon: game.finished)
                }
                applyVisitHold(game: game, darts: visit.darts, player: thrower, fromBot: false)
                // Vždy součet jako jedno číslo — ne tři syntetické šipky.
                holdSurface = .total
            } else {
                activeMatch = game; sumText = ""; store.feedback(score, announce: surface != .voice)
            }
        } catch { self.error = error.localizedDescription }
    }
    private func bust(_ count: Int) {
        guard !isHoldingVisit, legCeremony == nil, var game = activeMatch, game.currentPlayer.botLevel == nil else { return }
        let thrower = game.active
        do {
            try game.recordBust(darts: count)
            if let visit = game.visits.last {
                sumText = ""
                store.feedback(announce: surface != .voice, spoken: "Přehoz")
                applyVisitHold(game: game, darts: visit.darts, player: thrower, fromBot: false)
            } else {
                activeMatch = game; sumText = ""; store.feedback(0, announce: surface != .voice)
            }
        } catch { self.error = error.localizedDescription }
    }
    private var matchOptions: Binding<MatchOptions> {
        Binding(get:{ activeMatch?.config.settings ?? MatchOptions() },set:{ options in
            guard var game = activeMatch else { return }
            game.config.options = options; activeMatch = game
            UIApplication.shared.isIdleTimerDisabled = options.keepAwake
        })
    }
    private struct BoardStats {
        var darts: [Dart]
        var positioned: [Dart]
        var triples: Int
        var doubles: Int
        var singles: Int
        var bulls: Int
        var misses: Int
        var topFields: [(label: String, count: Int, pct: Double)]

        var total: Int { positioned.count }
        var averageScore: Double {
            guard total > 0 else { return 0 }
            return Double(positioned.reduce(0) { $0 + $1.score }) / Double(total)
        }
        var averageRadius: Double {
            let radii = positioned.compactMap { dart -> Double? in
                guard let x = dart.x, let y = dart.y else { return nil }
                return hypot(x, y)
            }
            guard !radii.isEmpty else { return 0 }
            return radii.reduce(0, +) / Double(radii.count)
        }
        func pct(_ count: Int) -> Int {
            guard total > 0 else { return 0 }
            return Int((Double(count) / Double(total) * 100).rounded())
        }

        static func make(from game: Match, player: Int, leg: Int? = nil) -> BoardStats? {
            let darts = game.visits
                .filter { $0.player == player && $0.enteredAsTotal != true && (leg == nil || $0.leg == leg) }
                .flatMap(\.darts)
            guard !darts.isEmpty else { return nil }
            let positioned = darts.filter { $0.x != nil && $0.y != nil }
            guard !positioned.isEmpty else { return nil }
            var fieldHits: [String: Int] = [:]
            var triples = 0, doubles = 0, singles = 0, bulls = 0, misses = 0
            for dart in positioned {
                fieldHits[dart.label, default: 0] += 1
                if dart.segment == 0 { misses += 1; continue }
                if dart.segment == 25 {
                    bulls += 1
                    continue
                }
                switch dart.multiplier {
                case 3: triples += 1
                case 2: doubles += 1
                default: singles += 1
                }
            }
            let fields = fieldHits
                .sorted { lhs, rhs in lhs.value == rhs.value ? lhs.key < rhs.key : lhs.value > rhs.value }
                .prefix(8)
                .map { label, count -> (String, Int, Double) in
                    (label, count, Double(count) / Double(positioned.count) * 100)
                }
            return BoardStats(
                darts: darts,
                positioned: positioned,
                triples: triples,
                doubles: doubles,
                singles: singles,
                bulls: bulls,
                misses: misses,
                topFields: fields
            )
        }
    }

    private func result(_ game: Match) -> some View {
        let order = game.players.indices.filter(game.isClassicPlayer).sorted { a, b in
            if game.winner == a { return true }
            if game.winner == b { return false }
            if game.config.playsSets, game.states[a].sets != game.states[b].sets {
                return game.states[a].sets > game.states[b].sets
            }
            return game.states[a].legs > game.states[b].legs
        }
        let xp = store.matchXP(for: game)
        return ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                resultHeroBanner(game)
                    .modifier(ResultRise(shown: resultShown, delay: 0, reduceMotion: reduceMotion))
                if xp.hasAward, !link.isOnline {
                    resultXPBanner(xp)
                        .modifier(ResultRise(shown: resultShown, delay: 0.08, reduceMotion: reduceMotion))
                }
                if !order.isEmpty {
                    Text("Hráči")
                        .font(.title3.bold())
                        .foregroundStyle(.white)
                        .padding(.top, 8)
                        .modifier(ResultRise(shown: resultShown, delay: 0.14, reduceMotion: reduceMotion))
                    ForEach(Array(order.enumerated()), id: \.element) { offset, i in
                        resultPlayerReport(game, index: i)
                            .modifier(ResultRise(shown: resultShown, delay: 0.18 + Double(offset) * 0.06, reduceMotion: reduceMotion))
                    }
                }
                if link.isOnline {
                    Text("Výsledek najdeš v Moje hry.")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.6))
                        .frame(maxWidth: .infinity, minHeight: 44)
                } else {
                    Button("Opravit poslední šipku") { undo() }
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.6))
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 16)
            .frame(maxWidth: 780)
            .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.hidden)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            resultActions(game)
                .modifier(ResultRise(shown: resultShown, delay: 0.28, reduceMotion: reduceMotion))
        }
        .background(MatchColors.background.ignoresSafeArea())
        .onAppear {
            if legCeremony == nil { animateResultIn() }
        }
        .sheet(isPresented: $showMatchXP) {
            MatchXPBreakdownSheet(breakdown: xp)
        }
    }

    private func resultXPBanner(_ xp: MatchXPBreakdown) -> some View {
        let positive = xp.total > 0
        return Button { showMatchXP = true } label: {
            HStack(spacing: 14) {
                Image(systemName: positive ? "bolt.fill" : "bolt.slash.fill")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(MatchColors.ink)
                    .frame(width: 48, height: 48)
                    .background(MatchColors.ink.opacity(0.12), in: Circle())
                VStack(alignment: .leading, spacing: 2) {
                    Text(positive ? "+\(xp.total) XP" : "\(xp.total) XP")
                        .font(.system(.title2, design: .rounded).weight(.heavy))
                        .monospacedDigit()
                        .foregroundStyle(MatchColors.ink)
                    Text(xp.reasons.first ?? "Klepni pro rozpis XP")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(MatchColors.ink.opacity(0.62))
                        .multilineTextAlignment(.leading)
                        .lineLimit(3)
                }
                Spacer(minLength: 8)
                Image(systemName: "info.circle.fill")
                    .font(.title3)
                    .foregroundStyle(MatchColors.ink.opacity(0.55))
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                (positive ? Theme.brand : Color(red: 1, green: 0.45, blue: 0.35)),
                in: RoundedRectangle(cornerRadius: 22, style: .continuous)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(xp.total) XP")
        .accessibilityHint("Otevře rozklad pásem a výsledku")
    }

    private func resultHeroBanner(_ game: Match) -> some View {
        let winner = game.winner
        return VStack(spacing: 14) {
            ZStack {
                if let winner {
                    playerAvatar(game, index: winner, size: 84)
                        .overlay(Circle().strokeBorder(MatchColors.amber, lineWidth: 3))
                    Image(systemName: "trophy.fill")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(MatchColors.ink)
                        .padding(7)
                        .background(MatchColors.amber, in: Circle())
                        .offset(x: 30, y: 30)
                } else {
                    Circle()
                        .fill(MatchColors.amber.opacity(0.18))
                        .frame(width: 92, height: 92)
                    Circle()
                        .fill(LinearGradient(colors: [MatchColors.amber, MatchColors.coral], startPoint: .top, endPoint: .bottom))
                        .frame(width: 68, height: 68)
                    Image(systemName: "equal")
                        .font(.system(size: 30, weight: .semibold))
                        .foregroundStyle(MatchColors.ink)
                }
            }
            .accessibilityHidden(true)
            VStack(spacing: 4) {
                Text(winner == nil ? "Remíza" : "Vítěz zápasu")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(MatchColors.amber)
                Text(winner.map { game.players[$0].name } ?? "Vyrovnaná hra")
                    .font(.largeTitle.bold())
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
                Text("\(game.config.mode.title) · \(game.config.summary)")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.6))
                    .multilineTextAlignment(.center)
            }
            resultScoreline(game)
                .padding(.top, 6)
        }
        .padding(.vertical, 28)
        .padding(.horizontal, 20)
        .frame(maxWidth: .infinity)
        .background {
            ZStack {
                Color.white.opacity(0.05)
                RadialGradient(colors: [MatchColors.amber.opacity(0.28), .clear], center: .top, startRadius: 0, endRadius: 320)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous).strokeBorder(.white.opacity(0.08), lineWidth: 1))
        .accessibilityElement(children: .combine)
    }

    private func resultScoreline(_ game: Match) -> some View {
        let showsCompletion = game.players.indices.contains { completionCaption(game, player: $0) != nil }
        return HStack(alignment: .center, spacing: 0) {
            ForEach(game.players.indices, id: \.self) { i in
                if i > 0 {
                    Text(":")
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.3))
                        .padding(.horizontal, 6)
                }
                VStack(spacing: 4) {
                    let caption = completionCaption(game, player: i)
                    playerAvatar(game, index: i, size: 36)
                    let primary = game.config.playsSets ? game.states[i].sets : game.states[i].legs
                    Text("\(primary)")
                        .font(.system(size: 44, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(game.winner == i ? MatchColors.amber : .white)
                    Text(game.config.playsSets
                         ? czechWord(primary, one: "set", few: "sety", many: "setů")
                         : czechWord(primary, one: "leg", few: "legy", many: "legů"))
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.white.opacity(0.45))
                    if game.config.playsSets {
                        Text("\(czechCount(game.states[i].legs, one: "leg", few: "legy", many: "legů")) v setu")
                            .font(.caption.weight(.semibold))
                            .monospacedDigit()
                            .foregroundStyle(.white.opacity(0.72))
                    }
                    Text(game.players[i].name)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.6))
                        .lineLimit(1)
                    if showsCompletion {
                        Text(caption ?? " ")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(MatchColors.green)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                            .opacity(caption == nil ? 0 : 1)
                            .accessibilityHidden(caption == nil)
                    }
                }
                .frame(maxWidth: .infinity)
            }
        }
        .frame(maxWidth: 360)
    }

    private func resultPlayerReport(_ game: Match, index: Int, card: Bool = true) -> some View {
        let visits = game.visits.filter { $0.player == index }
        let dartCount = visits.reduce(0) { $0 + $1.darts.count }
        let checkouts = visits.filter(\.checkout)
        let n180 = visits.filter { $0.credited == 180 }.count
        let board = BoardStats.make(from: game, player: index)
        let isWinner = game.winner == index
        let name = game.players[index].name
        let stack = VStack(alignment: .leading, spacing: 16) {
            if card {
                HStack(spacing: 12) {
                    playerAvatar(game, index: index, size: 40)
                        .overlay(Circle().strokeBorder(isWinner ? MatchColors.amber : Color.white.opacity(0.16), lineWidth: 2))
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(name)
                                .font(.headline)
                                .foregroundStyle(.white)
                                .lineLimit(1)
                            if isWinner {
                                Image(systemName: "crown.fill")
                                    .font(.caption)
                                    .foregroundStyle(MatchColors.amber)
                                    .accessibilityLabel("Vítěz")
                            }
                        }
                        Text(resultRecordLine(game, index: index, darts: dartCount))
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.55))
                        if let caption = completionCaption(game, player: index) {
                            Text(caption)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(MatchColors.green)
                        }
                    }
                    Spacer(minLength: 8)
                    if game.config.mode == .x01 {
                        VStack(alignment: .trailing, spacing: 0) {
                            Text(String(format: "%.1f", game.average(for: index)))
                                .font(.system(.title, design: .rounded).weight(.bold))
                                .monospacedDigit()
                                .foregroundStyle(MatchColors.green)
                            Text("průměr")
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.5))
                        }
                    }
                }
            } else {
                Text("ZÁPAS")
                    .font(AppFont.caption(11, weight: .heavy))
                    .tracking(1.1)
                    .foregroundStyle(.white.opacity(0.45))
            }

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                if game.config.mode == .x01 {
                    let finish = CheckoutStats.make(from: game, player: index)
                    resultChip("\(game.best(for: index))", "Nejlepší kolo")
                    resultChip("\(checkouts.map(\.credited).max() ?? 0)", "Checkout")
                    resultChip(finish.percentage.map { "\(Int($0.rounded())) %" } ?? "—", "Na double")
                    resultChip("\(finish.hits)/\(finish.attempts)", "Zavření / pokusy")
                    resultChip("\(n180)", "180")
                    resultChip("\(visits.filter(\.bust).count)", "Přehozy")
                } else if game.config.mode == .cricket || game.config.mode == .countUp {
                    resultChip("\(game.states[index].points)", "Body")
                    resultChip("\(game.states[index].rounds)", "Kola")
                    resultChip("\(game.best(for: index))", "Nejlepší kolo")
                } else {
                    resultChip(game.states[index].clockTarget >= 21 ? "✓" : "\(game.states[index].clockTarget)", "Cíl")
                    resultChip("\(dartCount)", "Šipky")
                    resultChip("\(visits.count)", "Návštěvy")
                }
            }

            let numbered = numberedDarts(game, player: index)
            if !numbered.isEmpty {
                segmentHeatmapSection(numbered)
            }
            if let board {
                resultBoardSection(board, player: index)
            }
        }
        return Group {
            if card {
                stack
                    .padding(16)
                    .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .strokeBorder(isWinner ? MatchColors.amber.opacity(0.4) : Color.white.opacity(0.06), lineWidth: 1)
                    )
            } else {
                stack
            }
        }
    }

    private func completionCaption(_ game: Match, player: Int) -> String? {
        guard game.players.indices.contains(player) else { return nil }
        let person = game.players[player]
        guard person.botLevel == nil, !game.isGhost(player) else { return nil }
        return store.completionCaption(for: person.id)
    }

    private func resultRecordLine(_ game: Match, index: Int, darts: Int) -> String {
        let dartsLabel = czechCount(darts, one: "šipka", few: "šipky", many: "šipek")
        if game.config.playsSets {
            let sets = czechCount(game.states[index].sets, one: "set", few: "sety", many: "setů")
            let legs = czechCount(game.states[index].legs, one: "leg", few: "legy", many: "legů")
            return "\(sets) · \(legs) v setu · \(dartsLabel)"
        }
        let legs = czechCount(game.states[index].legs, one: "leg", few: "legy", many: "legů")
        return "\(legs) · \(dartsLabel)"
    }

    private func czechWord(_ value: Int, one: String, few: String, many: String) -> String {
        value == 1 ? one : (2...4).contains(value) ? few : many
    }

    private func czechCount(_ value: Int, one: String, few: String, many: String) -> String {
        "\(value) \(czechWord(value, one: one, few: few, many: many))"
    }

    /// Šipky zadané po číslech nemají souřadnice. Heatmapa počítá pole, ne místo na terči.
    private func numberedDarts(_ game: Match, player: Int) -> [Dart] {
        var darts = game.visits
            .filter { $0.player == player && $0.enteredAsTotal != true }
            .flatMap(\.darts)
        if game.active == player, let pending = game.pendingDarts, game.legWinner == nil, !game.finished {
            darts.append(contentsOf: pending)
        }
        return darts.filter { $0.x == nil || $0.y == nil }
    }

    private func segmentHeatmapSection(_ darts: [Dart]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "chart.pie.fill")
                    .font(.system(size: 14, weight: .bold))
                VStack(alignment: .leading, spacing: 2) {
                    Text("MAPA SEGMENTŮ")
                        .font(AppFont.caption(11, weight: .heavy))
                        .tracking(1.2)
                    Text("\(czechCount(darts.count, one: "šipka", few: "šipky", many: "šipek")) podle zadaného pole")
                        .font(AppFont.caption(11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.5))
                }
                Spacer(minLength: 0)
            }
            .foregroundStyle(MatchColors.green)
            SegmentRoseChart(darts: darts, title: "Kam šipky padaly")
        }
        .accessibilityElement(children: .contain)
    }

    private func resultBoardSection(_ board: BoardStats, player: Int) -> some View {
        Button {
            boardDetail = BoardDetailSelection(player: player)
        } label: {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 8) {
                    Image(systemName: "scope")
                        .font(.system(size: 14, weight: .bold))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("DETAIL TERČE")
                            .font(AppFont.caption(11, weight: .heavy))
                            .tracking(1.2)
                        Text("\(board.total) přesně umístěných šipek")
                            .font(AppFont.caption(11, weight: .medium))
                            .foregroundStyle(.white.opacity(0.5))
                    }
                    Spacer()
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .font(.system(size: 13, weight: .bold))
                }
                .foregroundStyle(MatchColors.green)

                TouchDartboard(
                    marks: board.positioned,
                    interactive: false,
                    showMarkNumbers: false
                ) { _ in }
                    .allowsHitTesting(false)
                    .frame(maxWidth: 250)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 2)

                HStack(spacing: 6) {
                    ringPct("T", board.pct(board.triples), MatchColors.coral)
                    ringPct("D", board.pct(board.doubles), MatchColors.amber)
                    ringPct("S", board.pct(board.singles), MatchColors.green)
                    ringPct("B", board.pct(board.bulls), Color.white)
                    ringPct("M", board.pct(board.misses), Color.white.opacity(0.45))
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(14)
        .background(Color.black.opacity(0.28), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityLabel("Otevřít detailní statistiku terče")
    }

    private func boardDetailScreen(_ game: Match, player: Int) -> some View {
        let name = game.players.indices.contains(player) ? game.players[player].name : "Hráč"
        let legs = Array(Set(game.visits.filter { $0.player == player }.map(\.leg))).sorted()
        let pages: [Int] = [0] + (legs.count > 1 ? legs : [])
        return ZStack {
            LinearGradient(
                colors: [Color(red: 0.02, green: 0.22, blue: 0.18), MatchColors.background, Color.black],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 14) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Detail terče")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(MatchColors.green)
                        Text(name)
                            .font(.largeTitle.bold())
                            .foregroundStyle(.white)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                    Spacer()
                    Button {
                        boardDetail = nil
                    } label: {
                        Image(systemName: "xmark")
                            .font(.body.weight(.semibold))
                            .frame(width: 30, height: 30)
                    }
                    .buttonStyle(.glass)
                    .buttonBorderShape(.circle)
                    .controlSize(.large)
                    .accessibilityLabel("Zavřít detail terče")
                }
                .padding(.horizontal, 18)
                .padding(.top, 18)
                .frame(maxWidth: 700)

                if pages.count > 1 {
                    legPicker(game, player: player, pages: pages)
                }

                ScrollView(.horizontal) {
                    LazyHStack(spacing: 0) {
                        ForEach(pages, id: \.self) { leg in
                            boardDetailPage(game, player: player, leg: leg)
                                .containerRelativeFrame(.horizontal)
                                .id(leg)
                        }
                    }
                    .scrollTargetLayout()
                }
                .scrollTargetBehavior(.paging)
                .scrollPosition(id: $detailLeg)
                .scrollIndicators(.hidden)
                .scrollDisabled(boardZoomed)
            }
        }
        .preferredColorScheme(.dark)
        .statusBarHidden(true)
        .onAppear { detailLeg = 0 }
        .onDisappear { boardZoomed = false }
    }

    private func legWinner(_ game: Match, leg: Int) -> Int? {
        game.bullOffLegs?[leg] ?? game.visits.last { $0.leg == leg && $0.checkout }?.player
    }

    private func legPicker(_ game: Match, player: Int, pages: [Int]) -> some View {
        let selection = Binding<Int>(
            get: { detailLeg ?? 0 },
            set: { leg in withAnimation(.easeInOut(duration: 0.3)) { detailLeg = leg } }
        )
        let compact = pages.count > 4
        return Group {
            if pages.count <= 8 {
                Picker("Leg", selection: selection) {
                    ForEach(pages, id: \.self) { leg in
                        Text(leg == 0 ? "Vše" : compact ? "\(leg)" : "Leg \(leg)")
                            .accessibilityLabel(leg == 0 ? "Všechny legy" : "Leg \(leg)\(legWinner(game, leg: leg) == player ? ", vyhraný" : "")")
                            .tag(leg)
                    }
                }
                .pickerStyle(.segmented)
            } else {
                Picker("Leg", selection: selection) {
                    ForEach(pages, id: \.self) { leg in
                        Text(leg == 0 ? "Všechny legy" : "Leg \(leg)").tag(leg)
                    }
                }
                .pickerStyle(.menu)
                .buttonStyle(.glass)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, 18)
        .frame(maxWidth: 700)
        .sensoryFeedback(.selection, trigger: detailLeg)
    }

    private func boardDetailPage(_ game: Match, player: Int, leg: Int) -> some View {
        let board = BoardStats.make(from: game, player: player, leg: leg == 0 ? nil : leg)
        let visits = game.visits.filter { $0.player == player && (leg == 0 || $0.leg == leg) }
        let darts = visits.reduce(0) { $0 + $1.darts.count }
        let credited = visits.reduce(0) { $0 + $1.credited }
        let isX01 = game.config.mode == .x01
        let checkout = CheckoutStats.make(from: game, player: player, leg: leg == 0 ? nil : leg)
        let summaryValue: String = {
            if leg == 0 { return "\(game.states[player].legs)" }
            guard let winner = legWinner(game, leg: leg) else { return "—" }
            return winner == player ? "Vyhrál" : "Prohrál"
        }()
        return ScrollView {
            VStack(spacing: 18) {
                HStack(spacing: 8) {
                    boardMetric("\(darts)", "Šipky", "arrow.up.right")
                    boardMetric(
                        isX01 ? (darts == 0 ? "—" : String(format: "%.1f", Double(credited) * 3 / Double(darts))) : "\(credited)",
                        isX01 ? "Průměr / 3" : "Body",
                        "chart.line.uptrend.xyaxis"
                    )
                    boardMetric(summaryValue, leg == 0 ? "Vyhrané legy" : "Výsledek legu", leg == 0 ? "flag.checkered" : "trophy")
                }

                if checkout.hasData {
                    VStack(alignment: .leading, spacing: 14) {
                        detailSectionTitle("ZAVÍRÁNÍ", icon: "checkmark.seal.fill")
                        CheckoutStatsView(stats: checkout, tint: MatchColors.green)
                    }
                    .detailCard()
                }

                if let board {
                    SegmentRoseChart(darts: board.positioned, title: "Kam šipky padaly")

                    ZoomableDartboard(marks: board.positioned, zoomed: $boardZoomed)
                        .frame(maxWidth: 540)
                        .frame(maxWidth: .infinity)
                        .padding(8)
                        .background(Color.black.opacity(0.28), in: RoundedRectangle(cornerRadius: 28, style: .continuous))
                    Text("Přesná místa · \(board.total) šipek zadaných přes terč. Roztáhni prsty pro detail.")
                        .font(.footnote)
                        .foregroundStyle(.white.opacity(0.55))

                    HStack(spacing: 8) {
                        boardMetric("\(board.pct(board.total - board.misses)) %", "V terči", "scope")
                        boardMetric(String(format: "%.1f", board.averageScore), "Body / šipka", "number")
                        boardMetric("\(Int((board.averageRadius * 100).rounded())) %", "Od středu", "dot.scope")
                    }

                    VStack(alignment: .leading, spacing: 14) {
                        detailSectionTitle("TYP ZÁSAHU", icon: "chart.bar.fill")
                        HStack(spacing: 7) {
                            ringPct("TRIPLE", board.pct(board.triples), MatchColors.coral)
                            ringPct("DOUBLE", board.pct(board.doubles), MatchColors.amber)
                            ringPct("SINGLE", board.pct(board.singles), MatchColors.green)
                        }
                        HStack(spacing: 7) {
                            ringPct("BULL", board.pct(board.bulls), .white)
                            ringPct("VEDLE", board.pct(board.misses), .white.opacity(0.5))
                        }
                    }
                    .detailCard()

                    if !board.topFields.isEmpty {
                        VStack(alignment: .leading, spacing: 14) {
                            detailSectionTitle("NEJČASTĚJŠÍ POLE", icon: "square.grid.3x3.fill")
                            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 9) {
                                ForEach(Array(board.topFields.enumerated()), id: \.offset) { _, field in
                                    HStack {
                                        Text(field.label)
                                            .font(AppFont.title(18, weight: .heavy))
                                            .foregroundStyle(.white)
                                        Spacer()
                                        VStack(alignment: .trailing, spacing: 2) {
                                            Text("\(field.count)×")
                                                .font(AppFont.body(14, weight: .bold))
                                                .foregroundStyle(MatchColors.green)
                                            Text("\(Int(field.pct.rounded())) %")
                                                .font(AppFont.caption(10, weight: .semibold))
                                                .foregroundStyle(.white.opacity(0.45))
                                        }
                                    }
                                    .padding(12)
                                    .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 13))
                                }
                            }
                        }
                        .detailCard()
                    }

                } else {
                    ContentUnavailableView(
                        "Bez zásahů na terči",
                        systemImage: "scope",
                        description: Text(leg == 0
                            ? "Šipky byly zapsané jako součet, takže nemají přesné místo."
                            : "V legu \(leg) nejsou šipky zadané přes terč.")
                    )
                    .padding(.top, 40)
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 4)
            .padding(.bottom, 34)
            .frame(maxWidth: 700)
            .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.hidden)
        .scrollDisabled(boardZoomed)
    }

    private func boardMetric(_ value: String, _ label: String, _ icon: String) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(MatchColors.green)
            Text(value)
                .font(AppFont.display(22, weight: .heavy))
                .monospacedDigit()
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.65)
            Text(label)
                .font(AppFont.caption(10, weight: .semibold))
                .foregroundStyle(.white.opacity(0.45))
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 15))
    }

    private func detailSectionTitle(_ title: String, icon: String) -> some View {
        Label(title, systemImage: icon)
            .font(AppFont.caption(11, weight: .heavy))
            .tracking(1.2)
            .foregroundStyle(MatchColors.green)
    }

    private func ringPct(_ title: String, _ pct: Int, _ color: Color) -> some View {
        VStack(spacing: 4) {
            Text("\(pct)%")
                .font(AppFont.body(15, weight: .heavy))
                .monospacedDigit()
                .foregroundStyle(.white)
            Text(title)
                .font(AppFont.caption(11, weight: .bold))
                .foregroundStyle(color)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func resultChip(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.system(.title3, design: .rounded).weight(.bold))
                .monospacedDigit()
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.55))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func resultActions(_ game: Match) -> some View {
        if link.isOnline {
            Button(action: onOnlineExit) {
                Label("Zpět do lobby", systemImage: "person.2.fill")
                    .font(.headline)
                    .labelStyle(.titleAndIcon)
                    .foregroundStyle(Color.black)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .glassEffect(.regular.tint(MatchColors.finish).interactive(), in: Capsule())
            .padding(.horizontal, 16)
            .padding(.top, 10)
            .padding(.bottom, 6)
            .frame(maxWidth: 780)
            .frame(maxWidth: .infinity)
        } else {
            localResultActions(game)
        }
    }

    private func localResultActions(_ game: Match) -> some View {
        HStack(spacing: 12) {
            Button {
                store.finish()
                activeMatch = Match(config: game.config, players: game.players, firstPlayer: (game.starter + 1) % game.players.count)
                multiplier = 1; sumText = ""; paused = false; holdDarts = []; isHoldingVisit = false; holdPlayer = nil; legCeremony = nil; oneEightyFlash = nil; ceremonyLeaving = false; ceremonyDismissing = false; resultShown = false; revision = UUID()
            } label: {
                Label("Odveta", systemImage: "arrow.clockwise")
                    .font(.headline)
                    .labelStyle(.titleAndIcon)
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .glassEffect(.regular.interactive(), in: Capsule())

            Button { leaveToHome() } label: {
                Label("Domů", systemImage: "house.fill")
                    .font(.headline)
                    .labelStyle(.titleAndIcon)
                    .foregroundStyle(Color.black)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .glassEffect(.regular.tint(MatchColors.finish).interactive(), in: Capsule())
            .accessibilityHint("Uloží výsledek a vrátí na Domů")
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 6)
        .frame(maxWidth: 780)
        .frame(maxWidth: .infinity)
    }
}

/// Krátká obrazovka po uložení — liquid glass karta, pak návrat domů.
private struct MatchSavedSplash: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = false
    @State private var drift = false
    @State private var progress: CGFloat = 0

    /// Délka obrazovky. `saveAndLeave` na ni čeká, ať ukazatel doběhne před odchodem.
    static func hold(reduceMotion: Bool) -> TimeInterval {
        reduceMotion ? 0.7 : 1.45
    }

    var body: some View {
        ZStack {
            backdrop
            card
                .scaleEffect(shown || reduceMotion ? 1 : 0.92)
                .opacity(shown ? 1 : 0)
                .offset(y: shown || reduceMotion ? 0 : 16)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Hra uložena. Vracím tě na Domů.")
        .onAppear(perform: play)
    }

    private var backdrop: some View {
        ZStack {
            MatchColors.background
            MeshGradient(
                width: 3,
                height: 3,
                points: meshPoints,
                colors: [
                    Color(red: 0.03, green: 0.09, blue: 0.07),
                    Color(red: 0.05, green: 0.32, blue: 0.20),
                    Color(red: 0.02, green: 0.08, blue: 0.07),
                    Color(red: 0.02, green: 0.14, blue: 0.16),
                    Color(red: 0.06, green: 0.20, blue: 0.13),
                    Theme.brand.opacity(0.55),
                    Color(red: 0.02, green: 0.06, blue: 0.05),
                    MatchColors.green.opacity(0.45),
                    Color(red: 0.03, green: 0.10, blue: 0.08)
                ]
            )
            Circle()
                .fill(MatchColors.green.opacity(0.55))
                .frame(width: 260, height: 260)
                .blur(radius: 72)
                .offset(x: drift ? -70 : 24, y: drift ? -210 : -150)
            Circle()
                .fill(Theme.brand.opacity(0.42))
                .frame(width: 200, height: 200)
                .blur(radius: 64)
                .offset(x: drift ? 110 : 48, y: drift ? 200 : 130)
            Circle()
                .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
                .frame(width: 280, height: 280)
            Circle()
                .strokeBorder(Color.white.opacity(0.05), lineWidth: 1)
                .frame(width: 420, height: 420)
        }
        .ignoresSafeArea()
    }

    private var meshPoints: [SIMD2<Float>] {
        let shift: Float = drift ? 0.08 : -0.04
        return [
            SIMD2(0, 0), SIMD2(0.5, 0), SIMD2(1, 0),
            SIMD2(0, 0.5), SIMD2(0.5 + shift, 0.46 - shift), SIMD2(1, 0.5),
            SIMD2(0, 1), SIMD2(0.5, 1), SIMD2(1, 1)
        ]
    }

    private var card: some View {
        GlassEffectContainer(spacing: 22) {
            VStack(spacing: -34) {
                badge
                    .zIndex(1)

                VStack(spacing: 16) {
                    VStack(spacing: 6) {
                        Text("Hra uložena")
                            .font(AppFont.title(28, weight: .bold))
                            .foregroundStyle(.white)
                        Label("Vracím tě na Domů", systemImage: "house.fill")
                            .font(AppFont.body(16, weight: .medium))
                            .foregroundStyle(.white.opacity(0.78))
                            .labelStyle(.titleAndIcon)
                    }

                    Capsule()
                        .fill(Color.white.opacity(0.14))
                        .overlay(alignment: .leading) {
                            GeometryReader { geo in
                                Capsule()
                                    .fill(
                                        LinearGradient(
                                            colors: [MatchColors.green, Color(red: 0.62, green: 0.96, blue: 0.68)],
                                            startPoint: .leading,
                                            endPoint: .trailing
                                        )
                                    )
                                    .frame(width: max(10, geo.size.width * progress))
                                    .shadow(color: MatchColors.green.opacity(0.7), radius: 6)
                            }
                        }
                        .frame(height: 5)
                        .accessibilityHidden(true)
                }
                .padding(.top, 52)
                .padding(.horizontal, 28)
                .padding(.bottom, 22)
                .frame(maxWidth: 320)
                .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 34, style: .continuous))
            }
        }
        .padding(.horizontal, 28)
    }

    private var badge: some View {
        let mark = Image(systemName: "checkmark")
            .font(.system(size: 32, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: 92, height: 92)
            .glassEffect(.regular.tint(MatchColors.green), in: Circle())
        return Group {
            if reduceMotion {
                mark
            } else {
                mark.symbolEffect(.bounce, options: .speed(0.55), value: shown)
            }
        }
    }

    private func play() {
        let motion = reduceMotion
        withAnimation(motion ? nil : .spring(duration: 0.48, bounce: 0.28)) {
            shown = true
        }
        withAnimation(motion ? nil : .easeInOut(duration: 2.6).repeatForever(autoreverses: true)) {
            drift = true
        }
        let fill = max(0.35, Self.hold(reduceMotion: motion) - 0.22)
        withAnimation(motion ? .linear(duration: fill) : .easeInOut(duration: fill)) {
            progress = 1
        }
    }
}

private struct ResultDetailCard: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(16)
            .background(
                Color.white.opacity(0.065),
                in: RoundedRectangle(cornerRadius: 20, style: .continuous)
            )
    }
}

private extension View {
    func detailCard() -> some View {
        modifier(ResultDetailCard())
    }
}

/// Oblá karta s lehkým výřezem ve tvaru šipky na spodní hraně, ve sloupci hráče na tahu.
private struct ScoreboardBottomCutout: Shape {
    /// Relativní střed výřezu na šířku karty (0…1).
    var centerX: CGFloat
    var corner: CGFloat = 22
    var cutWidth: CGFloat = 18
    var cutDepth: CGFloat = 10

    var animatableData: CGFloat {
        get { centerX }
        set { centerX = newValue }
    }

    static func centerX(activeIndex: Int, columns: Int) -> CGFloat {
        let cols = max(1, columns)
        let col = activeIndex % cols
        return (CGFloat(col) + 0.5) / CGFloat(cols)
    }

    func path(in rect: CGRect) -> Path {
        let cx = rect.minX + rect.width * min(max(centerX, 0), 1)
        let half = min(cutWidth, rect.width * 0.2) / 2
        let depth = min(cutDepth, 12)
        let left = max(rect.minX + corner + 4, cx - half)
        let right = min(rect.maxX - corner - 4, cx + half)

        var path = Path()
        path.move(to: CGPoint(x: rect.minX + corner, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - corner, y: rect.minY))
        path.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY + corner), control: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - corner))
        path.addQuadCurve(to: CGPoint(x: rect.maxX - corner, y: rect.maxY), control: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: right, y: rect.maxY))
        path.addLine(to: CGPoint(x: cx, y: rect.maxY - depth))
        path.addLine(to: CGPoint(x: left, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX + corner, y: rect.maxY))
        path.addQuadCurve(to: CGPoint(x: rect.minX, y: rect.maxY - corner), control: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + corner))
        path.addQuadCurve(to: CGPoint(x: rect.minX + corner, y: rect.minY), control: CGPoint(x: rect.minX, y: rect.minY))
        path.closeSubpath()
        return path
    }
}

private struct ResultRise: ViewModifier {
    var shown: Bool
    var delay: Double
    var reduceMotion: Bool

    func body(content: Content) -> some View {
        content
            .opacity(shown || reduceMotion ? 1 : 0)
            .offset(y: shown || reduceMotion ? 0 : 36)
            .animation(reduceMotion ? nil : .spring(response: 0.72, dampingFraction: 0.84).delay(delay), value: shown)
    }
}

private enum CeremonyFade {
    static let seconds: TimeInterval = 0.42
}


private struct LegCeremonyView: View {
    let ceremony: LegCeremony
    let reduceMotion: Bool
    let leaving: Bool
    let onContinue: () -> Void

    @State private var appeared = false

    private var shown: Bool { appeared || reduceMotion }

    private var winnerName: String {
        ceremony.names.indices.contains(ceremony.winner) ? ceremony.names[ceremony.winner] : "Hráč"
    }
    private var accent: Color {
        ceremony.matchFinished ? MatchColors.amber : ceremony.isCheckout ? MatchColors.green : MatchColors.coral
    }
    private var badge: (title: String, icon: String) {
        if ceremony.matchFinished { return ("Konec zápasu", "trophy.fill") }
        if ceremony.setClosed { return ("Set hotový", "square.stack.3d.up.fill") }
        if ceremony.byBullOff { return ("Leg \(ceremony.leg) · rozhoz na střed", "scope") }
        if ceremony.isCheckout { return ("Leg \(ceremony.leg) · zavřeno", "checkmark.seal.fill") }
        return ("Leg \(ceremony.leg)", "flag.checkered")
    }
    private var showsCheckout: Bool { ceremony.isCheckout && ceremony.checkoutScore > 0 }
    private var userAverageText: String? {
        ceremony.userLegAverage.map { String(format: "%.1f", $0) }
    }
    private var averageSpoken: String {
        guard let userAverageText else { return "" }
        return " Tvůj průměr za leg \(userAverageText)."
    }
    private var outcomeLine: String {
        if ceremony.matchFinished { return "vyhrává zápas" }
        if ceremony.setClosed { return "vyhrává set" }
        return "vyhrává leg \(ceremony.leg)"
    }
    /// Set se právě zavřel — i když tím zároveň skončil zápas.
    private var setJustWon: Bool {
        guard ceremony.playsSets, ceremony.legs.indices.contains(ceremony.winner) else { return false }
        return ceremony.legs[ceremony.winner] >= ceremony.legsToWin
    }
    /// Tečky odpovídají tomu, co je nastavené. Best of 5 má pět teček, ne tři.
    private var legSlots: Int {
        max(ceremony.legSlots, ceremony.legsToWin, ceremony.legs.max() ?? 0)
    }
    private var setSlots: Int {
        max(ceremony.setSlots, ceremony.setsToWin, ceremony.sets.max() ?? 0)
    }
    private var scoreSpoken: String {
        guard ceremony.playsSets else { return "" }
        let sets = ceremony.sets.map(String.init).joined(separator: " ku ")
        let legs = ceremony.legs.map(String.init).joined(separator: " ku ")
        return " Sety \(sets). Legy v setu \(legs)."
    }

    var body: some View {
        ZStack {
            background
            VStack(spacing: 0) {
                Spacer(minLength: 20)
                VStack(spacing: 10) {
                    Label(badge.title, systemImage: badge.icon)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(accent)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(accent.opacity(0.16), in: Capsule())
                    if let userAverageText {
                        Text("Tvůj průměr za leg \(userAverageText)")
                            .font(.subheadline.weight(.bold))
                            .monospacedDigit()
                            .foregroundStyle(.white)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(.white.opacity(0.1), in: Capsule())
                    }
                }

                winnerMark
                    .padding(.top, 28)

                VStack(spacing: 2) {
                    Text(winnerName)
                        .font(.largeTitle.bold())
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .minimumScaleFactor(0.7)
                    Text(outcomeLine)
                        .font(ceremony.matchFinished ? .title2.weight(.semibold) : .title3)
                        .foregroundStyle(.white.opacity(0.65))
                }
                .padding(.top, 18)

                if showsCheckout {
                    checkoutCard
                        .padding(.top, 28)
                }

                scoreboard
                    .padding(.top, showsCheckout ? 14 : 32)

                Spacer(minLength: 20)
                continueButton
                    .padding(.bottom, 56)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 24)
            .padding(.top, 12)
            .padding(.bottom, 12)
            .frame(maxWidth: 520)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .opacity(leaving ? 0 : 1)
        .animation(reduceMotion ? nil : .easeInOut(duration: CeremonyFade.seconds), value: leaving)
        .statusBarHidden(true)
        .persistentSystemOverlays(.hidden)
        .preferredColorScheme(.dark)
        .contentShape(Rectangle())
        .onTapGesture(perform: onContinue)
        .onAppear {
            guard !appeared else { return }
            if reduceMotion {
                appeared = true
                return
            }
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: UInt64(CeremonyFade.seconds * 1_000_000_000))
                appeared = true
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            ceremony.matchFinished
            ? "\(winnerName) vyhrává zápas.\(scoreSpoken)\(averageSpoken)"
            : ceremony.setClosed
            ? "\(winnerName) vyhrává set.\(scoreSpoken)\(averageSpoken)"
            : showsCheckout
            ? "\(winnerName) zavřel na \(ceremony.checkoutScore) a vyhrává leg \(ceremony.leg).\(scoreSpoken)\(averageSpoken)"
            : "\(winnerName) vyhrává leg \(ceremony.leg).\(scoreSpoken)\(averageSpoken)"
        )
        .accessibilityHint(
            ceremony.matchFinished
            ? "Otevře statistiky zápasu"
            : ceremony.setClosed ? "Pokračuj na další set" : "Pokračuj na další leg"
        )
        .accessibilityAddTraits(.isButton)
    }

    private var background: some View {
        ZStack {
            MatchColors.background
            RadialGradient(
                colors: [accent.opacity(ceremony.matchFinished ? 0.5 : 0.38), .clear],
                center: .top,
                startRadius: 0,
                endRadius: ceremony.matchFinished ? 640 : 520
            )
            RadialGradient(colors: [accent.opacity(0.14), .clear], center: .bottom, startRadius: 0, endRadius: 420)
        }
        .ignoresSafeArea()
    }

    private var winnerMark: some View {
        ZStack {
            Circle()
                .stroke(accent.opacity(0.4), lineWidth: 2)
                .frame(width: 112, height: 112)
                .scaleEffect(appeared ? 1.65 : 0.85)
                .opacity(appeared ? 0 : 0.7)
                .animation(reduceMotion ? nil : .easeOut(duration: 1.05), value: appeared)
            Circle()
                .fill(accent.opacity(0.14))
                .frame(width: 128, height: 128)
            Circle()
                .strokeBorder(accent.opacity(0.35), lineWidth: 1)
                .frame(width: 128, height: 128)
            Avatar(
                name: winnerName,
                bot: ceremony.winnerAsset != nil,
                size: 92,
                photo: ceremony.winnerPhoto,
                asset: ceremony.winnerAsset
            )
            if ceremony.matchFinished {
                Image(systemName: "trophy.fill")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(MatchColors.ink)
                    .padding(8)
                    .background(accent, in: Circle())
                    .offset(x: 34, y: 34)
            }
        }
        .accessibilityHidden(true)
    }

    private var checkoutCard: some View {
        VStack(spacing: 8) {
            Text("Checkout")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.white.opacity(0.6))
            Text("\(ceremony.checkoutScore)")
                .font(.system(size: 64, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(accent)
            if !ceremony.checkoutDarts.isEmpty {
                HStack(spacing: 8) {
                    ForEach(Array(ceremony.checkoutDarts.enumerated()), id: \.offset) { _, label in
                        Text(label)
                            .font(.subheadline.weight(.semibold))
                            .monospacedDigit()
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(.white.opacity(0.12), in: Capsule())
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 18)
        .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private var scoreboard: some View {
        VStack(spacing: 0) {
            if ceremony.playsSets {
                HStack(spacing: 8) {
                    Spacer(minLength: 0)
                    Text("Sety")
                        .frame(width: columnWidth(setSlots))
                    Text("Legy")
                        .frame(width: columnWidth(legSlots))
                }
                .font(.caption2.weight(.bold))
                .foregroundStyle(.white.opacity(0.45))
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 2)
            }
            ForEach(ceremony.names.indices, id: \.self) { i in
                if i > 0 { Divider().overlay(.white.opacity(0.08)).padding(.leading, 16) }
                scoreRow(i)
            }
        }
        .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private func scoreRow(_ index: Int) -> some View {
        let legs = ceremony.legs.indices.contains(index) ? ceremony.legs[index] : 0
        let sets = ceremony.sets.indices.contains(index) ? ceremony.sets[index] : 0
        let isWinner = index == ceremony.winner
        let tint = isWinner ? accent : Color.white
        let pip = isWinner ? accent : Color.white.opacity(0.7)
        return HStack(spacing: 8) {
            Text(ceremony.names[index])
                .font(isWinner ? .body.weight(.semibold) : .body)
                .foregroundStyle(isWinner ? .white : .white.opacity(0.7))
                .lineLimit(1)
            Spacer(minLength: 8)
            if ceremony.playsSets {
                scoreCell(value: sets, total: setSlots, tint: tint, filled: pip, pulse: isWinner && setJustWon, delay: 0.46)
                scoreCell(value: legs, total: legSlots, tint: tint, filled: pip, pulse: isWinner, delay: 0.24)
            } else {
                scoreCell(value: legs, total: legSlots, tint: tint, filled: pip, pulse: isWinner, delay: 0.28)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, ceremony.playsSets ? 10 : 12)
    }

    private func columnWidth(_ total: Int) -> CGFloat {
        guard total <= 7 else { return 44 }
        let pips = CGFloat(total) * 8 + CGFloat(max(0, total - 1)) * 4
        return max(52, pips + 26)
    }

    private func scoreCell(value: Int, total: Int, tint: Color, filled: Color, pulse: Bool, delay: Double) -> some View {
        HStack(spacing: 6) {
            if total <= 7 {
                HStack(spacing: 4) {
                    ForEach(0..<total, id: \.self) { n in
                        let on = n < value
                        let newest = pulse && value > 0 && n == value - 1
                        Circle()
                            .fill(on ? filled : Color.white.opacity(0.15))
                            .frame(width: newest && shown ? 10 : 8, height: newest && shown ? 10 : 8)
                            .scaleEffect(newest && !shown ? 0.3 : 1)
                            .animation(reduceMotion ? nil : .spring(response: 0.55, dampingFraction: 0.68).delay(newest ? delay : 0), value: appeared)
                    }
                }
                .accessibilityHidden(true)
            }
            Text("\(value)")
                .font(.system(ceremony.playsSets ? .title3 : .title2, design: .rounded).weight(.bold))
                .monospacedDigit()
                .foregroundStyle(tint)
                .frame(minWidth: ceremony.playsSets ? 16 : 28, alignment: .trailing)
        }
        .frame(width: ceremony.playsSets ? columnWidth(total) : nil, alignment: .center)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(value) z \(total)")
    }

    private var continueButton: some View {
        Button(action: onContinue) {
            Label(continueTitle, systemImage: ceremony.matchFinished ? "chart.bar.fill" : "arrow.right")
                .font(.headline)
                .labelStyle(.titleAndIcon)
                .foregroundStyle(Color.black)
                .frame(maxWidth: .infinity, minHeight: 54)
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.tint(MatchColors.green).interactive(), in: Capsule())
    }

    private var continueTitle: String {
        if ceremony.matchFinished { return "Statistiky" }
        return "Pokračovat"
    }
}

/// Terč v detailu statistik s přiblížením. Kreslí se ve skutečné velikosti, takže zůstává ostrý i zblízka.
struct ZoomableDartboard: View {
    let marks: [Dart]
    @Binding var zoomed: Bool

    @State private var scale: CGFloat = 1
    @State private var baseScale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var baseOffset: CGSize = .zero

    private let maxScale: CGFloat = 10

    var body: some View {
        GeometryReader { geo in
            let side = geo.size.width
            TouchDartboard(marks: marks, interactive: false, showMarkNumbers: scale > 2.5) { _ in }
                .frame(width: side * scale, height: side * scale)
                .offset(offset)
                .frame(width: side, height: side)
                .clipped()
                .contentShape(Rectangle())
                .gesture(magnify(side: side))
                .simultaneousGesture(scale > 1.01 ? pan(side: side) : nil)
                .simultaneousGesture(doubleTap(side: side))
        }
        .aspectRatio(1, contentMode: .fit)
        .overlay(alignment: .bottomTrailing) { controls.padding(10) }
        .overlay(alignment: .bottomLeading) {
            if scale > 1.01 {
                Text("\(String(format: "%.1f", scale))×")
                    .font(.caption.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(.black.opacity(0.55), in: Capsule())
                    .padding(10)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Terč se zásahy")
        .accessibilityHint("Roztáhni dvěma prsty nebo dvakrát klepni pro přiblížení.")
    }

    private var controls: some View {
        HStack(spacing: 0) {
            Button { zoom(to: scale / 1.6) } label: { Image(systemName: "minus") .frame(width: 40, height: 40) }
                .disabled(scale <= 1.01)
                .accessibilityLabel("Oddálit")
            Divider().frame(height: 22).overlay(.white.opacity(0.2))
            Button { zoom(to: scale * 1.6) } label: { Image(systemName: "plus").frame(width: 40, height: 40) }
                .disabled(scale >= maxScale - 0.01)
                .accessibilityLabel("Přiblížit")
            if scale > 1.01 {
                Divider().frame(height: 22).overlay(.white.opacity(0.2))
                Button { zoom(to: 1) } label: { Image(systemName: "arrow.down.right.and.arrow.up.left").frame(width: 40, height: 40) }
                    .accessibilityLabel("Zobrazit celý terč")
            }
        }
        .font(.body.weight(.semibold))
        .foregroundStyle(.white)
        .background(.black.opacity(0.55), in: Capsule())
    }

    private func magnify(side: CGFloat) -> some Gesture {
        MagnifyGesture()
            .onChanged { value in
                let next = clampScale(baseScale * value.magnification)
                let ratio = next / max(baseScale, 0.001)
                scale = next
                offset = clampOffset(CGSize(width: baseOffset.width * ratio, height: baseOffset.height * ratio), side: side)
            }
            .onEnded { _ in commit() }
    }

    private func pan(side: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 4)
            .onChanged { value in
                offset = clampOffset(CGSize(width: baseOffset.width + value.translation.width,
                                            height: baseOffset.height + value.translation.height), side: side)
            }
            .onEnded { _ in baseOffset = offset }
    }

    private func doubleTap(side: CGFloat) -> some Gesture {
        SpatialTapGesture(count: 2)
            .onEnded { value in
                if scale > 1.01 {
                    zoom(to: 1)
                } else {
                    let target: CGFloat = 4
                    let dx = value.location.x - side / 2
                    let dy = value.location.y - side / 2
                    withAnimation(.easeOut(duration: 0.25)) {
                        scale = target
                        offset = clampOffset(CGSize(width: -dx * (target - 1), height: -dy * (target - 1)), side: side)
                    }
                    commit()
                }
            }
    }

    private func zoom(to value: CGFloat) {
        let next = clampScale(value)
        let ratio = next / max(scale, 0.001)
        withAnimation(.easeOut(duration: 0.22)) {
            scale = next
            offset = next <= 1.01 ? .zero : CGSize(width: offset.width * ratio, height: offset.height * ratio)
        }
        commit()
    }

    private func commit() {
        if scale <= 1.01 { scale = 1; offset = .zero }
        baseScale = scale
        baseOffset = offset
        zoomed = scale > 1.01
    }

    private func clampScale(_ value: CGFloat) -> CGFloat { min(maxScale, max(1, value)) }

    private func clampOffset(_ value: CGSize, side: CGFloat) -> CGSize {
        let limit = side * (scale - 1) / 2
        return CGSize(width: min(limit, max(-limit, value.width)),
                      height: min(limit, max(-limit, value.height)))
    }
}

#if DEBUG
#Preview("Živě") {
    NavigationStack { MatchView() }.dartiqoPreview(PreviewSupport.store(players: 2))
}
#Preview("Výsledek") {
    NavigationStack { MatchView() }.dartiqoPreview(PreviewSupport.store(players: 2, finished: true))
}
#endif
