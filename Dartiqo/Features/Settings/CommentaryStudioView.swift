import AVFoundation
import Combine
import SwiftUI
import UIKit

/// Seznam situací, které si hráč může namluvit.
struct CommentaryLibraryView: View {
    @EnvironmentObject private var store: AppStore
    @State private var query = ""
    @State private var filter: ClipFilter = .all
    @State private var wipe = false

    private var owner: UUID? { store.profile?.id }
    private var recorded: Set<String> {
        guard let owner else { return [] }
        _ = store.commentaryTick
        return store.commentary.recordedIDs(owner: owner)
    }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(progressTitle)
                            .font(.headline)
                        Spacer(minLength: 8)
                        Text(progressValue)
                            .font(.caption.weight(.bold).monospacedDigit())
                            .foregroundStyle(recordedCount == 0 ? .secondary : Theme.positive)
                    }
                    ProgressView(value: progressFraction)
                        .tint(recordedCount == 0 ? Color.secondary.opacity(0.35) : Theme.positive)
                    Text("Namluv skóre kola od 1 do 180 a zvláštní momenty. V zápasu si vybereš výchozí hlas, nebo svůj. Chybějící situace dočte výchozí hlas.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, 4)
                Picker("Filtr", selection: $filter) {
                    ForEach(ClipFilter.allCases) { item in
                        Text(item.title).tag(item)
                    }
                }
                .pickerStyle(.segmented)
                .listRowSeparator(.hidden)
            }

            let specials = visible(CommentaryCue.specials)
            if !specials.isEmpty {
                Section("Zvláštní momenty") {
                    ForEach(specials) { cue in
                        cueLink(cue)
                    }
                }
            }

            ForEach(CommentaryCue.scoreBands, id: \.title) { band in
                let cues = visible(band.cues)
                if !cues.isEmpty {
                    Section(band.title) {
                        ForEach(cues) { cue in
                            cueLink(cue)
                        }
                    }
                }
            }

            if visible(CommentaryCue.all).isEmpty {
                Section {
                    Text(query.isEmpty ? "V tomhle filtru nic není." : "Nic nesedí na „\(query)“.")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Vlastní komentátor")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $query, prompt: "Skóre nebo situace")
        .toolbar {
            if recordedCount > 0 {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Smazat vše", role: .destructive) { wipe = true }
                }
            }
        }
        .confirmationDialog("Smazat všechny nahrávky komentáře?", isPresented: $wipe, titleVisibility: .visible) {
            Button("Smazat nahrávky", role: .destructive) {
                guard let owner else { return }
                store.commentary.deleteAll(owner: owner)
                store.noteCommentaryChanged()
            }
            Button("Zrušit", role: .cancel) {}
        } message: {
            Text("Namluvené situace u tohoto profilu zmizí. Výchozí hlas zůstane.")
        }
    }

    private var recordedCount: Int {
        CommentaryCue.all.filter { recorded.contains($0.id) }.count
    }

    private var progressTitle: String {
        recordedCount == 0 ? "Zatím nic nenahráno" : "Nahráno \(recordedCount) z \(CommentaryCue.all.count)"
    }

    private var progressFraction: Double {
        let total = CommentaryCue.all.count
        guard total > 0 else { return 0 }
        return Double(recordedCount) / Double(total)
    }

    private var progressValue: String {
        let percent = Int((progressFraction * 100).rounded())
        return "\(percent) %"
    }

    private func visible(_ cues: [CommentaryCue]) -> [CommentaryCue] {
        cues.filter { cue in
            let ready = recorded.contains(cue.id)
            switch filter {
            case .all: break
            case .missing: if ready { return false }
            case .ready: if !ready { return false }
            }
            return matches(cue)
        }
    }

    private func matches(_ cue: CommentaryCue) -> Bool {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return true }
        if cue.title.localizedStandardContains(text) { return true }
        if cue.detail.localizedStandardContains(text) { return true }
        if case .score(let value) = cue, String(value).hasPrefix(text) { return true }
        return false
    }

    private func cueLink(_ cue: CommentaryCue) -> some View {
        NavigationLink {
            CommentaryRecordView(cue: cue)
        } label: {
            let ready = recorded.contains(cue.id)
            return HStack(spacing: 12) {
                Image(systemName: cue.symbol)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(ready ? Theme.positive : .secondary)
                    .frame(width: 36, height: 36)
                    .background(
                        (ready ? Theme.positive : Color.secondary).opacity(0.14),
                        in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                    )
                VStack(alignment: .leading, spacing: 2) {
                    Text(cue.title)
                        .font(.body.weight(.semibold))
                    if !isPlainScore(cue) {
                        Text(cue.detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 8)
                Text(ready ? "Hotovo" : "Nahrát")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(ready ? Theme.positive : .secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        (ready ? Theme.positive : Color.secondary).opacity(0.14),
                        in: Capsule()
                    )
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(cue.title), \(cue.detail), \(recorded.contains(cue.id) ? "nahráno" : "bez nahrávky")")
        }
    }

    private func isPlainScore(_ cue: CommentaryCue) -> Bool {
        if case .score = cue { return true }
        return false
    }
}

private enum ClipFilter: String, CaseIterable, Identifiable {
    case all, missing, ready
    var id: String { rawValue }
    var title: String {
        switch self {
        case .all: return "Vše"
        case .missing: return "Chybí"
        case .ready: return "Hotové"
        }
    }
}

/// Mikrofon, poslech a uložení jedné situace.
struct CommentaryRecordView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @StateObject private var recorder = CommentaryTakeRecorder()
    var cue: CommentaryCue
    @State private var discardPrompt = false
    @State private var deletePrompt = false
    @State private var savedPulse = 0

    private let recordRed = Color(red: 0.93, green: 0.27, blue: 0.24)

    private var owner: UUID? { store.profile?.id }
    private var saved: Bool {
        guard let owner else { return false }
        _ = store.commentaryTick
        return store.commentary.exists(owner: owner, cue: cue)
    }

    var body: some View {
        VStack(spacing: 14) {
            cueHeader
            stageCard
            Spacer(minLength: 4)
            recordControl
            Spacer(minLength: 4)
        }
        .padding(.horizontal, 20)
        .padding(.top, 4)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.background)
        .navigationTitle(cue.detail)
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(recorder.draftURL != nil)
        .background(PopGestureLock(locked: recorder.draftURL != nil))
        .onAppear { store.commentary.stop() }
        .toolbar {
            if recorder.draftURL != nil {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Zpět") { discardPrompt = true }
                        .disabled(recorder.isRecording)
                }
            }
            ToolbarItemGroup(placement: .topBarTrailing) {
                if canPlay {
                    Button(action: togglePlayback) {
                        Image(systemName: recorder.isPlaying ? "stop.fill" : "play.fill")
                    }
                    .accessibilityLabel(recorder.isPlaying ? "Zastavit přehrávání" : "Přehrát nahrávku")
                }
                if saved && recorder.draftURL == nil && !recorder.isRecording {
                    Label("Uloženo", systemImage: "checkmark.circle.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.positive)
                        .symbolEffect(.bounce, value: savedPulse)
                        .accessibilityLabel("Uloženo v profilu")
                }
                if saved && !recorder.isRecording && !recorder.isPlaying {
                    Button(role: .destructive) { deletePrompt = true } label: {
                        Image(systemName: "trash")
                    }
                    .accessibilityLabel("Smazat nahrávku")
                }
                if recorder.draftURL != nil && !recorder.isRecording {
                    Button("Uložit", action: saveTake)
                        .fontWeight(.bold)
                }
            }
        }
        .confirmationDialog("Smazat nahrávku?", isPresented: $deletePrompt, titleVisibility: .visible) {
            Button("Smazat", role: .destructive) { deleteTake() }
            Button("Zrušit", role: .cancel) {}
        } message: {
            Text("Tahle hláška zmizí z profilu. Výchozí hlas ji pak dočte.")
        }
        .confirmationDialog("Neuložená nahrávka", isPresented: $discardPrompt, titleVisibility: .visible) {
            Button("Uložit") {
                saveTake()
                if recorder.draftURL == nil { dismiss() }
            }
            Button("Zahodit", role: .destructive) {
                recorder.discardDraft()
                dismiss()
            }
            Button("Zůstat", role: .cancel) {}
        } message: {
            Text("Nový záznam ještě není v profilu.")
        }
        .onDisappear {
            recorder.abandon()
            store.commentary.stop()
        }
    }

    private var cueHeader: some View {
        VStack(spacing: 4) {
            Text(cue.title)
                .font(.system(size: cue.title.count > 8 ? 34 : 52, weight: .heavy, design: .rounded))
                .minimumScaleFactor(0.6)
                .lineLimit(1)
            Text(cue.prompt)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
    }

    private var stageCard: some View {
        VStack(spacing: 8) {
            TakeWaveform(
                samples: waveformSamples,
                progress: waveformProgress,
                tint: recorder.isRecording ? recordRed : Theme.accent
            )
            .frame(height: 40)

            Text(clockText)
                .font(.system(size: 28, weight: .bold, design: .rounded).monospacedDigit())
                .contentTransition(.numericText())
                .animation(reduceMotion ? nil : .snappy(duration: 0.2), value: clockText)

            Text(phaseDetail)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(recorder.errorMessage == nil ? .secondary : recordRed)
                .multilineTextAlignment(.center)
                .lineLimit(2)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(stageStroke, lineWidth: recorder.isRecording || recorder.isPlaying ? 1.5 : 1)
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: recorder.isRecording)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: recorder.isPlaying)
    }

    private var stageStroke: Color {
        if recorder.isRecording { return recordRed.opacity(0.7) }
        if recorder.isPlaying { return Theme.accent.opacity(0.7) }
        if recorder.draftURL != nil { return Theme.accent.opacity(0.35) }
        return Theme.stroke
    }

    private var recordControl: some View {
        VStack(spacing: 8) {
            micButton
            Text(micCaption)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(recorder.isRecording ? recordRed : .secondary)
        }
    }

    private var canPlay: Bool {
        !recorder.isRecording && (recorder.draftURL != nil || saved)
    }

    private var micButton: some View {
        let recording = recorder.isRecording
        let ringProgress = recording ? min(1, recorder.elapsed / recorder.maxSeconds) : (recorder.draftURL == nil ? 0 : 1)
        return Button {
            store.tapHaptic(recording ? .medium : .soft)
            recorder.toggleRecording()
        } label: {
            ZStack {
                Circle()
                    .stroke(Color.primary.opacity(0.08), lineWidth: 7)
                    .frame(width: 136, height: 136)
                Circle()
                    .trim(from: 0, to: ringProgress)
                    .stroke(
                        recording ? recordRed : Theme.accentFill,
                        style: StrokeStyle(lineWidth: 7, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .frame(width: 136, height: 136)
                if recording && !reduceMotion {
                    Circle()
                        .stroke(recordRed.opacity(0.28), lineWidth: 2)
                        .frame(width: 108 + recorder.level * 16, height: 108 + recorder.level * 16)
                }
                Circle()
                    .fill(recording ? recordRed : Theme.accentFill)
                    .frame(width: 88, height: 88)
                    .shadow(color: (recording ? recordRed : Theme.accentFill).opacity(0.38), radius: 12, y: 4)
                Image(systemName: recording ? "stop.fill" : "mic.fill")
                    .font(.system(size: 30, weight: .bold))
                    .foregroundStyle(recording ? Color.white : Theme.onAccent)
                    .symbolEffect(.pulse, options: .repeating, isActive: recording && !reduceMotion)
            }
            .opacity(recorder.isPlaying ? 0.38 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: recorder.level)
            .animation(reduceMotion ? nil : .linear(duration: 0.08), value: ringProgress)
        }
        .buttonStyle(.plain)
        .disabled(recorder.isPlaying)
        .accessibilityLabel(recording ? "Zastavit nahrávání" : "Nahrát")
        .accessibilityValue(clockText)
    }

    private var micCaption: String {
        if recorder.isPlaying { return "Nejdřív zastav poslech" }
        if recorder.isRecording { return "Zastavit" }
        if recorder.draftURL != nil { return "Nahrát znovu" }
        return "Klepni a namluv"
    }

    private var phaseDetail: String {
        if let error = recorder.errorMessage { return error }
        if recorder.isRecording { return "Nahrávám" }
        if recorder.isPlaying { return "Přehrávám" }
        if recorder.draftURL != nil, saved { return "Nový záznam. Původní zůstane, dokud ho neuložíš." }
        if recorder.draftURL != nil { return "Nový záznam. Přehrej ho a ulož." }
        if saved { return "Uložená hláška" }
        return "Připraveno · nejvýš 8 sekund"
    }

    private var clockText: String {
        let seconds: TimeInterval
        if recorder.isPlaying {
            seconds = recorder.playbackTime
        } else if recorder.isRecording {
            seconds = recorder.elapsed
        } else if recorder.draftURL != nil {
            seconds = recorder.takeSeconds
        } else {
            seconds = 0
        }
        let shown = seconds.formatted(.number.precision(.fractionLength(1)))
        if recorder.isRecording {
            let cap = recorder.maxSeconds.formatted(.number.precision(.fractionLength(0)))
            return "\(shown) / \(cap) s"
        }
        return "\(shown) s"
    }

    private var waveformSamples: [CGFloat] {
        if recorder.samples.count == CommentaryTakeRecorder.waveformBars {
            return recorder.samples
        }
        let count = CommentaryTakeRecorder.waveformBars
        let seed = cue.id.unicodeScalars.reduce(0) { $0 &+ Int($1.value) }
        return (0..<count).map { index in
            let envelope = sin(Double(index) / Double(count - 1) * .pi)
            let wobble = abs(sin(Double(index) * 0.62 + Double(seed % 9)))
            return CGFloat(0.16 + 0.42 * envelope * (0.45 + 0.55 * wobble))
        }
    }

    /// `-2` je klidový náhled, `-1` celý záznam bez přehrávací hlavy, `0…1` je poslech.
    private var waveformProgress: CGFloat {
        if recorder.isPlaying { return recorder.playbackProgress }
        if recorder.isRecording || recorder.draftURL != nil { return -1 }
        return -2
    }

    private func togglePlayback() {
        guard let owner else { return }
        store.selectionHaptic()
        recorder.togglePlayback(savedURL: store.commentary.fileURL(owner: owner, cue: cue), hasSaved: saved)
    }

    private func saveTake() {
        guard let owner, let draft = recorder.draftURL else { return }
        do {
            try store.commentary.save(owner: owner, cue: cue, from: draft)
            recorder.discardDraft()
            store.noteCommentaryChanged()
            savedPulse += 1
            store.feedback(announce: false)
        } catch {
            recorder.errorMessage = "Nahrávku se nepodařilo uložit. \(error.localizedDescription)"
        }
    }

    private func deleteTake() {
        guard let owner else { return }
        recorder.stopAll()
        store.commentary.delete(owner: owner, cue: cue)
        store.noteCommentaryChanged()
        store.tapHaptic(.medium)
    }
}

@MainActor
final class CommentaryTakeRecorder: NSObject, ObservableObject, AVAudioPlayerDelegate {
    static let waveformBars = 32

    @Published private(set) var isRecording = false
    @Published private(set) var isPlaying = false
    @Published private(set) var level: CGFloat = 0
    @Published private(set) var draftURL: URL?
    @Published var errorMessage: String?
    @Published private(set) var takeSeconds: TimeInterval = 0
    @Published private(set) var elapsed: TimeInterval = 0
    @Published private(set) var samples: [CGFloat] = []
    @Published private(set) var playbackTime: TimeInterval = 0
    @Published private(set) var playbackProgress: CGFloat = 0

    private var recorder: AVAudioRecorder?
    private var player: AVAudioPlayer?
    private var meter: Timer?
    private var playbackMeter: Timer?
    private var startedAt: Date?
    private var pendingURL: URL?
    private let finishProxy = RecorderFinishProxy()
    let maxSeconds: TimeInterval = 8

    func toggleRecording() {
        if isRecording {
            stopRecording()
        } else {
            Task { await startRecording() }
        }
    }

    func togglePlayback(savedURL: URL, hasSaved: Bool) {
        if isPlaying {
            stopPlayback()
            return
        }
        guard !isRecording else { return }
        let url = draftURL ?? (hasSaved ? savedURL : nil)
        guard let url, FileManager.default.fileExists(atPath: url.path) else { return }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
            try session.setActive(true)
            let next = try AVAudioPlayer(contentsOf: url)
            next.delegate = self
            next.prepareToPlay()
            next.play()
            player = next
            isPlaying = true
            playbackTime = 0
            playbackProgress = 0
            errorMessage = nil
            startPlaybackMeter()
        } catch {
            errorMessage = "Poslech se nepodařil. \(error.localizedDescription)"
        }
    }

    func stopAll() {
        stopRecording()
        stopPlayback()
    }

    /// Odchod z obrazovky. Rozpracovaný i neuložený záznam se smaže.
    func abandon() {
        isRecording = false
        meter?.invalidate()
        meter = nil
        level = 0
        recorder?.stop()
        recorder = nil
        stopPlayback()
        if let pendingURL {
            try? FileManager.default.removeItem(at: pendingURL)
        }
        pendingURL = nil
        discardDraft()
        try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
    }

    func discardDraft() {
        if let draftURL {
            try? FileManager.default.removeItem(at: draftURL)
        }
        draftURL = nil
        takeSeconds = 0
        elapsed = 0
        samples = []
    }

    private func startRecording() async {
        stopPlayback()
        errorMessage = nil
        let allowed = await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { ok in
                continuation.resume(returning: ok)
            }
        }
        guard allowed else {
            errorMessage = "Povol mikrofon v Nastavení, ať jde hláška nahrát."
            return
        }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .spokenAudio, options: [.defaultToSpeaker])
            try session.setActive(true)
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("dartiqo-take-\(UUID().uuidString).m4a")
            let settings: [String: Any] = [
                AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
                AVSampleRateKey: 44_100,
                AVNumberOfChannelsKey: 1,
                AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
            ]
            let next = try AVAudioRecorder(url: url, settings: settings)
            next.isMeteringEnabled = true
            next.delegate = finishProxy
            finishProxy.onFinish = { [weak self] in
                Task { @MainActor in self?.finishFromDelegate() }
            }
            guard next.record(forDuration: maxSeconds) else {
                errorMessage = "Mikrofon se nepodařilo spustit."
                return
            }
            discardDraft()
            recorder = next
            pendingURL = url
            startedAt = Date()
            isRecording = true
            level = 0
            elapsed = 0
            samples = Array(repeating: 0.1, count: Self.waveformBars)
            meter?.invalidate()
            let timer = Timer(timeInterval: 0.06, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.sampleLevel() }
            }
            RunLoop.main.add(timer, forMode: .common)
            meter = timer
        } catch {
            errorMessage = "Mikrofon se nepodařilo spustit. \(error.localizedDescription)"
        }
    }

    private func sampleLevel() {
        guard let recorder, isRecording else { return }
        recorder.updateMeters()
        let power = recorder.averagePower(forChannel: 0)
        let normalized = max(0, min(1, (power + 50) / 50))
        level = CGFloat(normalized)
        let seconds = Date().timeIntervalSince(startedAt ?? Date())
        elapsed = seconds
        var next = samples
        if next.count != Self.waveformBars {
            next = Array(repeating: 0.1, count: Self.waveformBars)
        }
        let index = min(Self.waveformBars - 1, Int((seconds / maxSeconds) * Double(Self.waveformBars)))
        next[index] = max(next[index], CGFloat(max(0.14, normalized)))
        samples = next
    }

    private func startPlaybackMeter() {
        playbackMeter?.invalidate()
        let timer = Timer(timeInterval: 0.05, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.samplePlayback() }
        }
        RunLoop.main.add(timer, forMode: .common)
        playbackMeter = timer
    }

    private func samplePlayback() {
        guard let player, isPlaying else { return }
        let duration = max(player.duration, 0.05)
        playbackTime = player.currentTime
        playbackProgress = CGFloat(min(1, player.currentTime / duration))
    }

    private func stopRecording() {
        guard isRecording else { return }
        let seconds = Date().timeIntervalSince(startedAt ?? Date())
        isRecording = false
        meter?.invalidate()
        meter = nil
        recorder?.stop()
        recorder = nil
        level = 0
        keepTake(seconds: seconds)
    }

    private func finishFromDelegate() {
        guard isRecording else { return }
        let seconds = Date().timeIntervalSince(startedAt ?? Date())
        isRecording = false
        meter?.invalidate()
        meter = nil
        recorder = nil
        level = 0
        keepTake(seconds: seconds)
    }

    private func keepTake(seconds: TimeInterval) {
        guard seconds > 0.2, let pendingURL else {
            if let pendingURL { try? FileManager.default.removeItem(at: pendingURL) }
            self.pendingURL = nil
            samples = []
            elapsed = 0
            errorMessage = "Nahrávka je moc krátká. Zkus to znovu."
            return
        }
        draftURL = pendingURL
        self.pendingURL = nil
        takeSeconds = seconds
        errorMessage = nil
    }

    private func stopPlayback() {
        playbackMeter?.invalidate()
        playbackMeter = nil
        player?.stop()
        player = nil
        isPlaying = false
        playbackTime = 0
        playbackProgress = 0
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            guard self.player === player else { return }
            self.stopPlayback()
        }
    }
}

