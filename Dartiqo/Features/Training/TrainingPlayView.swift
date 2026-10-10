import SwiftUI
import Combine

private enum TrainingColors {
    static let background = Color(red: 0.055, green: 0.10, blue: 0.08)
    static let coral = Color(red: 1, green: 0.32, blue: 0.20)
    static let ink = Color(red: 0.045, green: 0.10, blue: 0.075)
    static let finish = Color(red: 0.05, green: 0.52, blue: 0.31)
}

private enum TrainingSurface: String, CaseIterable, Identifiable {
    case grid, board, camera
    var id: String { rawValue }
    var title: String {
        switch self {
        case .grid: return "Čísla"
        case .board: return "Terč"
        case .camera: return "Kamera"
        }
    }
    var icon: String {
        switch self {
        case .grid: return "square.grid.3x3.fill"
        case .board: return "target"
        case .camera: return "camera.fill"
        }
    }
}

/// Trénink na stejné ploše jako zápas: skóre, tři sloty a mřížka čísel.
struct TrainingPlayView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    var definition: TrainingDefinition
    var config: TrainingConfig
    var seed: UInt64?
    var resume: TrainingSession?

    @State private var session: TrainingSession?
    @State private var saved = false
    @State private var awarded = 0
    @State private var multiplier = 1
    @State private var surface = TrainingSurface.grid
    @State private var confirmQuit = false
    @State private var pulse = 0
    @State private var previousBest: TrainingResult?

    private var projection: TrainingProjection {
        guard let session else { return TrainingProjection() }
        return TrainingEngine.project(session)
    }
    private var finished: Bool { projection.finished || session?.status == .completed }
    private var cameraReady: Bool {
        guard let calibration = store.boardCalibration else { return false }
        return calibration.isCalibrated && calibration.isCameraMapped
    }
    private var visitDarts: [Dart] {
        let recent = projection.recent
        let count = min(3, recent.count)
        return Array(recent.suffix(count))
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                Text(projection.task.isEmpty ? definition.title : projection.task)
                    .font(AppFont.caption(11, weight: .bold))
                    .foregroundStyle(.white.opacity(0.78))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .frame(maxWidth: .infinity, minHeight: 26)
                    .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                scoreboard
                if finished {
                    resultCard
                } else if projection.phase == .memorize {
                    promptCard {
                        Text(projection.memory.joined(separator: "  ·  "))
                            .font(AppFont.display(28))
                            .foregroundStyle(TrainingColors.ink)
                            .multilineTextAlignment(.center)
                        Button("Zapamatováno") { act(.ready) }
                            .buttonStyle(.glassProminent)
                            .tint(TrainingColors.finish)
                    }
                } else if projection.phase == .choose {
                    promptCard {
                        ForEach(Array(projection.choices.enumerated()), id: \.offset) { item in
                            Button(item.element) { act(.choose(item.offset)) }
                                .buttonStyle(.glassProminent)
                                .tint(TrainingColors.finish)
                        }
                    }
                } else {
                    throwStrip
                    input
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .frame(maxWidth: 780)
        }
        .scrollIndicators(.hidden)
        .background(TrainingColors.background)
        .safeAreaInset(edge: .bottom, spacing: 0) { bottomBar }
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
        .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { date in
            guard config.timeLimit != nil || definition.id == "rush" else { return }
            guard var current = session, current.status == .playing else { return }
            TrainingEngine.sync(&current, at: date)
            session = current
            if current.status == .completed { store.stageTraining(current) }
        }
        .sensoryFeedback(.impact, trigger: pulse)
    }

    private var scoreboard: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(definition.title)
                .font(AppFont.body(14, weight: .semibold))
                .lineLimit(1)
            Text(projection.target.isEmpty ? projection.scoreText : projection.target)
                .font(AppFont.display(64, weight: .bold))
                .monospacedDigit()
                .minimumScaleFactor(0.4)
                .lineLimit(1)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, minHeight: 72, alignment: .leading)
            HStack(spacing: 8) {
                capsule("\(projection.scoreText)")
                capsule("šipky \(projection.dartsLeft)")
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
    }

    private var throwStrip: some View {
        HStack(spacing: 8) {
            ForEach(0..<3, id: \.self) { index in
                let dart = visitDarts.indices.contains(index) ? visitDarts[index] : nil
                VStack(spacing: 4) {
                    Text("\(index + 1)")
                        .font(AppFont.caption(10, weight: .bold))
                        .foregroundStyle(TrainingColors.ink.opacity(0.4))
                    Text(dart.map { "\($0.score)" } ?? "—")
                        .font(AppFont.display(26, weight: .bold))
                        .monospacedDigit()
                        .foregroundStyle(dart == nil ? TrainingColors.ink.opacity(0.22) : TrainingColors.ink)
                    Text(dart?.label ?? "\(index + 1). šipka")
                        .font(AppFont.caption(12, weight: .bold))
                        .foregroundStyle(TrainingColors.ink.opacity(dart == nil ? 0.4 : 0.65))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                .frame(maxWidth: .infinity, minHeight: 78)
                .background(TrainingColors.ink.opacity(dart == nil ? 0.04 : 0.06), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
        }
        .padding(10)
        .background(.white, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    @ViewBuilder
    private var input: some View {
        switch surface {
        case .board:
            TouchDartboard { dart in _ = throwDart(dart) }
                .frame(maxWidth: 420)
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        case .camera:
            if let calibration = store.boardCalibration, cameraReady {
                CameraScoreView(calibration: calibration, labels: visitDarts.map(\.label), dartCount: session?.actions.count ?? 0) { dart, _ in
                    throwDart(dart)
                }
                .frame(minHeight: 420)
            }
        case .grid:
            dartGrid
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

    private var dartGrid: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                ForEach(1...3, id: \.self) { value in
                    Button { multiplier = value } label: {
                        Text(["Single", "Double", "Triple"][value - 1])
                            .font(AppFont.caption(12, weight: .semibold))
                            .frame(maxWidth: .infinity, minHeight: 47)
                            .overlay(alignment: .bottom) {
                                Rectangle().fill(multiplier == value ? TrainingColors.coral : .clear).frame(height: 3)
                            }
                    }
                    .accessibilityAddTraits(multiplier == value ? .isSelected : [])
                }
                Button { _ = throwDart(Dart(25, 2)) } label: {
                    VStack(spacing: 2) { Text("Bull").font(AppFont.caption(12, weight: .bold)); Text("50").font(AppFont.caption(12)) }
                        .frame(maxWidth: .infinity, minHeight: 47)
                }
                Button { _ = throwDart(Dart(25)) } label: {
                    VStack(spacing: 2) { Text("Outer").font(AppFont.caption(12, weight: .bold)); Text("25").font(AppFont.caption(12)) }
                        .frame(maxWidth: .infinity, minHeight: 47)
                }
                Button { _ = throwDart(.miss) } label: {
                    VStack(spacing: 2) { Text("Mimo").font(AppFont.caption(12, weight: .bold)); Text("0").font(AppFont.caption(12)) }
                        .frame(maxWidth: .infinity, minHeight: 47)
                }
                .accessibilityLabel("Mimo terč, 0 bodů")
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 1), count: 5), spacing: 1) {
                ForEach(1...20, id: \.self) { number in
                    Button { _ = throwDart(Dart(number, multiplier)) } label: {
                        Text("\(number)")
                            .font(AppFont.display(26, weight: .bold))
                            .frame(maxWidth: .infinity, minHeight: 46)
                            .background(TrainingColors.background)
                    }
                    .accessibilityLabel("\(multiplier == 3 ? "Triple" : multiplier == 2 ? "Double" : "Single") \(number)")
                }
            }
            .padding(.vertical, 1)
            .background(.white.opacity(0.13))
        }
        .foregroundStyle(.white)
    }

    private func promptCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 14) { content() }
            .frame(maxWidth: .infinity)
            .padding(16)
            .background(.white, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private var resultCard: some View {
        let result = session?.result ?? projection.result
        return VStack(alignment: .leading, spacing: 10) {
            Text(result?.success == true ? "Splněno" : "Nesplněno")
                .font(AppFont.title())
                .foregroundStyle(TrainingColors.ink)
            Text(result?.summary ?? "")
                .font(AppFont.body(15))
                .foregroundStyle(TrainingColors.ink.opacity(0.75))
            if let result {
                Text("Šipky \(result.darts) · přesnost \(Int((result.accuracy * 100).rounded())) %")
                    .foregroundStyle(TrainingColors.ink)
                if let average = result.average {
                    Text(String(format: "Průměr %.1f", average)).foregroundStyle(TrainingColors.ink)
                }
                recordLine(result)
            }
            if saved {
                Text(awarded > 0 ? "+\(awarded) XP" : "XP za tuhle hru už je zapsané.")
                    .font(AppFont.body(16, weight: .bold))
                    .foregroundStyle(TrainingColors.ink)
            } else {
                Button("Uložit výsledek") { save() }
                    .buttonStyle(.glassProminent)
                    .tint(TrainingColors.finish)
            }
            Button("Hrát znovu") { restart() }
                .buttonStyle(.glass)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(.white, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    @ViewBuilder
    private func recordLine(_ result: TrainingResult) -> some View {
        if let previous = previousBest {
            let better = result.success && (result.higherIsBetter ? result.score > previous.score : result.score < previous.score)
            Text(better ? "Nový rekord \(result.score)" : "Rekord zůstává \(previous.score)")
                .foregroundStyle(TrainingColors.ink)
        } else if result.success {
            Text("První záznam \(result.score)").foregroundStyle(TrainingColors.ink)
        }
    }

    private var bottomBar: some View {
        HStack(spacing: 10) {
            Button { undo() } label: { Label("Zpět", systemImage: "arrow.uturn.backward") }
                .buttonStyle(.glass)
                .disabled(saved || (session?.actions.isEmpty ?? true))
            Spacer(minLength: 0)
            if !finished {
                Menu {
                    Picker("Způsob zápisu", selection: $surface) {
                        ForEach(TrainingSurface.allCases) { item in
                            if item != .camera || cameraReady {
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

    private func prepare() {
        guard session == nil, let owner = store.profile?.id else { return }
        previousBest = store.bestTrainingResult(for: definition.id)
        if let resume {
            session = resume
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
        guard var current = session, current.status == .playing else { return false }
        let before = current.actions.count
        TrainingEngine.record(.dart(dart), into: &current)
        guard current.actions.count > before else { return false }
        session = current
        store.stageTraining(current)
        store.feedback(dart.segment == 0 ? nil : dart.score)
        pulse += 1
        return true
    }

    private func act(_ action: TrainingAction) {
        guard var current = session, current.status == .playing else { return }
        let before = current.actions.count
        TrainingEngine.record(action, into: &current)
        guard current.actions.count > before else { return }
        session = current
        store.stageTraining(current)
        pulse += 1
    }

    private func undo() {
        guard var current = session, !saved else { return }
        TrainingEngine.undo(&current)
        session = current
        store.stageTraining(current)
    }

    private func restart() {
        guard var current = session else { return }
        if saved {
            current.id = UUID()
            current.actions = []
            current.status = .playing
            current.finishedAt = nil
            current.result = nil
            current.startedAt = Date()
            saved = false
            awarded = 0
        } else {
            TrainingEngine.restart(&current)
        }
        session = current
        store.stageTraining(current)
    }

    private func save() {
        guard let current = session, !saved else { return }
        awarded = store.commitTraining(current)
        saved = true
        store.feedback()
        pulse += 1
    }

    private func autosave() {
        guard let current = session, current.status == .completed, !saved else { return }
        awarded = store.commitTraining(current)
        saved = true
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
