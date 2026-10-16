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
    var names: [String]
    var checkoutScore: Int
    var checkoutDarts: [String]
    var isCheckout: Bool
    var legsToWin: Int
    var setClosed: Bool
    var duration: Double
    var byBullOff = false
    var winnerPhoto: Data? = nil
    var winnerAsset: String? = nil
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
    @State private var showSettings = false
    @State private var sumText = ""
    @State private var finishPrompt = false
    @State private var bustPrompt = false
    @State private var error: String?
    @State private var revision = UUID()
    @State private var holdDarts: [Dart] = []
    @State private var isHoldingVisit = false
    @State private var holdSurface: ScoringSurface = .grid
    @State private var holdPlayer: Int?
    @State private var legCeremony: LegCeremony?
    /// Ceremony už odchází — krytí jen bledne, systémový sheet se nespouští.
    @State private var ceremonyLeaving = false
    /// Nový leg nejdřív dosedne, teprve pak bot hází.
    @State private var boardReady = true
    /// Statistiky po konci zápasu naskočí až po odchodu ceremonie.
    @State private var resultShown = false
    @State private var boardDetail: BoardDetailSelection?
    @State private var statsPlayer: BoardDetailSelection?
    @State private var boardZoomed = false
    /// 0 = všechny legy, jinak číslo legu.
    @State private var detailLeg: Int? = 0
    @State private var cameraHits: [CameraHit] = []
    @State private var correcting: Int?
    @State private var decidingLeg = false
    @State private var leavingHome = false
    /// Začátek právě běžícího úseku hry. Stopky stojí při pauze, mimo hru a na pozadí.
    @State private var clockStart: Date?
    @StateObject private var voice = VoiceScoreListener()
    /// Šipky po jedné, nebo součet celého kola.
    @State private var voiceMode: VoiceScoreMode = .darts
    @State private var showMatchXP = false
    var body: some View { clockTracking(screen) }
    private var screen: some View {
        matchPrompts
            .sheet(isPresented: $showLog) { visitLogSheet }
            .sheet(isPresented: $showSettings) { settingsSheet }
            .sheet(isPresented: correctionPresented, onDismiss: resumeHoldAfterCorrection) { correctionCover }
            .task(id: botTaskKey) { await throwBotDart() }
            .onAppear(perform: prepareMatch)
            .onDisappear(perform: leaveMatch)
            .onChange(of: voice.lastError) { _, message in
                if let message { error = message }
            }
            .onChange(of: isHoldingVisit) { _, holding in
                if holding { voice.stop() }
            }
    }
    private var matchCanvas: some View {
        ZStack {
            Group {
                if leavingHome {
                    MatchSavedSplash()
                } else if let game = store.activeMatch {
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
            if let ceremony = legCeremony {
                legCeremonyScreen(ceremony)
                    .zIndex(4)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(MatchColors.background)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { if !leavingHome { matchToolbar } }
        .toolbarBackground(MatchColors.background, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .preferredColorScheme(.dark)
        .tint(.white)
        .toolbar(leavingHome || (legCeremony != nil && !ceremonyLeaving) ? .hidden : .automatic, for: .navigationBar)
        .statusBarHidden(legCeremony != nil)
    }
    private var matchCovers: some View {
        matchCanvas
            .fullScreenCover(isPresented: $decidingLeg) {
                if let game = store.activeMatch {
                    BullOffView(
                        names: game.players.map(\.name),
                        bots: game.players.map(\.botLevel),
                        purpose: .decider,
                        onFinish: awardBullOff,
                        onCancel: { decidingLeg = false }
                    )
                }
            }
            .fullScreenCover(item: $boardDetail) { selection in
                if let game = store.activeMatch {
                    boardDetailScreen(game, player: selection.player)
                }
            }
            .sheet(item: $statsPlayer) { selection in
                if let game = store.activeMatch {
                    playerStatsSheet(game, player: selection.player)
                }
            }
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.28), value: isHoldingVisit)
    }
    private var matchPrompts: some View {
        matchCovers
            .alert("Přerušit zápas?", isPresented: $showLeave) {
                Button("Uložit a odejít") { saveAndLeave() }
                Button("Vymazat zápas", role: .destructive) { store.activeMatch = nil; dismiss() }
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
    @ViewBuilder
    private var visitLogSheet: some View {
        NavigationStack {
            if let game = store.activeMatch {
                VisitLog(game: game, onRewind: { rewind(to: $0) }).toolbar { ToolbarItem(placement: .confirmationAction) { Button("Hotovo") { showLog = false } } }
            }
        }
    }
    private var settingsSheet: some View {
        MatchSettingsSheet(
            paused: $paused,
            options: matchOptions,
            mode: store.activeMatch?.config.mode ?? .x01,
            showsBotTempo: settingsShowsBotTempo
        )
    }
    private var settingsShowsBotTempo: Bool {
        guard let game = store.activeMatch else { return false }
        return game.players.contains { $0.botLevel != nil } || game.ghostVisits != nil
    }
    @ViewBuilder
    private var correctionCover: some View {
        if let correcting { correctionSheet(correcting) }
    }
    private func prepareMatch() {
        if let game = store.activeMatch {
            seedSurface(for: game)
            UIApplication.shared.isIdleTimerDisabled = game.config.settings.keepAwake
            if game.currentPlayer.botLevel != nil || game.isGhostTurn { holdDarts = game.currentDarts }
        }
        syncClock()
    }
    private func seedSurface(for game: Match) {
        guard !didSeedSurface else { return }
        didSeedSurface = true
        if game.currentDarts.isEmpty && canUseTotal(game) && game.config.settings.entry == .total {
            surface = .total
        } else if game.config.settings.entry == .darts {
            surface = .board
        } else {
            surface = .grid
        }
    }
    private func leaveMatch() {
        voice.stop()
        flushClock()
        UIApplication.shared.isIdleTimerDisabled = false
    }

    @ToolbarContentBuilder
    private var matchToolbar: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button { showLeave = true } label: { Image(systemName: "xmark") }
                .accessibilityLabel("Odejít ze hry")
        }
        ToolbarItem(placement: .principal) {
            if let game = store.activeMatch {
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
        guard let g = store.activeMatch else { return "none" }
        // isHoldingVisit / legCeremony intentionally omitted — must not cancel mid-throw.
        return "\(g.id)-\(g.active)-\(g.leg)-\(g.visits.last?.id.uuidString ?? "start")-\(g.currentDarts.map(\.label).joined())-\(paused)-\(showSettings)-\(showLog)-\(showLeave)-\(statsPlayer != nil)-\(scenePhase == .active)-\(g.finished)-\(g.legWinner ?? -1)-\(revision)"
    }
    private var botIsThrowing: Bool {
        guard let game = store.activeMatch, !isHoldingVisit else { return false }
        // Během odchodu ceremonie už má být vidět terč, na který bot vzápětí hází.
        if legCeremony != nil && !ceremonyLeaving { return false }
        return game.currentPlayer.botLevel != nil || game.isGhostTurn
    }
    private var holdingBotVisit: Bool {
        guard isHoldingVisit, let player = holdPlayer, let game = store.activeMatch else { return false }
        return game.players[player].botLevel != nil || game.isGhost(player)
    }
    private var showingBotBoard: Bool { botIsThrowing || holdingBotVisit }
    private func stripDarts(for game: Match) -> [Dart] {
        if isHoldingVisit { return holdDarts }
        if game.currentPlayer.botLevel != nil || game.isGhostTurn { return holdDarts.isEmpty ? game.currentDarts : holdDarts }
        return game.currentDarts
    }
    private func live(_ game: Match) -> some View {
        let shown = game.liveProjection
        return ScrollView {
            VStack(spacing: 14) {
                VStack(spacing: 6) {
                    matchProgressStrip(game)
                    scoreboard(game, shown: shown)
                    liveStatsStrip(game, shown: shown)
                    if game.tracksGhostAverage, let ghostAvg = game.ghostAverage,
                       let human = game.players.indices.first(where: { game.players[$0].botLevel == nil && !game.isGhost($0) }) {
                        ghostRaceStrip(human: shown.average(for: human), ghost: ghostAvg)
                    }
                }
                if paused {
                    Label("Hra je pozastavená", systemImage: "pause.circle.fill").font(AppFont.title()).padding(24)
                    Button("Pokračovat") { paused = false }.buttonStyle(PrimaryButton())
                } else if game.needsBullOff && !isHoldingVisit {
                    bullOffCard(game)
                } else if game.legWinner != nil && !isHoldingVisit && legCeremony == nil {
                    // Ceremony overlay handles continuation; keep a quiet placeholder underneath.
                    Color.clear.frame(height: 1)
                } else {
                    gameStrip(game, shown: shown)
                    currentThrowStrip(game, shown: shown)
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
                    } else if isHoldingVisit {
                        // Součet už je v horním stripu — druhé okno by jen žralo místo.
                        if holdSurface != .total {
                            frozenHumanSurface(game)
                        }
                    } else if surface == .total && canUseTotal(game) {
                        totalInput(game)
                    } else if surface == .board {
                        boardInput(game)
                    } else if surface == .camera {
                        CameraScoreView(
                            calibration: store.boardCalibration,
                            labels: game.currentDarts.map(\.label),
                            dartCount: game.currentDarts.count,
                            onDart: { dart, point in recordCameraHit(dart, point: point) },
                            onCorrect: cameraHits.count == game.currentDarts.count ? { correcting = $0 } : nil
                        )
                    } else {
                        dartGrid(game, shown: shown)
                    }
                    }
                    .padding(.top, surface == .grid ? 8 : 14)
                    }
                }
            }.padding(.horizontal, 16).padding(.vertical, surface == .grid ? 6 : 10).frame(maxWidth: 780)
        }
        .scrollIndicators(.hidden)
        .scrollDisabled(surface == .grid && !paused && !showingBotBoard && !isHoldingVisit && !liveStatsNeedRoom(game))
        .safeAreaInset(edge: .bottom, spacing: 0) { bottomBar(game) }
        .opacity(boardReady || reduceMotion ? 1 : 0)
        .scaleEffect(boardReady || reduceMotion ? 1 : 0.965, anchor: .top)
        .animation(reduceMotion ? nil : .spring(response: 0.82, dampingFraction: 0.9), value: boardReady)
    }

    @ViewBuilder
    private func frozenHumanSurface(_ game: Match) -> some View {
        switch holdSurface {
        case .board:
            matchDartboard(marks: holdDarts, interactive: false)
        case .total:
            EmptyView()
        case .grid:
            matchDartboard(marks: holdDarts, interactive: false)
                .opacity(0.96)
        case .voice:
            visitSummaryCard(title: "Hlasové kolo", value: holdDarts.map(\.label).joined(separator: " · "))
        case .camera:
            VStack(spacing: 10) {
                Text("Kamera").font(AppFont.caption(13, weight: .semibold)).foregroundStyle(MatchColors.ink.opacity(0.55))
                Text("\(holdDarts.reduce(0) { $0 + $1.score })")
                    .font(AppFont.display(48, weight: .bold)).foregroundStyle(MatchColors.ink).monospacedDigit()
                CameraHitChips(
                    labels: holdDarts.map(\.label),
                    ink: MatchColors.ink,
                    fill: MatchColors.ink.opacity(0.07),
                    onCorrect: cameraHits.count == holdDarts.count && legCeremony == nil ? { correcting = $0 } : nil
                )
                if cameraHits.count == holdDarts.count {
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
        let visits = store.activeMatch?.visits.count ?? 0
        let pending = store.activeMatch?.currentDarts.count ?? 0
        if pending == 0, !isHoldingVisit { cameraHits = [] }
        hit(dart)
        let accepted = (store.activeMatch?.visits.count ?? 0) > visits || (store.activeMatch?.currentDarts.count ?? 0) > pending
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
        guard legCeremony == nil, var game = store.activeMatch, cameraHits.indices.contains(index) else { return }
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
        store.activeMatch = game
        cameraHits = Array(hits[..<index])
        var replay = darts
        replay[index] = dart
        for offset in index..<replay.count {
            let visits = store.activeMatch?.visits.count ?? 0
            let pending = store.activeMatch?.currentDarts.count ?? 0
            hit(replay[offset])
            let finished = (store.activeMatch?.visits.count ?? 0) > visits
            guard finished || (store.activeMatch?.currentDarts.count ?? 0) > pending else { break }
            cameraHits.append(hits[offset])
            if finished { break }
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
    private func scoreboard(_ game: Match,shown: Match) -> some View {
        let columns = min(2, game.players.count)
        let rows = stride(from: 0, to: game.players.count, by: columns).map { Array($0..<min($0 + columns, game.players.count)) }
        let activeIndex = isHoldingVisit ? (holdPlayer ?? game.active) : game.active
        let rowCount = max(1, rows.count)
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
            ScoreboardBannerCutout(
                centerX: ScoreboardBannerCutout.centerX(
                    activeIndex: activeIndex,
                    columns: columns
                ),
                cutFromTop: activeIndex / columns == 0,
                rowCount: rowCount
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
        return Button {
            statsPlayer = BoardDetailSelection(player: index)
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    playerAvatar(game, index: index, size: 22)
                    Text(player.name).font(AppFont.body(14, weight: .semibold)).lineLimit(1)
                    if player.botLevel != nil {
                        Image(systemName: "cpu").font(AppFont.caption(11, weight: .semibold))
                    } else if game.isGhost(index) {
                        Image(systemName: "person.fill.viewfinder").font(AppFont.caption(11, weight: .semibold))
                    }
                    Spacer(minLength: 4)
                    if game.config.playsSets {
                        Text("\(state.sets)")
                            .font(AppFont.body(14, weight: .bold))
                            .foregroundStyle(MatchColors.ink)
                            .frame(minWidth: 24, minHeight: 24)
                            .background(.white.opacity(0.85), in: RoundedRectangle(cornerRadius: 7))
                            .accessibilityLabel("\(state.sets) setů")
                    }
                    Text("\(state.legs)").font(AppFont.body(14, weight: .bold)).foregroundStyle(.white).frame(minWidth: 24, minHeight: 24).background(MatchColors.ink, in: RoundedRectangle(cornerRadius: 7)).accessibilityLabel("\(state.legs) vyhraných legů")
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
                    .contentTransition(.numericText(value: score.headlineNumber))
                    .frame(maxWidth: .infinity, minHeight: 80, maxHeight: 80, alignment: .leading)
                let chips = panelChips(game, shown: shown, index: index, fallback: score)
                if !chips.isEmpty {
                    panelChipRow(chips)
                }
            }
            .foregroundStyle(MatchColors.ink)
            .padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 16)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(active ? MatchColors.coral : MatchColors.amber)
        }
        .buttonStyle(.plain)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.25), value: active)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(active ? [.isSelected, .isButton] : .isButton)
        .accessibilityHint("Zobrazí statistiky ze zápasu")
        .accessibilityValue(active ? "Na tahu" : "")
    }

    private func playerLook(_ game: Match, index: Int) -> (photo: Data?, asset: String?) {
        guard game.players.indices.contains(index) else { return (nil, nil) }
        let player = game.players[index]
        if let level = player.botLevel { return (nil, BotLevel.get(level).photo) }
        if game.isGhost(index) { return (store.profile?.photoJPEG, nil) }
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
        case .perLeg, .hidden:
            break
        }
        return chips
    }

    private func averageChip(_ match: Match, player: Int, leg: Int?, title: String, accessibility: String) -> PanelChip {
        let darts = match.thrownDarts(for: player, leg: leg)
        let average = match.average(for: player, leg: leg)
        let text = darts == 0 ? "—" : String(format: "%.1f", average)
        return PanelChip(
            id: leg.map { "leg-\($0)" } ?? "match",
            title: title,
            value: text,
            number: average,
            accessibility: darts == 0 ? "\(accessibility) zatím není" : "\(accessibility) \(text)"
        )
    }

    private func panelChipRow(_ chips: [PanelChip]) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 4) { ForEach(chips) { panelChip($0) } }
            VStack(alignment: .leading, spacing: 4) { ForEach(chips) { panelChip($0) } }
        }
    }

    private func panelChip(_ chip: PanelChip) -> some View {
        HStack(spacing: 4) {
            Text(chip.title).font(AppFont.caption(12, weight: .heavy)).opacity(0.6)
            Text(chip.value)
                .font(AppFont.body(15, weight: .bold))
                .monospacedDigit()
                .contentTransition(.numericText(value: chip.number))
                .minimumScaleFactor(0.7)
                .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(MatchColors.ink.opacity(0.12), in: Capsule())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(chip.accessibility)
    }

    private func liveStatsNeedRoom(_ game: Match) -> Bool {
        guard game.config.mode == .x01 else { return false }
        let display = store.data.matchDisplay ?? MatchDisplay()
        return display.scope == .perLeg || display.showsExtraNumbers
    }

    @ViewBuilder
    private func liveStatsStrip(_ game: Match, shown: Match) -> some View {
        if liveStatsNeedRoom(game) {
            let display = store.data.matchDisplay ?? MatchDisplay()
            VStack(alignment: .leading, spacing: 10) {
                if display.scope == .perLeg {
                    legAverageBoard(game, shown: shown)
                }
                if display.showsExtraNumbers {
                    extraNumberRows(game, shown: shown, display: display)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }

    private func legAverageBoard(_ game: Match, shown: Match) -> some View {
        let legs = Array(Set(shown.visits.map(\.leg)).union([game.leg])).sorted()
        return VStack(alignment: .leading, spacing: 8) {
            Text("PRŮMĚR KAŽDÉ HRY")
                .font(AppFont.caption(11, weight: .heavy))
                .tracking(1.1)
                .foregroundStyle(.white.opacity(0.45))
            ScrollView(.horizontal) {
                Grid(alignment: .leading, horizontalSpacing: 6, verticalSpacing: 6) {
                    GridRow {
                        Color.clear.frame(width: 72, height: 1)
                        ForEach(legs, id: \.self) { leg in
                            Text("\(leg)")
                                .font(AppFont.caption(11, weight: .bold))
                                .foregroundStyle(leg == game.leg ? MatchColors.green : .white.opacity(0.45))
                                .frame(minWidth: 48)
                                .accessibilityLabel("Leg \(leg)")
                        }
                    }
                    ForEach(game.players.indices, id: \.self) { index in
                        GridRow {
                            Text(game.players[index].name)
                                .font(AppFont.caption(12, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.85))
                                .lineLimit(1)
                                .frame(width: 72, alignment: .leading)
                            ForEach(legs, id: \.self) { leg in
                                let darts = shown.thrownDarts(for: index, leg: leg)
                                let text = darts == 0 ? "—" : String(format: "%.1f", shown.average(for: index, leg: leg))
                                Text(text)
                                    .font(AppFont.body(15, weight: .bold))
                                    .monospacedDigit()
                                    .foregroundStyle(leg == game.leg ? MatchColors.green : .white)
                                    .frame(minWidth: 48)
                                    .padding(.vertical, 4)
                                    .background(
                                        leg == game.leg ? MatchColors.green.opacity(0.16) : Color.white.opacity(0.05),
                                        in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    )
                                    .accessibilityLabel(darts == 0 ? "\(game.players[index].name), leg \(leg), bez šipek" : "\(game.players[index].name), leg \(leg), průměr \(text)")
                            }
                        }
                    }
                }
            }
            .scrollIndicators(.hidden)
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
            Text(value)
                .font(AppFont.body(14, weight: .bold))
                .monospacedDigit()
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
            return ("\(state.remaining)", Double(state.remaining), "Ø", text, average, "Průměr \(text)")
        case .aroundClock:
            let done = min(21, max(0, state.clockTarget - 1))
            let headline = state.clockTarget >= 21 ? "BULL" : "\(state.clockTarget)"
            return (headline, Double(min(state.clockTarget, 21)), "Hotovo", "\(done)/21", Double(done), "Hotovo \(done) z 21")
        case .cricket:
            let closed = cricketNumbers.filter { state.marks[$0, default: 0] >= 3 }.count
            if game.config.settings.cricketNoScore {
                let rounds = game.states[index].rounds
                return ("\(closed)/7", Double(closed), "Kola", "\(rounds)", Double(rounds), "\(rounds) kol, zavřeno \(closed) ze 7")
            }
            return ("\(state.points)", Double(state.points), "Zavřeno", "\(closed)/7", Double(closed), "\(state.points) bodů, zavřeno \(closed) ze 7")
        case .countUp:
            let rounds = game.states[index].rounds
            let limit = game.config.settings.countUpRounds
            return ("\(state.points)", Double(state.points), "Kola", "\(rounds)/\(limit)", Double(rounds), "\(state.points) bodů, kolo \(rounds) z \(limit)")
        }
    }

    private var cricketNumbers: [Int] { [20, 19, 18, 17, 16, 15, 25] }

    @ViewBuilder
    private func gameStrip(_ game: Match, shown: Match) -> some View {
        switch game.config.mode {
        case .cricket:
            let index = isHoldingVisit ? (holdPlayer ?? game.active) : game.active
            CricketMarksCard(
                names: game.players.map(\.name),
                marksByPlayer: shown.states.map(\.marks),
                numbers: cricketNumbers,
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
        let name = game.players.indices.contains(player) ? game.players[player].name : "Hráč"
        return NavigationStack {
            ScrollView {
                resultPlayerReport(game, index: player)
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 24)
            }
            .scrollIndicators(.hidden)
            .background(MatchColors.background.ignoresSafeArea())
            .navigationTitle(name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Hotovo") { statsPlayer = nil }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .preferredColorScheme(.dark)
    }
    /// Current throw: tři šipky, nebo jeden součet kola (hlas / číselný zápis).
    @ViewBuilder
    private func currentThrowStrip(_ game: Match, shown: Match) -> some View {
        if let total = heldTotalScore(game) {
            totalScoreStrip(value: "\(total)", filled: true)
        } else if showsTotalScoreStrip(game) {
            let display = liveTotalDisplay()
            totalScoreStrip(value: display, filled: display != "—")
        } else {
            let darts = stripDarts(for: game)
            let guide = checkoutGuide(game, shown: shown, thrown: darts.count)
            HStack(spacing: 8) {
                ForEach(0..<3, id: \.self) { i in
                    let filled = darts.count > i
                    let suggested = (!filled && guide.route.indices.contains(i - darts.count)) ? guide.route[i - darts.count] : nil
                    let note = (!filled && suggested == nil && i == darts.count) ? guide.note : nil
                    ThrowSlotTile(
                        index: i,
                        dart: filled ? darts[i] : nil,
                        suggestion: suggested,
                        note: note,
                        setupLeave: suggested == nil ? nil : guide.setupLeave
                    )
                }
            }
            .frame(height: 88)
            .padding(10)
            .background(.white, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
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
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("SOUČET KOLA")
                    .font(AppFont.caption(11, weight: .heavy))
                    .tracking(1.0)
                    .foregroundStyle(MatchColors.ink.opacity(0.45))
                Text(value)
                    .font(AppFont.display(40, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(filled ? MatchColors.ink : MatchColors.ink.opacity(0.28))
                    .contentTransition(.numericText())
            }
            Spacer(minLength: 0)
            Image(systemName: "sum")
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(Theme.brand.opacity(filled ? 1 : 0.45))
                .frame(width: 56, height: 56)
                .background(MatchColors.ink.opacity(0.06), in: Circle())
        }
        .padding(.horizontal, 18)
        .frame(maxWidth: .infinity)
        .frame(height: 88)
        .padding(10)
        .background(.white, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .accessibilityLabel(filled ? "Součet kola \(value)" : "Součet kola")
    }

    private func matchProgressStrip(_ game: Match) -> some View {
        let player = isHoldingVisit ? (holdPlayer ?? game.active) : game.active
        return Text(playerTurnCaption(game, player: player))
            .font(AppFont.caption(11, weight: .bold))
            .foregroundStyle(.white.opacity(0.78))
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .frame(maxWidth: .infinity, minHeight: 26)
            .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            .contentTransition(.opacity)
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.35), value: game.leg)
            .accessibilityLabel(playerTurnCaption(game, player: player))
    }

    private func playerTurnCaption(_ game: Match, player: Int) -> String {
        let completedRounds = game.visits.lazy.filter { $0.leg == game.leg && $0.player == player }.count
        let round = isHoldingVisit ? max(1, completedRounds) : completedRounds + 1
        let heldDarts = isHoldingVisit ? holdDarts.count : game.currentDarts.count
        let dartsInVisit = min(3, heldDarts)
        if showsTotalScoreStrip(game) || (isHoldingVisit && holdSurface == .total) {
            return "Leg \(game.leg) · Kolo \(round) · Součet"
        }
        if game.config.mode == .x01, let limit = game.config.settings.dartLimit {
            let used = min(limit, isHoldingVisit ? completedRounds * 3 : completedRounds * 3 + heldDarts)
            return "Leg \(game.leg) · Kolo \(round) · Šipky \(used)/\(limit)"
        }
        return "Leg \(game.leg) · Kolo \(round) · Šipky \(dartsInVisit)/3"
    }

    /// Spodní lišta: Liquid Glass — Zpět, režim hlasu a způsob zápisu.
    @ViewBuilder
    private func bottomBar(_ game: Match) -> some View {
        let humanInput = !paused && game.legWinner == nil && !game.needsBullOff && !showingBotBoard && !isHoldingVisit
        let canUndo = isHoldingVisit || !game.currentDarts.isEmpty || !game.visits.isEmpty
        let showTotalConfirm = humanInput && surface == .total && canUseTotal(game)
        let showVoiceModes = surface == .voice && canUseTotal(game) && !isHoldingVisit
        if !paused && legCeremony == nil && (game.legWinner == nil || isHoldingVisit) {
            // Menu držíme mimo GlassEffectContainer — jinak iOS 26 při změně ikony/layoutu glitchuje výběr.
            HStack(spacing: 10) {
                GlassEffectContainer(spacing: 10) {
                    HStack(spacing: 10) {
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

                        if showTotalConfirm {
                            Button { resolveTotal(game) } label: {
                                Label(sumText.isEmpty ? "Potvrdit" : "Potvrdit \(sumText)", systemImage: "checkmark")
                                    .font(.headline)
                                    .foregroundStyle(sumText.isEmpty ? Color.secondary : Theme.onAccent)
                                    .frame(maxWidth: .infinity, minHeight: 52)
                                    .contentShape(Capsule())
                                    .contentTransition(.numericText())
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
        ManualScorePad(multiplier: $multiplier, focus: padFocus(game, shown: shown), onSelect: { store.selectionHaptic() }, onHit: hit)
    }
    private func canUseTotal(_ game: Match) -> Bool { game.config.mode == .x01 && !game.config.anyDoubleIn(players: game.players.count) }

    /// Mikrofon smí běžet jen při tvém zápisu — ne během bota, holdu ani pauzy.
    private func isVoiceArmed(_ game: Match) -> Bool {
        surface == .voice
            && !paused
            && !isHoldingVisit
            && legCeremony == nil
            && game.legWinner == nil
            && !game.needsBullOff
            && !game.finished
            && game.currentPlayer.botLevel == nil
            && !game.isGhostTurn
    }

    private var voiceSyncKey: String {
        guard let game = store.activeMatch else { return "none" }
        return "\(surface.rawValue)-\(game.active)-\(isHoldingVisit)-\(paused)-\(game.finished)-\(game.legWinner ?? -1)-\(game.needsBullOff)-\(botIsThrowing)"
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
            if isHoldingVisit { return holdSurface == .total ? "Součet zapsán" : "Kolo hotovo" }
            if botIsThrowing || holdingBotVisit { return "Vypnuto" }
            if paused { return "Pauza" }
            if recognizing { return "Zapisuju" }
            if listening { return "Poslouchám" }
            return "Připraven"
        }()
        let detail: String? = {
            if let unavailable { return unavailable }
            if isHoldingVisit {
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
            if let live = store.activeMatch {
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
            guard let live = store.activeMatch, isVoiceArmed(live) else { return }
            applyVoiceCommand(command, gameCanTotal: canUseTotal(live))
            if let updated = store.activeMatch {
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
            guard let game = store.activeMatch else { return }
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
        if let game = store.activeMatch {
            voice.updateMode(effectiveVoiceMode(for: game))
        }
    }

    private func changeSurface(_ value: ScoringSurface) {
        guard let live = store.activeMatch else { return }
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
                guard var game = store.activeMatch else { return }
                var options = game.config.settings
                guard options.entry != entry else { return }
                options.entry = entry
                game.config.options = options
                store.activeMatch = game
            }
        }
    }
    private func hit(_ dart: Dart) {
        guard !paused, !isHoldingVisit, legCeremony == nil, var game = store.activeMatch, game.currentPlayer.botLevel == nil, !game.finished, game.legWinner == nil, !game.needsBullOff else { return }
        let thrower = game.active
        let count = game.visits.count
        do {
            try game.recordDart(dart)
            let visitFinished = game.visits.count > count
            if visitFinished, let visit = game.visits.last {
                store.feedback(visit.credited, announce: surface != .voice)
                multiplier = 1
                applyVisitHold(game: game, darts: visit.darts, player: thrower, fromBot: false)
            } else {
                store.tapHaptic(.light)
                withAnimation(reduceMotion ? nil : .easeOut(duration: 0.16)) { store.activeMatch = game }
            }
        } catch { self.error = error.localizedDescription }
    }
    private func rewind(to visit: Visit) {
        guard var game = store.activeMatch else { return }
        guard game.rewind(before: visit.id) else {
            error = "Na toto kolo se už nejde vrátit. Starší zápis nemá uložený stav."
            return
        }
        isHoldingVisit = false
        holdPlayer = nil
        legCeremony = nil
        ceremonyLeaving = false
        boardReady = true
        holdDarts = []
        sumText = ""
        multiplier = 1
        withAnimation(reduceMotion ? nil : .snappy(duration: 0.35)) { store.activeMatch = game }
        revision = UUID()
        showLog = false
        store.feedback(nil)
    }
    private func undo() {
        guard legCeremony == nil, var game = store.activeMatch else { return }
        store.tapHaptic(.soft)
        if isHoldingVisit {
            isHoldingVisit = false
            holdPlayer = nil
        }
        game.undoLastInput()
        withAnimation(reduceMotion ? nil : .snappy(duration: 0.35)) { store.activeMatch = game }
        if cameraHits.count > game.currentDarts.count { cameraHits = Array(cameraHits.prefix(game.currentDarts.count)) }
        sumText = ""
        multiplier = 1
        revision = UUID()
        holdDarts = game.currentPlayer.botLevel != nil || game.isGhostTurn || !game.currentDarts.isEmpty ? game.currentDarts : []
        if !game.currentDarts.isEmpty && surface == .total { surface = .board }
    }
    /// Arm hold *before* publishing the advanced match so the UI never flashes the next player's surface.
    private func applyVisitHold(game: Match, darts: [Dart], player: Int, fromBot: Bool) {
        holdDarts = darts
        holdPlayer = player
        holdSurface = fromBot ? .board : surface
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            isHoldingVisit = true
        }
        withAnimation(reduceMotion ? nil : .snappy(duration: 0.35)) {
            store.activeMatch = game
        }
        scheduleVisitHold(darts: darts)
    }
    @MainActor private func scheduleVisitHold(darts: [Dart]) {
        let delay = store.activeMatch?.config.settings.botDelay ?? 1.5
        let legOver = store.activeMatch?.legWinner != nil
        // Keep the whole throw screen visible long enough to read before the turn flips.
        // A winning visit goes straight to the ceremony, which shows the checkout itself.
        let hold = legOver ? 0.35 : ScoringChrome.visitHoldSeconds(botDelay: delay, reduceMotion: reduceMotion)
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(hold * 1_000_000_000))
            guard isHoldingVisit, holdDarts == darts, correcting == nil else { return }
            finishVisitHold()
        }
    }
    @MainActor private func finishVisitHold() {
        if holdSurface == .camera { learnConfirmedHits() }
        guard let game = store.activeMatch else {
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
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.28)) {
            isHoldingVisit = false
            holdDarts = []
            holdPlayer = nil
        }
        if game.needsBullOff {
            decidingLeg = true
        } else {
            revision = UUID()
        }
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
            names: game.players.map(\.name),
            checkoutScore: visit?.credited ?? 0,
            checkoutDarts: visit?.darts.map(\.label) ?? [],
            isCheckout: visit?.checkout == true,
            legsToWin: game.config.legsToWin,
            setClosed: !game.finished && game.config.playsSets && game.states.contains { $0.legs >= game.config.legsToWin },
            duration: auto,
            byBullOff: game.bullOffLegs?[game.leg] == winner,
            winnerPhoto: playerLook(game, index: winner).photo,
            winnerAsset: playerLook(game, index: winner).asset
        )
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            ceremonyLeaving = false
            resultShown = false
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
        guard let ceremony = legCeremony, !ceremonyLeaving else { return }
        if reduceMotion {
            if ceremony.matchFinished { revealMatchResult() } else { revealNextLeg() }
            commitLegCeremonyDismiss()
            return
        }
        withAnimation(.easeInOut(duration: 0.62)) { ceremonyLeaving = true }
        let finished = ceremony.matchFinished
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 180_000_000)
            if finished { revealMatchResult() } else { revealNextLeg() }
            try? await Task.sleep(nanoseconds: 460_000_000)
            guard ceremonyLeaving else { return }
            commitLegCeremonyDismiss()
        }
    }
    /// Skóre se přetočí na start dalšího legu.
    private func revealNextLeg() {
        guard var game = store.activeMatch, game.legWinner != nil, !game.finished else { return }
        let newSet = legCeremony?.setClosed == true
        game.nextLeg()
        let starter = game.players.indices.contains(game.active) ? game.players[game.active].name : "Hráč"
        let leg = game.leg
        var hidden = Transaction()
        hidden.disablesAnimations = true
        withTransaction(hidden) { boardReady = false }
        withAnimation(reduceMotion ? nil : .spring(response: 0.82, dampingFraction: 0.9)) {
            store.activeMatch = game
            isHoldingVisit = false
            holdDarts = []
            holdPlayer = nil
            multiplier = 1
            sumText = ""
        }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 50_000_000)
            withAnimation(reduceMotion ? nil : .spring(response: 0.86, dampingFraction: 0.9)) { boardReady = true }
        }
        UIAccessibility.post(notification: .announcement, argument: "\(newSet ? "Nový set" : "Nový leg") \(leg). Začíná \(starter).")
    }
    /// Statistiky jsou pod blednoucí ceremonií, ať konec zápasu neskočí.
    private func revealMatchResult() {
        isHoldingVisit = false
        holdDarts = []
        holdPlayer = nil
    }
    private func animateResultIn() {
        guard !resultShown else { return }
        resultShown = true
    }
    private func commitLegCeremonyDismiss() {
        // Závoj je už pryč. Lišta se vrátí spolu s hřištěm, bez skoku.
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.4)) {
            legCeremony = nil
        }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 420_000_000)
            if legCeremony == nil { ceremonyLeaving = false }
        }
    }
    private func saveAndLeave() {
        guard !leavingHome else { return }
        leavingHome = true
        flushClock()
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: reduceMotion ? 700_000_000 : 1_400_000_000)
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
            .onChange(of: scenePhase) { _, _ in syncClock() }
            .onChange(of: paused) { _, _ in syncClock() }
            .onChange(of: store.activeMatch?.finished ?? true) { _, _ in syncClock() }
    }
    private var clockRuns: Bool {
        scenePhase == .active && !paused && store.activeMatch.map { !$0.finished } == true
    }
    private func syncClock() {
        if clockRuns {
            if clockStart == nil { clockStart = Date() }
        } else {
            flushClock()
        }
    }
    /// Připíše uběhlý úsek do zápasu. Průběžně, aby se čas neztratil ani při pádu appky.
    private func flushClock(keepRunning: Bool = false) {
        guard let start = clockStart else { return }
        let now = Date()
        if var game = store.activeMatch {
            game.addPlayTime(from: start, to: now)
            store.activeMatch = game
        }
        clockStart = keepRunning && clockRuns ? now : nil
    }
    private func awardBullOff(_ winner: Int) {
        guard var game = store.activeMatch, game.needsBullOff else { decidingLeg = false; return }
        game.awardBullOff(to: winner)
        store.activeMatch = game
        decidingLeg = false
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 450_000_000)
            guard let current = store.activeMatch, current.legWinner == winner, legCeremony == nil else { return }
            presentLegCeremony(current, winner: winner)
        }
    }
    private func continuePastDartLimit() {
        guard var game = store.activeMatch, game.needsBullOff else { return }
        game.continuePastDartLimit()
        store.activeMatch = game
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
    /// Celá obrazovka přes lištu i stavový řádek. Krátké shrnutí legu.
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
            Text(String(format: "Ty %.1f", human))
                .font(AppFont.caption(12, weight: .bold))
                .monospacedDigit()
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
            if paused || showSettings || showLog || showLeave || statsPlayer != nil { return false }
            do { try await Task.sleep(nanoseconds: 40_000_000) } catch { return false }
            if Task.isCancelled || key != botTaskKey { return false }
        }
        return true
    }
    @MainActor private func throwBotDart() async {
        guard scenePhase == .active, !paused, !showSettings, !showLog, !showLeave, statsPlayer == nil else { return }
        guard let game = store.activeMatch, !game.finished, game.legWinner == nil, !game.needsBullOff else { return }
        let auto = game.currentPlayer.botLevel != nil || game.isGhostTurn
        guard auto else { return }
        guard await waitUntilThrowIsClear() else { return }
        guard scenePhase == .active, !paused, !showSettings, !showLog, !showLeave, statsPlayer == nil, !isHoldingVisit, legCeremony == nil else { return }
        guard let ready = store.activeMatch, !ready.finished, ready.legWinner == nil, !ready.needsBullOff else { return }
        guard ready.currentPlayer.botLevel != nil || ready.isGhostTurn else { return }
        if holdDarts.count != ready.currentDarts.count { holdDarts = ready.currentDarts }
        let key = botTaskKey
        let thrower = ready.active
        let pending = ready.currentDarts.count
        let visits = ready.visits.count
        let delay = ready.config.settings.botDelay
        do { try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000)) } catch { return }
        guard !Task.isCancelled, key == botTaskKey, !isHoldingVisit, legCeremony == nil, var current = store.activeMatch else { return }
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
                store.feedback(current.visits.last?.credited)
                applyVisitHold(game: current, darts: shownDarts, player: thrower, fromBot: true)
            } else {
                holdDarts = shownDarts
                withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) { store.activeMatch = current }
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
        guard !isHoldingVisit, legCeremony == nil, let score = Int(sumText), var game = store.activeMatch, game.currentPlayer.botLevel == nil else { return }
        let thrower = game.active
        do {
            try game.submitTotal(score, checkoutDarts: darts)
            if let visit = game.visits.last {
                sumText = ""
                store.feedback(score, announce: surface != .voice)
                applyVisitHold(game: game, darts: visit.darts, player: thrower, fromBot: false)
                // Vždy součet jako jedno číslo — ne tři syntetické šipky.
                holdSurface = .total
            } else {
                store.activeMatch = game; sumText = ""; store.feedback(score, announce: surface != .voice)
            }
        } catch { self.error = error.localizedDescription }
    }
    private func bust(_ count: Int) {
        guard !isHoldingVisit, legCeremony == nil, var game = store.activeMatch, game.currentPlayer.botLevel == nil else { return }
        let thrower = game.active
        do {
            try game.recordBust(darts: count)
            if let visit = game.visits.last {
                sumText = ""
                store.feedback(0, announce: surface != .voice)
                applyVisitHold(game: game, darts: visit.darts, player: thrower, fromBot: false)
            } else {
                store.activeMatch = game; sumText = ""; store.feedback(0, announce: surface != .voice)
            }
        } catch { self.error = error.localizedDescription }
    }
    private var matchOptions: Binding<MatchOptions> {
        Binding(get:{ store.activeMatch?.config.settings ?? MatchOptions() },set:{ options in
            guard var game = store.activeMatch else { return }
            game.config.options = options; store.activeMatch = game
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
        var topSegments: [(label: String, count: Int, pct: Double)]
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
            var segmentHits: [Int: Int] = [:]
            var fieldHits: [String: Int] = [:]
            var triples = 0, doubles = 0, singles = 0, bulls = 0, misses = 0
            for dart in positioned {
                fieldHits[dart.label, default: 0] += 1
                if dart.segment == 0 { misses += 1; continue }
                if dart.segment == 25 {
                    bulls += 1
                    segmentHits[25, default: 0] += 1
                    continue
                }
                segmentHits[dart.segment, default: 0] += 1
                switch dart.multiplier {
                case 3: triples += 1
                case 2: doubles += 1
                default: singles += 1
                }
            }
            let top = segmentHits
                .sorted { lhs, rhs in lhs.value == rhs.value ? lhs.key > rhs.key : lhs.value > rhs.value }
                .prefix(5)
                .map { key, count -> (String, Int, Double) in
                    let label = key == 25 ? "Bull" : "\(key)"
                    return (label, count, Double(count) / Double(positioned.count) * 100)
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
                topSegments: top,
                topFields: fields
            )
        }
    }

    private func result(_ game: Match) -> some View {
        let order = game.players.indices.sorted { a, b in
            if game.winner == a { return true }
            if game.winner == b { return false }
            return game.states[a].legs > game.states[b].legs
        }
        let xp = store.matchXP(for: game)
        return ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                resultHeroBanner(game)
                    .modifier(ResultRise(shown: resultShown, delay: 0, reduceMotion: reduceMotion))
                if xp.hasAward {
                    resultXPBanner(xp)
                        .modifier(ResultRise(shown: resultShown, delay: 0.08, reduceMotion: reduceMotion))
                }
                Text("Hráči")
                    .font(.title3.bold())
                    .foregroundStyle(.white)
                    .padding(.top, 8)
                    .modifier(ResultRise(shown: resultShown, delay: 0.14, reduceMotion: reduceMotion))
                ForEach(Array(order.enumerated()), id: \.element) { offset, i in
                    resultPlayerReport(game, index: i)
                        .modifier(ResultRise(shown: resultShown, delay: 0.18 + Double(offset) * 0.06, reduceMotion: reduceMotion))
                }
                Button("Opravit poslední šipku") { undo() }
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.6))
                    .frame(maxWidth: .infinity, minHeight: 44)
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
        .onAppear { animateResultIn() }
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
        HStack(alignment: .center, spacing: 0) {
            ForEach(game.players.indices, id: \.self) { i in
                if i > 0 {
                    Text(":")
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.3))
                        .padding(.horizontal, 6)
                }
                VStack(spacing: 4) {
                    playerAvatar(game, index: i, size: 36)
                    Text("\(game.states[i].legs)")
                        .font(.system(size: 44, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(game.winner == i ? MatchColors.amber : .white)
                    Text(game.players[i].name)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.6))
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .frame(maxWidth: 360)
    }

    private func resultPlayerReport(_ game: Match, index: Int) -> some View {
        let visits = game.visits.filter { $0.player == index }
        let dartCount = visits.reduce(0) { $0 + $1.darts.count }
        let checkouts = visits.filter(\.checkout)
        let n180 = visits.filter { $0.credited == 180 }.count
        let board = BoardStats.make(from: game, player: index)
        let isWinner = game.winner == index
        let name = game.players[index].name
        return VStack(alignment: .leading, spacing: 16) {
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
                    Text("\(game.states[index].legs) legů · \(dartCount) šipek")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.55))
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

            if let board {
                resultBoardSection(board, player: index)
            }
        }
        .padding(16)
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(isWinner ? MatchColors.amber.opacity(0.4) : Color.white.opacity(0.06), lineWidth: 1)
        )
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
                    ZoomableDartboard(marks: board.positioned, zoomed: $boardZoomed)
                        .frame(maxWidth: 540)
                        .frame(maxWidth: .infinity)
                        .padding(8)
                        .background(Color.black.opacity(0.28), in: RoundedRectangle(cornerRadius: 28, style: .continuous))
                    Text("\(board.total) šipek zadaných přes terč")
                        .font(.footnote)
                        .foregroundStyle(.white.opacity(0.55))

                    HStack(spacing: 8) {
                        boardMetric("\(board.pct(board.total - board.misses)) %", "V terči", "scope")
                        boardMetric(String(format: "%.1f", board.averageScore), "Body / šipka", "number")
                        boardMetric("\(Int((board.averageRadius * 100).rounded())) %", "Od středu", "dot.scope")
                    }

                    VStack(alignment: .leading, spacing: 14) {
                        detailSectionTitle("KAM ŠIPKY PADALY", icon: "chart.bar.fill")
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

                    if !board.topSegments.isEmpty {
                        VStack(alignment: .leading, spacing: 14) {
                            detailSectionTitle("NEJČASTĚJŠÍ ČÍSLA", icon: "list.number")
                            VStack(spacing: 11) {
                                ForEach(Array(board.topSegments.enumerated()), id: \.offset) { _, row in
                                    boardBar(row.label, count: row.count, pct: row.pct)
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

    private func boardBar(_ label: String, count: Int, pct: Double) -> some View {
        HStack(spacing: 10) {
            Text(label)
                .font(AppFont.body(15, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 42, alignment: .leading)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.08))
                    Capsule()
                        .fill(MatchColors.green)
                        .frame(width: max(6, geo.size.width * pct / 100))
                }
            }
            .frame(height: 10)
            Text("\(count) · \(Int(pct.rounded())) %")
                .font(AppFont.caption(11, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(.white.opacity(0.65))
                .frame(width: 72, alignment: .trailing)
        }
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

    private func resultActions(_ game: Match) -> some View {
        HStack(spacing: 12) {
            Button {
                store.finish()
                store.activeMatch = Match(config: game.config, players: game.players, firstPlayer: (game.starter + 1) % game.players.count)
                multiplier = 1; sumText = ""; paused = false; holdDarts = []; isHoldingVisit = false; holdPlayer = nil; legCeremony = nil; ceremonyLeaving = false; resultShown = false; boardReady = true; revision = UUID()
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

/// Krátká obrazovka po uložení — pak návrat domů.
private struct MatchSavedSplash: View {
    var body: some View {
        VStack(spacing: 18) {
            Spacer()
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 64, weight: .semibold))
                .foregroundStyle(MatchColors.finish)
                .symbolRenderingMode(.hierarchical)
            Text("Hra uložena")
                .font(AppFont.title(28, weight: .bold))
                .foregroundStyle(.white)
            Text("Vracím tě na Domů…")
                .font(AppFont.body(16))
                .foregroundStyle(.white.opacity(0.6))
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(MatchColors.background.ignoresSafeArea())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Hra uložena")
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

/// Banner scoreboardu s výřezem na hraně u hráče na tahu.
private struct ScoreboardBannerCutout: Shape {
    /// Relativní střed výřezu na šířku banneru (0…1).
    var centerX: CGFloat
    var cutFromTop: Bool
    var rowCount: Int
    var corner: CGFloat = 22
    var cutWidth: CGFloat = 56
    var cutDepth: CGFloat = 18

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(centerX, cutFromTop ? 0 : 1) }
        set {
            centerX = newValue.first
            cutFromTop = newValue.second < 0.5
        }
    }

    static func centerX(activeIndex: Int, columns: Int) -> CGFloat {
        let cols = max(1, columns)
        let col = activeIndex % cols
        return (CGFloat(col) + 0.5) / CGFloat(cols)
    }

    func path(in rect: CGRect) -> Path {
        let rows = max(1, rowCount)
        let cellH = rect.height / CGFloat(rows)
        let cx = rect.minX + rect.width * min(max(centerX, 0), 1)
        let half = min(cutWidth, rect.width * 0.34) / 2
        let depth = min(cutDepth, cellH * 0.24)
        let left = max(rect.minX + corner + 4, cx - half)
        let right = min(rect.maxX - corner - 4, cx + half)

        var path = Path()
        path.move(to: CGPoint(x: rect.minX + corner, y: rect.minY))
        if cutFromTop {
            path.addLine(to: CGPoint(x: left, y: rect.minY))
            path.addCurve(
                to: CGPoint(x: right, y: rect.minY),
                control1: CGPoint(x: left, y: rect.minY + depth),
                control2: CGPoint(x: right, y: rect.minY + depth)
            )
        }
        path.addLine(to: CGPoint(x: rect.maxX - corner, y: rect.minY))
        path.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY + corner), control: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - corner))
        path.addQuadCurve(to: CGPoint(x: rect.maxX - corner, y: rect.maxY), control: CGPoint(x: rect.maxX, y: rect.maxY))
        if !cutFromTop {
            path.addLine(to: CGPoint(x: right, y: rect.maxY))
            path.addCurve(
                to: CGPoint(x: left, y: rect.maxY),
                control1: CGPoint(x: right, y: rect.maxY - depth),
                control2: CGPoint(x: left, y: rect.maxY - depth)
            )
        }
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
            .offset(y: shown || reduceMotion ? 0 : 22)
            .animation(reduceMotion ? nil : .spring(response: 0.62, dampingFraction: 0.84).delay(delay), value: shown)
    }
}

private struct LegCeremonyView: View {
    let ceremony: LegCeremony
    let reduceMotion: Bool
    let leaving: Bool
    let onContinue: () -> Void

    @State private var appeared = false
    @State private var progress: CGFloat = 0

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

    var body: some View {
        ZStack {
            background
                .opacity(shown ? 1 : 0)
            VStack(spacing: 0) {
                Spacer(minLength: 20)
                Label(badge.title, systemImage: badge.icon)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(accent)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(accent.opacity(0.16), in: Capsule())

                winnerMark
                    .padding(.top, 28)

                Text(winnerName)
                    .font(.largeTitle.bold())
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
                    .padding(.top, 18)
                Text(ceremony.matchFinished ? "vyhrává zápas" : "vyhrává leg \(ceremony.leg)")
                    .font(ceremony.matchFinished ? .title2.weight(.semibold) : .title3)
                    .foregroundStyle(.white.opacity(0.65))
                    .padding(.top, 2)

                if showsCheckout {
                    checkoutCard
                        .padding(.top, 28)
                }

                scoreboard
                    .padding(.top, showsCheckout ? 14 : 32)

                Spacer(minLength: 20)
                continueButton
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 24)
            .padding(.top, 12)
            .padding(.bottom, 12)
            .frame(maxWidth: 520)
            .opacity(shown ? 1 : 0)
            .offset(y: shown ? 0 : 22)
            .scaleEffect(shown ? 1 : 0.97, anchor: .center)
        }
        .animation(reduceMotion ? nil : .spring(response: 0.78, dampingFraction: 0.9), value: appeared)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .opacity(leaving ? 0 : 1)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.62), value: leaving)
        .statusBarHidden(true)
        .persistentSystemOverlays(.hidden)
        .preferredColorScheme(.dark)
        .contentShape(Rectangle())
        .onTapGesture(perform: onContinue)
        .onAppear {
            guard !appeared else { return }
            if reduceMotion {
                appeared = true
                progress = 1
                return
            }
            appeared = true
            withAnimation(.linear(duration: ceremony.duration)) { progress = 1 }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            ceremony.matchFinished
            ? "\(winnerName) vyhrává zápas."
            : showsCheckout
            ? "\(winnerName) zavřel na \(ceremony.checkoutScore) a vyhrává leg \(ceremony.leg)."
            : "\(winnerName) vyhrává leg \(ceremony.leg)."
        )
        .accessibilityHint(ceremony.matchFinished ? "Otevře statistiky zápasu" : "Pokračuj na další leg")
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
            ForEach(ceremony.names.indices, id: \.self) { i in
                if i > 0 { Divider().overlay(.white.opacity(0.08)).padding(.leading, 16) }
                let legs = ceremony.legs.indices.contains(i) ? ceremony.legs[i] : 0
                let isWinner = i == ceremony.winner
                HStack(spacing: 12) {
                    Text(ceremony.names[i])
                        .font(isWinner ? .body.weight(.semibold) : .body)
                        .foregroundStyle(isWinner ? .white : .white.opacity(0.7))
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    if ceremony.legsToWin <= 7 {
                        HStack(spacing: 5) {
                            ForEach(0..<ceremony.legsToWin, id: \.self) { n in
                                let newest = isWinner && legs > 0 && n == legs - 1
                                Circle()
                                    .fill(n < legs ? (isWinner ? accent : Color.white.opacity(0.7)) : Color.white.opacity(0.15))
                                    .frame(width: newest && shown ? 11 : 9, height: newest && shown ? 11 : 9)
                                    .scaleEffect(newest && !shown ? 0.4 : 1)
                                    .animation(reduceMotion ? nil : .spring(response: 0.6, dampingFraction: 0.82).delay(newest ? 0.28 : 0), value: appeared)
                            }
                        }
                        .accessibilityHidden(true)
                    }
                    Text("\(legs)")
                        .font(.system(.title2, design: .rounded).weight(.bold))
                        .monospacedDigit()
                        .foregroundStyle(isWinner ? accent : .white)
                        .frame(minWidth: 28, alignment: .trailing)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
        }
        .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private var continueButton: some View {
        Button(action: onContinue) {
            Text(ceremony.matchFinished ? "Statistiky" : ceremony.setClosed ? "Další set" : "Další leg")
                .font(.headline)
                .foregroundStyle(MatchColors.ink)
                .frame(maxWidth: .infinity, minHeight: 54)
                .background {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            accent
                            Rectangle()
                                .fill(.white.opacity(0.28))
                                .frame(width: geo.size.width * progress)
                        }
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
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