/// AVAudioRecorder drží delegate slabě. Samostatný objekt přežije konec nahrávky.
private final class RecorderFinishProxy: NSObject, AVAudioRecorderDelegate {
    var onFinish: (() -> Void)?
    func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        onFinish?()
    }
}

/// Při neuloženém záznamu nejde z obrazovky odjet gestem, ať nahrávka nezmizí potichu.
private struct PopGestureLock: UIViewControllerRepresentable {
    var locked: Bool

    func makeUIViewController(context: Context) -> Controller { Controller() }

    func updateUIViewController(_ controller: Controller, context: Context) {
        controller.locked = locked
        controller.apply()
    }

    final class Controller: UIViewController {
        var locked = false
        override func didMove(toParent parent: UIViewController?) {
            super.didMove(toParent: parent)
            apply()
        }
        override func viewWillDisappear(_ animated: Bool) {
            super.viewWillDisappear(animated)
            navigationController?.interactivePopGestureRecognizer?.isEnabled = true
        }
        func apply() {
            navigationController?.interactivePopGestureRecognizer?.isEnabled = !locked
        }
    }
}

/// Sloupce hlasitosti. `-2` je klidový náhled, `-1` je celý záznam, `0…1` je poslech.
private struct TakeWaveform: View {
    var samples: [CGFloat]
    var progress: CGFloat
    var tint: Color

