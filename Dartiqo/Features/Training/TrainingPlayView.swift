import SwiftUI
import Combine

private enum TrainingColors {
    static let background = Color(red: 0.055, green: 0.10, blue: 0.08)
    static let coral = Color(red: 1, green: 0.32, blue: 0.20)
    static let ink = Color(red: 0.045, green: 0.10, blue: 0.075)
    static let finish = Color(red: 0.05, green: 0.52, blue: 0.31)
}

/// Trénink na stejné ploše jako zápas: skóre, tři sloty, hold po kole a stejné způsoby zápisu.
struct TrainingPlayView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var definition: TrainingDefinition
    var config: TrainingConfig
    var seed: UInt64?
    var resume: TrainingSession?

    @State private var session: TrainingSession?
    @State private var saved = false
    @State private var awarded = 0
    @State private var xpBreakdown = TrainingXPBreakdown()
    @State private var showXP = false
    @State private var multiplier = 1
    @State private var surface = ScoringSurface.grid
    @State private var sumText = ""
    @State private var visitBuffer: [Dart] = []
    @State private var holdDarts: [Dart] = []
    @State private var isHoldingVisit = false
    @State private var holdSurface: ScoringSurface = .grid
    @State private var holdGeneration = 0
    @State private var confirmQuit = false
    @State private var pulse = 0
    @State private var previousBest: TrainingResult?
    @State private var entryError: String?

    private var projection: TrainingProjection {
        guard let session else { return TrainingProjection() }
        return TrainingEngine.project(session)
    }
    private var finished: Bool { projection.finished || session?.status == .completed }
    private var cameraReady: Bool {
        guard let calibration = store.boardCalibration else { return false }
        return calibration.isCalibrated && calibration.isCameraMapped
    }
    /// Šipky aktuálního / drženého kola — ne celá historie.
    private var visitDarts: [Dart] {
        isHoldingVisit ? holdDarts : visitBuffer
    }
    private var playSurfaces: [ScoringSurface] {
        var items: [ScoringSurface] = [.grid, .board, .total]
        if cameraReady { items.append(.camera) }
        return items
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                if finished {
                    resultScreen
                } else {
                Text(projection.task.isEmpty ? definition.title : projection.task)
                    .font(AppFont.caption(11, weight: .bold))
                    .foregroundStyle(.white.opacity(0.78))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .frame(maxWidth: .infinity, minHeight: 26)
                    .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                scoreboard
                if projection.phase == .memorize {
                    promptCard {
                        Text(projection.memory.joined(separator: "  ·  "))
                            .font(AppFont.display(28))
                            .foregroundStyle(TrainingColors.ink)
                            .multilineTextAlignment(.center)
                        Button("Zapamatováno") { act(.ready) }
                            .buttonStyle(.glassProminent)
                            .tint(TrainingColors.finish)
                    }
                } else {
                    if !projection.boardNumbers.isEmpty {
                        CricketMarksCard(
                            names: session?.names.isEmpty == false ? (session?.names ?? ["Hráč"]) : ["Hráč"],
                            marksByPlayer: [projection.boardMarks],
                            numbers: projection.boardNumbers,
                            active: 0
                        )
                    }
                    throwStrip
                    input
                }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, surface == .grid ? 6 : 10)
            .frame(maxWidth: 780)
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.28), value: isHoldingVisit)
            .animation(reduceMotion ? nil : .snappy(duration: 0.28), value: projection.score)
            .animation(reduceMotion ? nil : .snappy(duration: 0.28), value: projection.scoreText)
        }
        .scrollIndicators(.hidden)
        .scrollDisabled(surface == .grid && !isHoldingVisit && !finished)
        .background(TrainingColors.background)
        .safeAreaInset(edge: .bottom, spacing: 0) { bottomBar }
        .alert("Zápis", isPresented: Binding(
            get: { entryError != nil },
            set: { if !$0 { entryError = nil } }
        )) {
            Button("OK", role: .cancel) { entryError = nil }
        } message: {
            Text(entryError ?? "")
        }
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbarBackground(TrainingColors.background, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .preferredColorScheme(.dark)
        .tint(.white)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button { confirmQuit = true } label: { Image(systemName: "xmark") }
                    .accessibilityLabel("Odejít ze hry")
            }
            ToolbarItem(placement: .principal) {
                Text(definition.title).font(.headline)
            }
        }
        .alert("Přerušit trénink?", isPresented: $confirmQuit) {
            Button("Uložit a odejít") { dismiss() }
            Button("Vymazat trénink", role: .destructive) { quit() }
            Button("Zrušit", role: .cancel) {}
        } message: {
            Text("Rozehraný trénink zůstane uložený, dokud ho nesmažeš.")
        }
        .onAppear(perform: prepare)
        .onDisappear(perform: autosave)
        .onChange(of: finished) { _, done in
            if done { commitIfNeeded() }
        }
        .sheet(isPresented: $showXP) {
            TrainingXPBreakdownSheet(breakdown: xpBreakdown)
        }
        .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { date in
            guard config.timeLimit != nil || definition.id == "rush" else { return }
            guard var current = session, current.status == .playing else { return }
            TrainingEngine.sync(&current, at: date)
            session = current
            store.stageTraining(current)
            if current.status == .completed { commitIfNeeded() }
        }
        .sensoryFeedback(.impact, trigger: pulse)
    }

    private var scoreboard: some View {
        let headline = projection.target.isEmpty ? projection.scoreText : projection.target
        let numeric = Double(projection.score)
        return VStack(alignment: .leading, spacing: 2) {
            Text(definition.title)
                .font(AppFont.body(14, weight: .semibold))
                .lineLimit(1)
            Text(headline)
                .font(AppFont.display(64, weight: .bold))
                .monospacedDigit()
                .minimumScaleFactor(0.4)
                .lineLimit(1)
                .foregroundStyle(.white)
                .contentTransition(.numericText(value: numeric))
                .frame(maxWidth: .infinity, minHeight: 72, alignment: .leading)
            HStack(spacing: 8) {
                capsule(projection.scoreText)
                capsule(isHoldingVisit ? "kolo hotovo" : "šipky \(projection.dartsLeft)")
                capsule("kolo \(projection.visit)")
                if let lives = projection.lives { capsule("životy \(lives)") }
            }
        }
        .foregroundStyle(TrainingColors.ink)
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(TrainingColors.coral, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private func capsule(_ text: String) -> some View {
        Text(text)
            .font(AppFont.caption(12, weight: .bold))
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(TrainingColors.ink.opacity(0.12), in: Capsule())
            .contentTransition(.opacity)
    }

    private var throwStrip: some View {
        Group {
            if isHoldingVisit && holdSurface == .total {
                VisitHoldSummaryCard(
                    title: "Součet zapsán",
                    value: "\(holdDarts.reduce(0) { $0 + $1.score })",
                    labels: holdDarts.map(\.label)
                )
            } else {
                HStack(spacing: 8) {
                    ForEach(0..<3, id: \.self) { index in
                        let dart = visitDarts.indices.contains(index) ? visitDarts[index] : nil
                        ThrowSlotFace(index: index, dart: dart)
                    }
                }
                .frame(height: 88)
                .padding(10)
                .background(.white, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                .accessibilityElement(children: .contain)
                .accessibilityLabel(isHoldingVisit ? "Kolo hotovo" : "Aktuální hod")
            }
        }
    }

    @ViewBuilder
    private var input: some View {
        if isHoldingVisit {
            if holdSurface != .total {
                ScoringDartboard(marks: holdDarts, interactive: false)
            }
        } else {
            switch surface {
            case .board:
                ScoringDartboard(marks: visitDarts, interactive: true) { dart in _ = throwDart(dart) }
            case .camera:
                if let calibration = store.boardCalibration, cameraReady {
                    CameraScoreView(calibration: calibration, labels: visitDarts.map(\.label), dartCount: visitDarts.count) { dart, _ in
                        throwDart(dart)
                    }
                    .frame(minHeight: 420)
                }
            case .total:
                TotalScorePad(
                    sumText: $sumText,
                    showBust: false,
                    onQuick: { score in
                        sumText = "\(score)"
                        submitTotal()
                    },
                    onTap: { store.tapHaptic(.light) }
                )
            case .grid, .voice:
                ManualScorePad(multiplier: $multiplier, onSelect: { store.selectionHaptic() }) { dart in
                    _ = throwDart(dart)
                }
            }
        }
        if !projection.detail.isEmpty || projection.hint != nil || projection.ghost != nil || !projection.bogeys.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                if !projection.detail.isEmpty { Text(projection.detail) }
                if let line = projection.playerLine { Text(line).fontWeight(.bold) }
                if let ghost = projection.ghost { Text(ghost) }
                if config.showCheckouts, let hint = projection.hint, !hint.isEmpty { Text(hint).fontWeight(.semibold) }
                if !projection.bogeys.isEmpty {
                    Text("Nezavřitelné: \(projection.bogeys.map(String.init).joined(separator: ", "))")
                }
            }
            .font(AppFont.caption(13))
            .foregroundStyle(.white.opacity(0.8))
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func promptCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 14) { content() }
            .frame(maxWidth: .infinity)
            .padding(16)
            .background(.white, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private var resultScreen: some View {
        let result = session?.result ?? projection.result
        let success = result?.success == true
        let accent = success ? Theme.brand : TrainingColors.coral
        return VStack(alignment: .leading, spacing: 14) {
            VStack(spacing: 16) {
                ZStack {
                    Circle()
                        .fill(accent.opacity(0.18))
                        .frame(width: 96, height: 96)
                    Circle()
                        .fill(accent)
                        .frame(width: 68, height: 68)
                    Image(systemName: success ? "checkmark" : "xmark")
                        .font(.system(size: 30, weight: .bold))
                        .foregroundStyle(success ? Color.black : Color.white)
                }
                .accessibilityHidden(true)
                VStack(spacing: 6) {
                    Text(success ? "Splněno" : "Nesplněno")
                        .font(.largeTitle.bold())
                        .foregroundStyle(.white)
                    if let summary = result?.summary, !summary.isEmpty {
                        Text(summary)
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.72))
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                if let result {
                    recordLine(result, success: success)
                }
            }
            .padding(.vertical, 28)
            .padding(.horizontal, 20)
            .frame(maxWidth: .infinity)
            .background {
                ZStack {
                    Color.white.opacity(0.05)
                    RadialGradient(colors: [accent.opacity(0.34), .clear], center: .top, startRadius: 0, endRadius: 280)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous).strokeBorder(.white.opacity(0.08), lineWidth: 1))

            if let result {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                    ForEach(resultFacts(result), id: \.label) { fact in
                        resultChip(fact.value, fact.label)
                    }
                }
            }
            if xpBreakdown.hasAward || awarded != 0 || saved {
                resultXPBanner
            }
        }
    }

    private var resultXPBanner: some View {
        let total = xpBreakdown.hasAward ? xpBreakdown.total : awarded
        let positive = total >= 0
        return Button { showXP = true } label: {
            HStack(spacing: 14) {
                Image(systemName: positive ? "bolt.fill" : "bolt.slash.fill")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(TrainingColors.ink)
                    .frame(width: 48, height: 48)
                    .background(TrainingColors.ink.opacity(0.12), in: Circle())
                VStack(alignment: .leading, spacing: 2) {
                    Text(total > 0 ? "+\(total) XP" : total == 0 ? "0 XP" : "\(total) XP")
                        .font(.system(.title2, design: .rounded).weight(.heavy))
                        .monospacedDigit()
                        .foregroundStyle(TrainingColors.ink)
                    Text(xpBreakdown.hasAward ? "Klepni — za co přesně padlo XP" : "XP za tuhle hru už je zapsané")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(TrainingColors.ink.opacity(0.62))
                }
                Spacer(minLength: 8)
                Image(systemName: "info.circle.fill")
                    .font(.title3)
                    .foregroundStyle(TrainingColors.ink.opacity(0.55))
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.brand, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(!xpBreakdown.hasAward)
        .accessibilityLabel("\(total) XP")
        .accessibilityHint(xpBreakdown.hasAward ? "Otevře rozklad odměny" : "")
    }

    private func resultFacts(_ result: TrainingResult) -> [(value: String, label: String)] {
        var facts: [(String, String)] = [
            ("\(result.darts)", "Šipky"),
            ("\(Int((result.accuracy * 100).rounded())) %", "Přesnost"),
            ("\(result.score)", "Skóre")
        ]
        if let average = result.average {
            facts.append((String(format: "%.1f", average), "Průměr"))
        }
        if let best = result.bestVisit {
            facts.append(("\(best)", "Nejlepší kolo"))
        }
        if result.oneEighties > 0 {
            facts.append(("\(result.oneEighties)", "180"))
        }
        if result.checkoutAttempts > 0 {
            facts.append(("\(result.checkoutHits)/\(result.checkoutAttempts)", "Zavření"))
        }
        if result.busts > 0 {
            facts.append(("\(result.busts)", "Přehozy"))
        }
        if result.bestStreak > 0 {
            facts.append(("\(result.bestStreak)", "Série"))
        }
        return facts
    }

    private func resultChip(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.system(.title3, design: .rounded).weight(.bold))
                .monospacedDigit()
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(label)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.55))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func recordLine(_ result: TrainingResult, success: Bool) -> some View {
        let text: String? = {
            if let previous = previousBest {
                let better = success && (result.higherIsBetter ? result.score > previous.score : result.score < previous.score)
                return better ? "Nový rekord \(result.score)" : "Rekord zůstává \(previous.score)"
            }
            return success ? "První záznam \(result.score)" : nil
        }()
        if let text {
            Label(text, systemImage: "trophy.fill")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(.black)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Theme.brand, in: Capsule())
        }
    }

    private var bottomBar: some View {
        HStack(spacing: 10) {
            if finished {
                Button { restart() } label: {
                    Label("Znovu", systemImage: "arrow.clockwise")
                        .font(.headline)
                        .labelStyle(.titleAndIcon)
                        .foregroundStyle(.primary)
                        .frame(maxWidth: .infinity, minHeight: 52)
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .glassEffect(.regular.interactive(), in: Capsule())

                Button(action: goHome) {
                    Label("Domů", systemImage: "house.fill")
                        .font(.headline)
                        .labelStyle(.titleAndIcon)
                        .foregroundStyle(Color.black)
                        .frame(maxWidth: .infinity, minHeight: 52)
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .glassEffect(.regular.tint(Theme.brand).interactive(), in: Capsule())
                .accessibilityHint("Uloží výsledek a vrátí na Domů")
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

                if surface == .total && !isHoldingVisit {
                    Button { submitTotal() } label: {
                        Label(sumText.isEmpty ? "Potvrdit" : "Potvrdit \(sumText)", systemImage: "checkmark")
                            .font(.headline)
                            .labelStyle(.titleAndIcon)
                            .foregroundStyle(sumText.isEmpty ? Color.secondary : Color.black)
                            .frame(maxWidth: .infinity, minHeight: 52)
                            .contentShape(Capsule())
                            .contentTransition(.numericText())
                    }
                    .buttonStyle(.plain)
                    .glassEffect(
                        sumText.isEmpty ? .regular : .regular.tint(TrainingColors.finish).interactive(),
                        in: Capsule()
                    )
                    .disabled(sumText.isEmpty)
                } else {
                    Spacer(minLength: 0)
                }

                Menu {
                    ForEach(playSurfaces) { item in
                        Button {
                            changeSurface(item)
                        } label: {
                            Label(item.title, systemImage: surface == item ? "checkmark" : item.icon)
                        }
                        .disabled(item == .total && !visitBuffer.isEmpty)
                    }
                } label: {
                    Image(systemName: surface.icon)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.primary)
                        .frame(width: 52, height: 52)
                        .contentShape(Circle())
                        .glassEffect(.regular.interactive(), in: Circle())
                }
                .buttonStyle(.plain)
                .disabled(isHoldingVisit)
                .accessibilityLabel("Způsob zápisu")
                .accessibilityValue(surface.title)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 6)
        .frame(maxWidth: 780)
        .frame(maxWidth: .infinity)
    }

    private var canUndo: Bool {
        if isHoldingVisit { return true }
        return !(session?.actions.isEmpty ?? true)
    }

    private func changeSurface(_ value: ScoringSurface) {
        guard value != surface, !isHoldingVisit else { return }
        if value == .total, !visitBuffer.isEmpty {
            entryError = "Součet lze zapnout na začátku kola. Dokonči nebo vrať šipky."
            return
        }
        store.selectionHaptic()
        withAnimation(reduceMotion ? nil : .snappy(duration: 0.22)) {
            surface = value
            sumText = ""
        }
    }

    private func prepare() {
        guard session == nil, let owner = store.profile?.id else { return }
        previousBest = store.bestTrainingResult(for: definition.id)
        if let resume {
            session = resume
            if resume.status == .completed { commitIfNeeded() }
            return
        }
        let started = TrainingEngine.start(
            definition: definition,
            config: config,
            owner: owner,
            context: store.trainingContext(),
            seed: seed ?? UInt64.random(in: 1...UInt64.max),
            names: [store.profile?.name ?? "Hráč"]
        )
        session = started
        store.stageTraining(started)
    }

    @discardableResult
    private func throwDart(_ dart: Dart) -> Bool {
        guard !isHoldingVisit, var current = session, current.status == .playing else { return false }
        let beforeVisit = TrainingEngine.project(current).visit
        let beforeLeft = TrainingEngine.project(current).dartsLeft
        let beforeCount = current.actions.count
        TrainingEngine.record(.dart(dart), into: &current)
        guard current.actions.count > beforeCount else { return false }
        var buffer = visitBuffer
        buffer.append(dart)
        let after = TrainingEngine.project(current)
        withAnimation(reduceMotion ? nil : .snappy(duration: 0.28)) {
            session = current
            visitBuffer = buffer
        }
        store.stageTraining(current)
        store.feedback(dart.segment == 0 ? nil : dart.score, announce: surface != .total)
        pulse += 1
        if current.status == .completed { commitIfNeeded() }

        let closed = after.finished
            || after.visit > beforeVisit
            || buffer.count >= 3
            || (beforeLeft <= 1 && after.dartsLeft > beforeLeft)
        if closed {
            beginVisitHold(buffer, surface: surface)
        }
        return true
    }

    private func submitTotal() {
        guard !isHoldingVisit, visitBuffer.isEmpty, let score = Int(sumText) else { return }
        guard let darts = ScoringTotal.darts(for: score) else {
            entryError = "Součet \(score) nejde sestavit ze tří šipek."
            return
        }
        var recorded: [Dart] = []
        for dart in darts {
            guard throwDartQuiet(dart) else { break }
            recorded.append(dart)
            if projection.finished { break }
        }
        sumText = ""
        if !recorded.isEmpty {
            beginVisitHold(recorded, surface: .total)
        }
    }

    /// Zápis bez holdu — pro dávku součtu.
    @discardableResult
    private func throwDartQuiet(_ dart: Dart) -> Bool {
        guard var current = session, current.status == .playing else { return false }
        let beforeCount = current.actions.count
        TrainingEngine.record(.dart(dart), into: &current)
        guard current.actions.count > beforeCount else { return false }
        visitBuffer.append(dart)
        session = current
        store.stageTraining(current)
        pulse += 1
        if current.status == .completed { commitIfNeeded() }
        return true
    }

    private func beginVisitHold(_ darts: [Dart], surface hold: ScoringSurface) {
        holdGeneration += 1
        let generation = holdGeneration
        holdDarts = darts
        holdSurface = hold
        visitBuffer = []
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) { isHoldingVisit = true }
        if hold == .total {
            store.feedback(darts.reduce(0) { $0 + $1.score })
        }
        let delay = ScoringChrome.visitHoldSeconds(reduceMotion: reduceMotion)
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard generation == holdGeneration, isHoldingVisit, holdDarts == darts else { return }
            finishVisitHold()
        }
    }

    private func finishVisitHold() {
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.28)) {
            isHoldingVisit = false
            holdDarts = []
        }
        if finished { commitIfNeeded() }
    }

    private func act(_ action: TrainingAction) {
        guard !isHoldingVisit, var current = session, current.status == .playing else { return }
        let before = current.actions.count
        TrainingEngine.record(action, into: &current)
        guard current.actions.count > before else { return }
        session = current
        store.stageTraining(current)
        pulse += 1
        if current.status == .completed { commitIfNeeded() }
    }

    private func undo() {
        guard var current = session, !saved else { return }
        if isHoldingVisit {
            holdGeneration += 1
            let count = holdDarts.count
            for _ in 0..<count { TrainingEngine.undo(&current) }
            withAnimation(reduceMotion ? nil : .snappy(duration: 0.28)) {
                isHoldingVisit = false
                holdDarts = []
                visitBuffer = []
                session = current
            }
            store.stageTraining(current)
            return
        }
        guard !current.actions.isEmpty else { return }
        TrainingEngine.undo(&current)
        if !visitBuffer.isEmpty { visitBuffer.removeLast() }
        withAnimation(reduceMotion ? nil : .snappy(duration: 0.28)) {
            session = current
        }
        store.stageTraining(current)
    }

    private func restart() {
        guard var current = session else { return }
        holdGeneration += 1
        isHoldingVisit = false
        holdDarts = []
        visitBuffer = []
        sumText = ""
        if saved {
            current.id = UUID()
            current.actions = []
            current.status = .playing
            current.finishedAt = nil
            current.result = nil
            current.startedAt = Date()
            saved = false
            awarded = 0
            xpBreakdown = TrainingXPBreakdown()
        } else {
            TrainingEngine.restart(&current)
        }
        session = current
        store.stageTraining(current)
    }

    private func commitIfNeeded() {
        guard let current = session, current.status == .completed else { return }
        xpBreakdown = store.trainingXP(for: current)
        if !saved {
            awarded = store.commitTraining(current)
            saved = true
            store.feedback()
            pulse += 1
        }
        if !xpBreakdown.hasAward, awarded != 0 {
            xpBreakdown = store.trainingXP(for: current)
        }
    }

    private func autosave() {
        commitIfNeeded()
    }

    private func goHome() {
        commitIfNeeded()
        store.returnHome()
        dismiss()
    }

    private func quit() {
        guard var current = session else { dismiss(); return }
        if current.status == .playing { TrainingEngine.abandon(&current, at: Date()) }
        session = current
        store.abandonTraining(current)
        saved = true
        dismiss()
    }
}

#if DEBUG
#Preview {
    NavigationStack {
        TrainingPlayView(definition: PreviewSupport.sampleTraining, config: TrainingConfig())
    }
    .dartiqoPreview(PreviewSupport.store(activeMatch: false))
}
#endif
