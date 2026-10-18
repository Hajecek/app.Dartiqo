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
                VStack(alignment: .leading, spacing: 8) {
                    Text(progressTitle)
                        .font(.headline)
                    Text("Namluv skóre kola od 1 do 180 a zvláštní momenty. V zápasu si v nastavení vybereš výchozí hlas, nebo svůj. Chybějící situace dočte výchozí hlas.")
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
        "Nahráno \(recordedCount) z \(CommentaryCue.all.count)"
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
            HStack(spacing: 12) {
                Image(systemName: cue.symbol)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(recorded.contains(cue.id) ? Theme.positive : .secondary)
                    .frame(width: 28)
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
                Text(recorded.contains(cue.id) ? "Nahráno" : "Nahrát")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(recorded.contains(cue.id) ? Theme.positive : .secondary)
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
    @StateObject private var recorder = CommentaryTakeRecorder()
    var cue: CommentaryCue
    @State private var discardPrompt = false

    private var owner: UUID? { store.profile?.id }
    private var saved: Bool {
        guard let owner else { return false }
        _ = store.commentaryTick
        return store.commentary.exists(owner: owner, cue: cue)
    }

    var body: some View {
        VStack(spacing: 28) {
            VStack(spacing: 10) {
                Text(cue.title)
                    .font(.system(size: cue.title.count > 8 ? 40 : 64, weight: .heavy, design: .rounded))
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                Text(cue.detail)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.accent)
                Text(cue.prompt)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, 12)

            micButton

            Text(recorder.status)
                .font(.headline)
                .multilineTextAlignment(.center)
                .frame(minHeight: 28)

            if let error = recorder.errorMessage {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }

            if !recorder.isRecording, recorder.draftURL != nil || saved {
                HStack(spacing: 12) {
                    Button {
                        guard let owner else { return }
                        recorder.togglePlayback(savedURL: store.commentary.fileURL(owner: owner, cue: cue), hasSaved: saved)
                    } label: {
                        Label(recorder.isPlaying ? "Zastavit" : "Přehrát", systemImage: recorder.isPlaying ? "stop.fill" : "play.fill")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                    }
                    .buttonStyle(.bordered)
                    .disabled(recorder.isRecording || (recorder.draftURL == nil && !saved))

                    Button {
                        saveTake()
                    } label: {
                        Label("Uložit", systemImage: "checkmark")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .foregroundStyle(Theme.onAccent)
                            .background(Theme.accentFill, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .opacity(recorder.draftURL == nil || recorder.isRecording ? 0.4 : 1)
                    }
                    .buttonStyle(.plain)
                    .disabled(recorder.draftURL == nil || recorder.isRecording)
                }
            }

            if saved {
                Label(recorder.draftURL == nil ? "Uloženo v profilu" : "Uložená verze zůstane, dokud neuložíš novou", systemImage: "checkmark.circle.fill")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.positive)
                    .multilineTextAlignment(.center)
                Button("Smazat nahrávku", role: .destructive) {
                    guard let owner else { return }
                    recorder.stopAll()
                    store.commentary.delete(owner: owner, cue: cue)
                    store.noteCommentaryChanged()
                }
                .disabled(recorder.isRecording)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.background)
        .navigationTitle("Nahrávka")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(recorder.draftURL != nil)
        .background(PopGestureLock(locked: recorder.draftURL != nil))
        .onAppear { store.commentary.stop() }
        .toolbar {
            if recorder.draftURL != nil {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Zpět") { discardPrompt = true }
                }
            }
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

    private var micButton: some View {
        Button {
            recorder.toggleRecording()
        } label: {
            ZStack {
                Circle()
                    .fill(recorder.isRecording ? Color.red.opacity(0.18) : Theme.accentFill.opacity(0.18))
                    .frame(width: 168, height: 168)
                    .scaleEffect(recorder.isRecording ? 1 + recorder.level * 0.18 : 1)
                Circle()
                    .fill(recorder.isRecording ? Color.red : Theme.accentFill)
                    .frame(width: 112, height: 112)
                Image(systemName: recorder.isRecording ? "stop.fill" : "mic.fill")
                    .font(.system(size: 40, weight: .bold))
                    .foregroundStyle(recorder.isRecording ? Color.white : Theme.onAccent)
            }
            .animation(.easeOut(duration: 0.12), value: recorder.level)
        }
        .buttonStyle(.plain)
        .disabled(recorder.isPlaying)
        .accessibilityLabel(recorder.isRecording ? "Zastavit nahrávání" : "Nahrát")
    }

    private func saveTake() {
        guard let owner, let draft = recorder.draftURL else { return }
        do {
            try store.commentary.save(owner: owner, cue: cue, from: draft)
            recorder.discardDraft()
            store.noteCommentaryChanged()
            store.feedback()
        } catch {
            recorder.errorMessage = "Nahrávku se nepodařilo uložit. \(error.localizedDescription)"
        }
    }
}

@MainActor
final class CommentaryTakeRecorder: NSObject, ObservableObject, AVAudioPlayerDelegate {
    @Published private(set) var isRecording = false
    @Published private(set) var isPlaying = false
    @Published private(set) var level: CGFloat = 0
    @Published private(set) var draftURL: URL?
    @Published var errorMessage: String?
    @Published private(set) var takeSeconds: TimeInterval = 0

    private var recorder: AVAudioRecorder?
    private var player: AVAudioPlayer?
    private var meter: Timer?
    private var startedAt: Date?
    private var pendingURL: URL?
    private let finishProxy = RecorderFinishProxy()
    private let maxSeconds: TimeInterval = 8

    var status: String {
        if isRecording { return "Nahrávám…" }
        if isPlaying { return "Poslech" }
        if draftURL != nil {
            let seconds = takeSeconds.formatted(.number.precision(.fractionLength(1)))
            return "Nový záznam \(seconds) s. Poslechni si ho a ulož."
        }
        return "Klepni na mikrofon a namluv hlášku."
    }

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
            errorMessage = nil
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
            errorMessage = "Nahrávka je moc krátká. Zkus to znovu."
            return
        }
        draftURL = pendingURL
        self.pendingURL = nil
        takeSeconds = seconds
        errorMessage = nil
    }

    private func stopPlayback() {
        player?.stop()
        player = nil
        isPlaying = false
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            guard self.player === player else { return }
            self.player = nil
            self.isPlaying = false
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

#if DEBUG
#Preview("Komentátor") {
    NavigationStack { CommentaryLibraryView() }.dartiqoPreview()
}
#endif