    var body: some View {
        HStack(alignment: .center, spacing: 3) {
            ForEach(samples.indices, id: \.self) { index in
                let amount = min(1, max(0.08, samples[index]))
                Capsule(style: .continuous)
                    .fill(barColor(index))
                    .frame(maxWidth: .infinity)
                    .frame(height: 8 + amount * 48)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .animation(.easeOut(duration: 0.08), value: samples)
    }

    private func barColor(_ index: Int) -> Color {
        if progress < -1 { return tint.opacity(0.38) }
        if progress < 0 { return tint }
        let head = CGFloat(index) / CGFloat(max(samples.count - 1, 1))
        return head <= progress + 0.001 ? tint : tint.opacity(0.22)
    }
}

/// Jedna volba komentátora jako běžná řádka nastavení. Vybraná má fajfku.
struct CommentatorOptionRow: View {
    @EnvironmentObject private var store: AppStore
    var item: Commentator

    private var selected: Bool { store.commentator == item }

    var body: some View {
        Button {
            guard !selected else { return }
            store.commentator = item
            store.selectionHaptic()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: symbol)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(selected ? Theme.onAccent : .secondary)
                    .frame(width: 32, height: 32)
                    .background(
                        selected ? Theme.accentFill : Color.primary.opacity(0.08),
                        in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                    )
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                if selected {
                    Image(systemName: "checkmark")
                        .font(.body.weight(.bold))
                        .foregroundStyle(Theme.accent)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityLabel("\(item.title), \(detail)")
    }

    private var symbol: String {
        switch item {
        case .system: return "speaker.wave.2.fill"
        case .custom: return "person.wave.2.fill"
        }
    }

    private var detail: String {
        switch item {
        case .system:
            return "Systém přečte skóre kola"
        case .custom:
            let count = store.commentaryCount
            if count == 0 { return "Nahraj si vlastní hlášky" }
            return CommentaryCopy.countPhrase(count)
        }
    }
}

/// Odkaz do studia nahrávek, s postupem kolik situací už je namluvených.
struct CommentaryStudioLink: View {
    @EnvironmentObject private var store: AppStore

    private var total: Int { CommentaryCue.all.count }
    private var count: Int { store.commentaryCount }
    private var fraction: Double {
        guard total > 0 else { return 0 }
        return Double(count) / Double(total)
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "waveform.and.mic")
                .font(.body.weight(.bold))
                .foregroundStyle(Theme.onAccent)
                .frame(width: 40, height: 40)
                .background(Theme.accentFill, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            VStack(alignment: .leading, spacing: 6) {
                Text("Vlastní komentátor")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.primary)
                Text(count == 0 ? "Namluv si hlášky" : "\(CommentaryCopy.countPhrase(count)) z \(total)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ProgressView(value: fraction)
                    .tint(count == 0 ? Color.secondary.opacity(0.35) : Theme.positive)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(count == 0 ? "Vlastní komentátor, zatím bez nahrávek" : "Vlastní komentátor, \(CommentaryCopy.countPhrase(count)) z \(total)")
    }
}

enum CommentaryCopy {
    static func countPhrase(_ count: Int) -> String {
        let mod = count % 100
        if count == 1 { return "1 nahrávka" }
        if (2...4).contains(count % 10), !(12...14).contains(mod) { return "\(count) nahrávky" }
        return "\(count) nahrávek"
    }
}

#if DEBUG
#Preview("Komentátor") {
    NavigationStack { CommentaryLibraryView() }.dartiqoPreview()
}
#Preview("Nahrávka") {
    NavigationStack { CommentaryRecordView(cue: .celebration180) }.dartiqoPreview()
}
#endif
