import SwiftUI
import UIKit

private struct CameraHit {
    var dart: Dart
    /// Kde kamera hod viděla (obraz kamery 0…1).
    var point: SIMD2<Double>?
    var corrected = false
}

private enum MatchColors {
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
private enum ScoringSurface: String, CaseIterable, Identifiable {
    case grid, board, total, camera
    var id: String { rawValue }
    var title: String {
        switch self {
        case .grid: return "Čísla"
        case .board: return "Terč"
        case .total: return "Součet"
        case .camera: return "Kamera"
        }
    }
    var icon: String {
        switch self {
        case .grid: return "square.grid.3x3.fill"
        case .board: return "target"
        case .total: return "number"
        case .camera: return "camera.fill"
        }
    }
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
    @State private var boardDetail: BoardDetailSelection?
    @State private var boardZoomed = false
    /// 0 = všechny legy, jinak číslo legu.
    @State private var detailLeg: Int? = 0
    @State private var cameraHits: [CameraHit] = []
    @State private var correcting: Int?
    var body: some View {
        Group {
            if let game = store.activeMatch {
                if game.finished && !isHoldingVisit && legCeremony == nil { result(game) }
                else { live(game) }
            } else {
                EmptyCard(title: "Žádná rozehraná hra", subtitle: "Novou hru spustíš na záložce Hrát.")
                    .padding()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(MatchColors.background)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { matchToolbar }
        .toolbarBackground(MatchColors.background, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .preferredColorScheme(.dark)
        .tint(.white)
        .toolbar(legCeremony == nil ? .automatic : .hidden, for: .navigationBar)
        .fullScreenCover(item: $legCeremony) { ceremony in
            legCeremonyScreen(ceremony)
        }
        .fullScreenCover(item: $boardDetail) { selection in
            if let game = store.activeMatch {
                boardDetailScreen(game, player: selection.player)
            }
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.28), value: isHoldingVisit)
        .confirmationDialog("Přerušit zápas?", isPresented: $showLeave, titleVisibility: .visible) {
            Button("Uložit a odejít") { dismiss() }
            Button("Zahodit zápas", role: .destructive) { store.activeMatch = nil; dismiss() }
            Button("Pokračovat", role: .cancel) {}
        } message: { Text("Ukládá se i rozehrané kolo po jedné nebo dvou šipkách.") }
        .confirmationDialog("Kolik šipek jsi použil na zavření?", isPresented: $finishPrompt, titleVisibility: .visible) {
            ForEach(1...3, id: \.self) { count in Button("\(count) šipky · správné zavření") { submitTotal(darts: count) } }
            Button("Zrušit", role: .cancel) {}
        } message: { Text("Potvrď, že poslední šipka splnila pravidlo out.") }
        .confirmationDialog("Po kolika šipkách nastal přehoz?", isPresented: $bustPrompt, titleVisibility: .visible) {
            ForEach(1...3, id: \.self) { n in Button("\(n) šipky") { bust(n) } }
            Button("Zrušit", role: .cancel) {}
        }
        .alert("Zápis skóre", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) { Button("OK") {} } message: { Text(error ?? "") }
        .sheet(isPresented: $showLog) {
            NavigationStack {
                if let game = store.activeMatch {
                    VisitLog(game: game, onRewind: { rewind(to: $0) }).toolbar { ToolbarItem(placement: .confirmationAction) { Button("Hotovo") { showLog = false } } }
                }
            }
        }
        .sheet(isPresented: $showSettings) { settings }
        .sheet(isPresented: Binding(get: { correcting != nil }, set: { if !$0 { correcting = nil } }), onDismiss: resumeHoldAfterCorrection) {
            if let correcting { correctionSheet(correcting) }
        }
        .task(id: botTaskKey) { await throwBotDart() }
        .onAppear {
            if let game = store.activeMatch {
                if game.currentDarts.isEmpty && canUseTotal(game) && game.config.settings.entry == .total {
                    surface = .total
                } else if game.config.settings.entry == .darts {
                    surface = .board
                } else {
                    surface = .grid
                }
                UIApplication.shared.isIdleTimerDisabled = game.config.settings.keepAwake
                if game.currentPlayer.botLevel != nil { holdDarts = game.currentDarts }
            }
        }
        .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
    }

    @ToolbarContentBuilder
    private var matchToolbar: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button { showLeave = true } label: { Image(systemName: "xmark") }
                .accessibilityLabel("Odejít ze hry")
        }
        ToolbarItem(placement: .principal) {
            if let game = store.activeMatch {
                VStack(spacing: 1) {
                    Text(game.config.mode.shortTitle).font(.headline)
                    Text(legCaption(game)).font(.caption2).foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
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
        return "\(g.id)-\(g.active)-\(g.leg)-\(g.visits.last?.id.uuidString ?? "start")-\(g.currentDarts.map(\.label).joined())-\(paused)-\(showSettings)-\(showLog)-\(showLeave)-\(scenePhase == .active)-\(g.finished)-\(g.legWinner ?? -1)-\(revision)"
    }
    private var botIsThrowing: Bool {
        guard let game = store.activeMatch, !isHoldingVisit, legCeremony == nil else { return false }
        return game.currentPlayer.botLevel != nil
    }
    private var holdingBotVisit: Bool {
        guard isHoldingVisit, let player = holdPlayer, let game = store.activeMatch else { return false }
        return game.players[player].botLevel != nil
    }
    private var showingBotBoard: Bool { botIsThrowing || holdingBotVisit }
    private func stripDarts(for game: Match) -> [Dart] {
        if isHoldingVisit { return holdDarts }
        if game.currentPlayer.botLevel != nil { return holdDarts.isEmpty ? game.currentDarts : holdDarts }
        return game.currentDarts
    }
    private func live(_ game: Match) -> some View {
        let shown = game.liveProjection
        return ScrollView {
            VStack(spacing: 14) {
                scoreboard(game, shown: shown)
                if paused {
                    Label("Hra je pozastavená", systemImage: "pause.circle.fill").font(AppFont.title()).padding(24)
                    Button("Pokračovat") { paused = false }.buttonStyle(PrimaryButton())
                } else if game.legWinner != nil && !isHoldingVisit && legCeremony == nil {
                    // Ceremony overlay handles continuation; keep a quiet placeholder underneath.
                    Color.clear.frame(height: 1)
                } else {
                    if game.config.mode == .cricket { CricketTable(game: shown) }
                    currentThrowStrip(game, shown: shown)
                    // Keep bot board on one view identity so the 3rd dart / hold does not remount and flash.
                    Group {
                    if showingBotBoard {
                        botBoard(game)
                    } else if isHoldingVisit {
                        frozenHumanSurface(game)
                    } else {
                        if surface == .total && canUseTotal(game) {
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
                            dartGrid
                        }
                    }
                    }
                    .padding(.top, 14)
                }
            }.padding(.horizontal, 16).padding(.vertical, 10).frame(maxWidth: 780)
        }
        .scrollIndicators(.hidden)
        .safeAreaInset(edge: .bottom, spacing: 0) { bottomBar(game) }
    }

    @ViewBuilder
    private func frozenHumanSurface(_ game: Match) -> some View {
        switch holdSurface {
        case .board:
            TouchDartboard(marks: holdDarts, interactive: false) { _ in }
                .allowsHitTesting(false)
                .frame(maxWidth: 420)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)
        case .total:
            visitSummaryCard(title: "Součet kola", value: "\(holdDarts.reduce(0) { $0 + $1.score })")
        case .grid:
            TouchDartboard(marks: holdDarts, interactive: false) { _ in }
                .allowsHitTesting(false)
                .frame(maxWidth: 420)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)
                .opacity(0.96)
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
        VStack(spacing: 10) {
            Text(title).font(AppFont.caption(13, weight: .semibold)).foregroundStyle(MatchColors.ink.opacity(0.55))
            Text(value).font(AppFont.display(48, weight: .bold)).foregroundStyle(MatchColors.ink).monospacedDigit()
            Text(holdDarts.map(\.label).joined(separator: " · "))
                .font(AppFont.body(15, weight: .semibold))
                .foregroundStyle(MatchColors.ink.opacity(0.7))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
        .padding(.horizontal, 16)
        .background(.white, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
    private func legCaption(_ game: Match) -> String {
        if game.config.mode == .x01 || game.config.mode == .cricket { return game.config.lengthLine }
        return game.config.summary
    }
    private func scoreboard(_ game: Match,shown: Match) -> some View {
        let columns = min(2, game.players.count)
        let rows = stride(from: 0, to: game.players.count, by: columns).map { Array($0..<min($0 + columns, game.players.count)) }
        return Grid(horizontalSpacing: 0, verticalSpacing: 0) {
            ForEach(rows, id: \.first) { row in
                GridRow {
                    ForEach(row, id: \.self) { i in
                        playerPanel(game, shown: shown, index: i)
                    }
                    if row.count < columns { Color.clear.gridCellUnsizedAxes([.horizontal, .vertical]) }
                }
            }
        }.clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
    private func playerPanel(_ game: Match, shown: Match, index: Int) -> some View {
        let player = game.players[index]
        let active = (!isHoldingVisit && legCeremony == nil && game.active == index)
            || (isHoldingVisit && holdPlayer == index)
        let state = shown.states[index]
        let value = game.config.mode == .x01 ? "\(state.remaining)" : game.config.mode == .aroundClock ? (state.clockTarget >= 21 ? "BULL" : "\(state.clockTarget)") : "\(state.points)"
        let x01 = game.config.mode == .x01
        let stat = x01 ? String(format: "%.1f", shown.average(for: index)) : "\(game.states[index].rounds)"
        return VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Text(player.name).font(AppFont.body(14, weight: .semibold)).lineLimit(1)
                if player.botLevel != nil { Image(systemName: "cpu").font(AppFont.caption(11, weight: .semibold)) }
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
            Text(value)
                .font(AppFont.display(72, weight: .bold))
                .monospacedDigit()
                .minimumScaleFactor(0.5)
                .lineLimit(1)
                .foregroundStyle(active ? Color.white : MatchColors.ink)
                .contentTransition(.numericText(value: Double(x01 ? state.remaining : state.points)))
                .frame(maxWidth: .infinity, minHeight: 80, maxHeight: 80, alignment: .leading)
            HStack(spacing: 4) {
                Text(x01 ? "Ø" : "Kola").font(AppFont.caption(12, weight: .heavy)).opacity(0.6)
                Text(stat).font(AppFont.body(15, weight: .bold)).monospacedDigit().contentTransition(.numericText())
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(MatchColors.ink.opacity(0.12), in: Capsule())
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(x01 ? "Průměr \(stat)" : "\(stat) kol")
        }
        .foregroundStyle(MatchColors.ink)
        .padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(active ? MatchColors.coral : MatchColors.amber)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.25), value: active)
        .accessibilityElement(children: .combine).accessibilityAddTraits(active ? .isSelected : [])
    }
    /// Current throw: thrown / AI tip / empty as three distinct tiles.
    private func currentThrowStrip(_ game: Match, shown: Match) -> some View {
        let darts = stripDarts(for: game)
        let guide = checkoutGuide(game, shown: shown, thrown: darts.count)
        return HStack(spacing: 8) {
            ForEach(0..<3, id: \.self) { i in
                let filled = darts.count > i
                let suggested = (!filled && guide.route.indices.contains(i - darts.count)) ? guide.route[i - darts.count] : nil
                let note = (!filled && suggested == nil && i == darts.count) ? guide.note : nil
                throwSlotTile(
                    index: i,
                    dart: filled ? darts[i] : nil,
                    suggestion: suggested,
                    note: note,
                    setupLeave: suggested == nil ? nil : guide.setupLeave
                )
            }
        }
        .padding(10)
        .background(.white, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Aktuální hod")
    }

    @ViewBuilder
    private func throwSlotTile(index: Int, dart: Dart?, suggestion: Dart?, note: String?, setupLeave: String? = nil) -> some View {
        if let dart {
            VStack(spacing: 4) {
                Text("\(index + 1)")
                    .font(AppFont.caption(10, weight: .bold))
                    .foregroundStyle(MatchColors.ink.opacity(0.4))
                Text("\(dart.score)")
                    .font(AppFont.display(26, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(MatchColors.ink)
                Text(dart.label)
                    .font(AppFont.caption(12, weight: .bold))
                    .foregroundStyle(MatchColors.ink.opacity(0.65))
            }
            .frame(maxWidth: .infinity, minHeight: 78)
            .background(MatchColors.ink.opacity(0.06), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .accessibilityLabel("\(index + 1). šipka \(dart.label)")
        } else if let suggestion {
            let setup = setupLeave != nil
            VStack(spacing: 5) {
                HStack(spacing: 3) {
                    Image(systemName: setup ? "arrow.turn.up.right" : "sparkles")
                        .font(.system(size: 9, weight: .bold))
                    Text(setup ? "Sehrávka" : "AI")
                        .font(AppFont.caption(10, weight: .heavy))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                .foregroundStyle(.white.opacity(0.85))
                Text(suggestion.label)
                    .font(AppFont.display(28, weight: .heavy))
                    .foregroundStyle(.white)
                    .minimumScaleFactor(0.7)
                    .lineLimit(1)
                Text(setup ? "na \(setupLeave ?? "")" : "\(suggestion.score)")
                    .font(AppFont.caption(12, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(.white.opacity(0.75))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .frame(maxWidth: .infinity, minHeight: 78)
            .background(setup ? MatchColors.setupTip : MatchColors.aiTip, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(setup ? MatchColors.amber : MatchColors.green.opacity(0.55), lineWidth: 1.5)
            )
            .accessibilityLabel(setup
                ? "\(index + 1). šipka, sehrávka na \(setupLeave ?? ""), hoď \(suggestion.label)"
                : "\(index + 1). šipka, AI nápověda \(suggestion.label)")
        } else {
            VStack(spacing: 4) {
                Text("\(index + 1)")
                    .font(AppFont.caption(10, weight: .bold))
                    .foregroundStyle(MatchColors.ink.opacity(0.35))
                Text("—")
                    .font(AppFont.display(26, weight: .bold))
                    .foregroundStyle(MatchColors.ink.opacity(0.22))
                Text(note ?? "\(index + 1). šipka")
                    .font(AppFont.caption(11, weight: .semibold))
                    .foregroundStyle(MatchColors.ink.opacity(0.4))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .frame(maxWidth: .infinity, minHeight: 78)
            .background(MatchColors.aiTipSoft.opacity(note != nil ? 0.55 : 0.35), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .accessibilityLabel(note.map { "\(index + 1). šipka, \($0)" } ?? "\(index + 1). šipka volná")
        }
    }

    /// Spodní lišta: Zpět, potvrzení součtu a způsob zápisu.
    @ViewBuilder
    private func bottomBar(_ game: Match) -> some View {
        let humanInput = !paused && game.legWinner == nil && !showingBotBoard && !isHoldingVisit
        let canUndo = isHoldingVisit || !game.currentDarts.isEmpty || !game.visits.isEmpty
        if !paused && legCeremony == nil && (game.legWinner == nil || isHoldingVisit) {
            HStack(spacing: 10) {
                Button { undo() } label: {
                    Label("Zpět", systemImage: "arrow.uturn.backward")
                }
                .buttonStyle(.glass)
                .disabled(!canUndo)
                .accessibilityHint("Vrátí poslední šipku, včetně hodů bota")

                if humanInput && surface == .total && canUseTotal(game) {
                    Button { resolveTotal(game) } label: {
                        Label(sumText.isEmpty ? "Potvrdit" : "Potvrdit \(sumText)", systemImage: "checkmark")
                            .frame(maxWidth: .infinity)
                            .contentTransition(.numericText())
                    }
                    .buttonStyle(.glassProminent)
                    .tint(MatchColors.finish)
                    .disabled(sumText.isEmpty)
                    .accessibilityHint("Odečte zadaný součet kola")
                } else {
                    Spacer(minLength: 0)
                }

                if humanInput {
                    Menu {
                        Picker("Způsob zápisu", selection: Binding(get: { surface }, set: { changeSurface($0) })) {
                            ForEach(ScoringSurface.allCases) { item in
                                if item != .total || canUseTotal(game) {
                                    Label(item.title, systemImage: item.icon).tag(item)
                                }
                            }
                        }
                    } label: {
                        Label(surface.title, systemImage: surface.icon)
                            .labelStyle(.iconOnly)
                            .frame(width: 24, height: 24)
                    }
                    .buttonStyle(.glass)
                    .buttonBorderShape(.circle)
                    .accessibilityLabel("Způsob zápisu")
                    .accessibilityValue(surface.title)
                }
            }
            .font(.headline)
            .lineLimit(1)
            .labelStyle(.titleAndIcon)
            .controlSize(.large)
            .buttonBorderShape(.capsule)
            .tint(.white)
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 6)
            .frame(maxWidth: 780)
            .frame(maxWidth: .infinity)
        }
    }

    private func botBoard(_ game: Match) -> some View {
        let darts = stripDarts(for: game)
        let name = holdPlayer.map { game.players[$0].name } ?? game.currentPlayer.name
        return ZStack(alignment: .topLeading) {
            TouchDartboard(marks: darts, interactive: false) { _ in }
                .allowsHitTesting(false)
                .frame(maxWidth: 440)
                .frame(maxWidth: .infinity)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(holdingBotVisit ? "\(name) dokončil hod" : "\(name) hází")
        .accessibilityValue(darts.map(\.label).joined(separator: ", "))
    }

    private func boardInput(_ game: Match) -> some View {
        ZStack(alignment: .topTrailing) {
            TouchDartboard(marks: game.currentDarts, onHit: { hit($0) })
                .frame(maxWidth: 420)
                .frame(maxWidth: .infinity)
        }
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private struct CheckoutGuide {
        var route: [Dart] = []
        /// Short note for the next empty slot when there is no dart suggestion.
        var note: String? = nil
        /// Set when `route` is a setup toward this leave, not a finish.
        var setupLeave: String? = nil
    }

    private func checkoutGuide(_ game: Match, shown: Match, thrown: Int) -> CheckoutGuide {
        guard !isHoldingVisit, game.currentPlayer.botLevel == nil else { return CheckoutGuide() }
        guard game.config.mode == .x01, game.config.settings.checkoutHints else { return CheckoutGuide() }
        let state = shown.states[game.active]
        let dartsLeft = max(0, 3 - thrown)
        if !state.opened {
            return CheckoutGuide(note: "double in")
        }
        guard dartsLeft > 0 else { return CheckoutGuide() }
        let rule = game.config.outRule(for: game.active)
        if let route = Checkout.route(for: state.remaining, rule: rule, darts: dartsLeft) {
            return CheckoutGuide(route: route)
        }
        if state.remaining <= 170, let setup = Checkout.setup(for: state.remaining, rule: rule, darts: dartsLeft) {
            return CheckoutGuide(route: setup.darts, setupLeave: setup.leaveLabel)
        }
        return CheckoutGuide()
    }
    private var dartGrid: some View {
        VStack(spacing:0) {
            HStack(spacing:0) {
                ForEach(1...3,id:\.self) { n in
                    Button { multiplier = n } label:{ Text(["Single","Double","Triple"][n-1]).font(AppFont.caption(12, weight: .semibold)).frame(maxWidth:.infinity,minHeight:47).overlay(alignment:.bottom) { Rectangle().fill(multiplier == n ? MatchColors.coral : .clear).frame(height:3) } }.accessibilityAddTraits(multiplier == n ? .isSelected : [])
                }
                Button { hit(Dart(25,2)) } label:{ VStack(spacing:2) { Text("Bull").font(AppFont.caption(12, weight: .bold)); Text("50").font(AppFont.caption(12)) }.frame(maxWidth:.infinity,minHeight:47) }
                Button { hit(Dart(25)) } label:{ VStack(spacing:2) { Text("Outer").font(AppFont.caption(12, weight: .bold)); Text("25").font(AppFont.caption(12)) }.frame(maxWidth:.infinity,minHeight:47) }
                Button { hit(.miss) } label:{ VStack(spacing:2) { Text("Mimo").font(AppFont.caption(12, weight: .bold)); Text("0").font(AppFont.caption(12)) }.frame(maxWidth:.infinity,minHeight:47) }
                    .accessibilityLabel("Mimo terč, 0 bodů")
            }
            LazyVGrid(columns:Array(repeating:GridItem(.flexible(),spacing:1),count:5),spacing:1) {
                ForEach(1...20,id:\.self) { n in
                    Button { hit(Dart(n,multiplier)) } label:{ Text("\(n)").font(AppFont.display(26, weight: .bold)).frame(maxWidth:.infinity,minHeight:46).background(MatchColors.background) }
                        .accessibilityLabel("\(multiplier == 3 ? "Triple" : multiplier == 2 ? "Double" : "Single") \(n), zapíše se ihned")
                }
            }.padding(.vertical,1).background(.white.opacity(0.13))
        }
    }
    private func canUseTotal(_ game: Match) -> Bool { game.config.mode == .x01 && !game.config.anyDoubleIn(players: game.players.count) }
    private func changeSurface(_ value: ScoringSurface) {
        guard var game = store.activeMatch else { return }
        if value == .total && !game.currentDarts.isEmpty { error = "Součet lze zapnout na začátku kola. Dokonči nebo vrať rozehrané šipky."; return }
        surface = value; sumText = ""
        var options = game.config.settings; options.entry = value == .total ? .total : .darts
        game.config.options = options; store.activeMatch = game
    }
    private func hit(_ dart: Dart) {
        guard !paused, !isHoldingVisit, legCeremony == nil, var game = store.activeMatch, game.currentPlayer.botLevel == nil, !game.finished, game.legWinner == nil else { return }
        let thrower = game.active
        let count = game.visits.count
        do {
            try game.recordDart(dart)
            let visitFinished = game.visits.count > count
            if visitFinished, let visit = game.visits.last {
                store.feedback(visit.credited)
                multiplier = 1
                applyVisitHold(game: game, darts: visit.darts, player: thrower, fromBot: false)
            } else {
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
        holdDarts = game.currentPlayer.botLevel != nil || !game.currentDarts.isEmpty ? game.currentDarts : []
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
        let hold = legOver ? 0.35 : reduceMotion ? 0.45 : max(1.8, min(2.8, delay + 0.6))
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
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.28)) {
            isHoldingVisit = false
            holdDarts = []
            holdPlayer = nil
        }
        if let winner = game.legWinner {
            presentLegCeremony(game, winner: winner)
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
            duration: auto
        )
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.35)) {
            legCeremony = ceremony
        }
        let ceremonyID = ceremony.id
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(auto * 1_000_000_000))
            guard legCeremony?.id == ceremonyID else { return }
            dismissLegCeremony()
        }
    }
    private func dismissLegCeremony() {
        guard let ceremony = legCeremony else { return }
        if ceremony.matchFinished {
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.25)) {
                legCeremony = nil
            }
            return
        }
        guard var game = store.activeMatch, game.legWinner != nil, !game.finished else {
            legCeremony = nil
            return
        }
        game.nextLeg()
        multiplier = 1
        sumText = ""
        holdDarts = []
        isHoldingVisit = false
        holdPlayer = nil
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.3)) {
            store.activeMatch = game
            legCeremony = nil
        }
        revision = UUID()
    }
    /// Celá obrazovka přes lištu i stavový řádek. Krátké shrnutí legu.
    private func legCeremonyScreen(_ ceremony: LegCeremony) -> some View {
        LegCeremonyView(ceremony: ceremony, reduceMotion: reduceMotion) { dismissLegCeremony() }
    }
    @MainActor private func throwBotDart() async {
        guard scenePhase == .active, !paused, !showSettings, !showLog, !showLeave, !isHoldingVisit, legCeremony == nil else { return }
        guard let game = store.activeMatch, !game.finished, game.legWinner == nil, game.currentPlayer.botLevel != nil else { return }
        if holdDarts.count != game.currentDarts.count { holdDarts = game.currentDarts }
        let key = botTaskKey
        let thrower = game.active
        do { try await Task.sleep(nanoseconds: UInt64(game.config.settings.botDelay * 1_000_000_000)) } catch { return }
        guard !Task.isCancelled, key == botTaskKey, !isHoldingVisit, legCeremony == nil, var current = store.activeMatch, current.currentPlayer.botLevel != nil else { return }
        var rng = SystemRandomNumberGenerator()
        let projected = current.liveProjection
        let target = Bot.target(in: projected, dartsLeft: 3 - current.currentDarts.count)
        let dart = Bot.throwDart(at: target, level: current.currentPlayer.botLevel ?? 1, using: &rng)
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
        VStack(spacing:10) {
            HStack { Text(sumText.isEmpty ? "Součet kola" : sumText).font(AppFont.display(26, weight: .bold)).foregroundStyle(MatchColors.ink); Spacer(); Button { if !sumText.isEmpty { sumText.removeLast() } } label:{ Image(systemName:"delete.left").frame(width:44,height:44) }.foregroundStyle(MatchColors.ink) }.padding(.horizontal,18).frame(height:58).background(.white,in:Capsule())
            HStack(spacing:5) {
                ForEach([26,41,60,100,140,180],id:\.self) { score in
                    Button { sumText = "\(score)"; resolveTotal(game) } label:{ Text("\(score)").font(AppFont.caption(12, weight: .bold)).frame(maxWidth:.infinity,minHeight:44).background(.white.opacity(0.08),in:RoundedRectangle(cornerRadius:10)) }.accessibilityLabel("Odečíst \(score) bodů ihned")
                }
            }
            LazyVGrid(columns:Array(repeating:GridItem(.flexible(),spacing:1),count:3),spacing:1) {
                ForEach(["1","2","3","4","5","6","7","8","9","C","0","BUST"],id:\.self) { key in
                    Button {
                        if key == "C" { sumText = "" }
                        else if key == "BUST" { bustPrompt = true }
                        else if sumText.count < 3 { sumText = sumText == "0" ? key : sumText + key }
                    } label:{ Text(key).font(key == "BUST" ? AppFont.caption(14, weight: .bold) : AppFont.display(24, weight: .bold)).frame(maxWidth:.infinity,minHeight:48).background(MatchColors.background) }
                }
            }.padding(1).background(.white.opacity(0.13))
        }
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
                store.feedback(score)
                applyVisitHold(game: game, darts: visit.darts, player: thrower, fromBot: false)
            } else {
                store.activeMatch = game; sumText = ""; store.feedback(score)
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
                store.feedback(0)
                applyVisitHold(game: game, darts: visit.darts, player: thrower, fromBot: false)
            } else {
                store.activeMatch = game; sumText = ""; store.feedback(0)
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
    private var settings: some View {
        NavigationStack {
            Form {
                Section {
                    Button(paused ? "Pokračovat ve hře" : "Pozastavit hru",systemImage:paused ? "play.fill" : "pause.fill") { paused.toggle(); showSettings = false }
                }
                Section("Ovládání") {
                    Toggle("Nápověda zavření",isOn:matchOptions.checkoutHints)
                    Toggle("Nezhasínat displej",isOn:matchOptions.keepAwake)
                    Picker("Tempo šipek bota",selection:matchOptions.botDelay) { Text("Rychlé · 0,5 s").tag(0.5); Text("Plynulé · 1,5 s").tag(1.5); Text("Klidné · 3 s").tag(3.0) }
                    Toggle("Hlasové skóre",isOn:$store.data.voice)
                    Toggle("Haptika",isOn:$store.data.haptics)
                }
                Section {
                    Text("Každý zásah z čísel nebo terče se odečte ihned. Po třetí šipce, přehozu nebo zavření se kolo automaticky ukončí.").font(.footnote)
                    Text("Na terči klepni pro zápis. Podržením otevřeš zvětšený terč a vybereš přesné pole.").font(.footnote)
                    Text("Po dokončení kola zůstane obrazovka chvíli stát, pak se přepne na dalšího hráče.").font(.footnote)
                    Text("Po ukončení legu se ukáže celoobrazovková zpráva — klepni, nebo počkej.").font(.footnote)
                    Text("Zpět vrací jednu šipku. Funguje i během kontroly hodu bota.").font(.footnote)
                }
            }.navigationTitle("Nastavení zápasu").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement:.confirmationAction) { Button("Hotovo") { store.save(); showSettings = false } } }
                .onDisappear { store.save() }
        }.tint(MatchColors.green).preferredColorScheme(.dark)
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
        return ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                resultHeroBanner(game)
                Text("Hráči")
                    .font(.title3.bold())
                    .foregroundStyle(.white)
                    .padding(.top, 8)
                ForEach(order, id: \.self) { i in
                    resultPlayerReport(game, index: i)
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
        .safeAreaInset(edge: .bottom, spacing: 0) { resultActions(game) }
        .background(MatchColors.background.ignoresSafeArea())
    }

    private func resultHeroBanner(_ game: Match) -> some View {
        let winner = game.winner
        return VStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(MatchColors.amber.opacity(0.18))
                    .frame(width: 92, height: 92)
                Circle()
                    .fill(LinearGradient(colors: [MatchColors.amber, MatchColors.coral], startPoint: .top, endPoint: .bottom))
                    .frame(width: 68, height: 68)
                Image(systemName: winner == nil ? "equal" : "trophy.fill")
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(MatchColors.ink)
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
                VStack(spacing: 2) {
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
                Text(String(name.prefix(1)).uppercased())
                    .font(.headline)
                    .foregroundStyle(isWinner ? MatchColors.ink : .white)
                    .frame(width: 40, height: 40)
                    .background(isWinner ? MatchColors.amber : Color.white.opacity(0.12), in: Circle())
                    .accessibilityHidden(true)
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
        game.visits.last { $0.leg == leg && $0.checkout }?.player
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
                multiplier = 1; sumText = ""; paused = false; holdDarts = []; isHoldingVisit = false; holdPlayer = nil; legCeremony = nil; revision = UUID()
            } label: {
                Label("Odveta", systemImage: "arrow.clockwise")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glass)
            .tint(.white)

            Button { store.finish(); dismiss() } label: {
                Label("Dokončit", systemImage: "checkmark")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glassProminent)
            .tint(MatchColors.finish)
            .accessibilityHint("Uloží výsledek do historie")
        }
        .font(.headline)
        .controlSize(.large)
        .buttonBorderShape(.capsule)
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 6)
        .frame(maxWidth: 780)
        .frame(maxWidth: .infinity)
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

struct CricketTable: View {
    var game: Match
    var body: some View {
        VStack(spacing: 12) {
            HStack { Text("CÍL").frame(width: 40); ForEach(game.players.indices, id: \.self) { i in Text(game.players[i].name).lineLimit(1).frame(maxWidth: .infinity) } }.font(AppFont.caption(12, weight: .bold)).foregroundStyle(.secondary)
            ForEach([20,19,18,17,16,15,25], id: \.self) { n in
                HStack {
                    Text(n == 25 ? "B" : "\(n)").font(AppFont.body(17, weight: .semibold)).frame(width: 40)
                    ForEach(game.players.indices, id: \.self) { i in
                        let marks = game.states[i].marks[n, default: 0]
                        Text(["—", "/", "×", "⊗"][min(3, max(0, marks))]).font(AppFont.title(20)).foregroundStyle(marks == 3 ? Theme.mint : .secondary).frame(maxWidth: .infinity).accessibilityLabel("\(game.players[i].name), \(n), \(marks) zásahy")
                    }
                }
            }
            Divider()
            HStack { Text("BODY").font(AppFont.caption(11)).frame(width: 40); ForEach(game.players.indices, id: \.self) { i in Text("\(game.states[i].points)").font(AppFont.body(17, weight: .bold)).frame(maxWidth: .infinity) } }
        }.surface()
    }
}
private struct LegCeremonyView: View {
    let ceremony: LegCeremony
    let reduceMotion: Bool
    let onContinue: () -> Void

    @State private var appeared = false
    @State private var progress: CGFloat = 0

    private var winnerName: String {
        ceremony.names.indices.contains(ceremony.winner) ? ceremony.names[ceremony.winner] : "Hráč"
    }
    private var accent: Color {
        ceremony.matchFinished ? MatchColors.amber : ceremony.isCheckout ? MatchColors.green : MatchColors.coral
    }
    private var badge: (title: String, icon: String) {
        if ceremony.matchFinished { return ("Konec zápasu", "trophy.fill") }
        if ceremony.setClosed { return ("Set hotový", "square.stack.3d.up.fill") }
        if ceremony.isCheckout { return ("Leg \(ceremony.leg) · zavřeno", "checkmark.seal.fill") }
        return ("Leg \(ceremony.leg)", "flag.checkered")
    }
    private var showsCheckout: Bool { ceremony.isCheckout && ceremony.checkoutScore > 0 }

    var body: some View {
        ZStack {
            background
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
                    .font(.title3)
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
            .scaleEffect(appeared || reduceMotion ? 1 : 0.94)
            .opacity(appeared || reduceMotion ? 1 : 0)
        }
        .statusBarHidden(true)
        .persistentSystemOverlays(.hidden)
        .preferredColorScheme(.dark)
        .contentShape(Rectangle())
        .onTapGesture(perform: onContinue)
        .onAppear {
            withAnimation(reduceMotion ? nil : .spring(response: 0.45, dampingFraction: 0.82)) { appeared = true }
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
        .accessibilityHint(ceremony.matchFinished ? "Pokračuj na shrnutí" : "Pokračuj na další leg")
        .accessibilityAddTraits(.isButton)
    }

    private var background: some View {
        ZStack {
            MatchColors.background
            RadialGradient(colors: [accent.opacity(0.42), .clear], center: .top, startRadius: 0, endRadius: 560)
            RadialGradient(colors: [accent.opacity(0.12), .clear], center: .bottom, startRadius: 0, endRadius: 420)
        }
        .ignoresSafeArea()
    }

    private var winnerMark: some View {
        ZStack {
            Circle()
                .fill(accent.opacity(0.14))
                .frame(width: 128, height: 128)
            Circle()
                .strokeBorder(accent.opacity(0.35), lineWidth: 1)
                .frame(width: 128, height: 128)
            Circle()
                .fill(LinearGradient(colors: [accent, accent.opacity(0.75)], startPoint: .top, endPoint: .bottom))
                .frame(width: 92, height: 92)
            if ceremony.matchFinished {
                Image(systemName: "trophy.fill")
                    .font(.system(size: 40, weight: .semibold))
                    .foregroundStyle(MatchColors.ink)
            } else {
                Text(String(winnerName.prefix(1)).uppercased())
                    .font(.system(size: 42, weight: .bold, design: .rounded))
                    .foregroundStyle(MatchColors.ink)
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
                                Circle()
                                    .fill(n < legs ? (isWinner ? accent : Color.white.opacity(0.7)) : Color.white.opacity(0.15))
                                    .frame(width: 9, height: 9)
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
            Text(ceremony.matchFinished ? "Zobrazit shrnutí" : ceremony.setClosed ? "Další set" : "Další leg")
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
