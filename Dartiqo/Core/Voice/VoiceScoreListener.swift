import AVFoundation
import Combine
import Foundation
import Speech

/// Kontinuální hlasový zápis: AVAudioRecorder + SFSpeech (síť / systém, ne vynucené on-device).
@MainActor
final class VoiceScoreListener: ObservableObject {
    enum Phase: Equatable {
        case idle
        case askingPermission
        case preparing
        case listening
        case recognizing
        case unavailable(String)
    }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var transcript = ""
    @Published private(set) var lastError: String?
    @Published private(set) var lastHeard = ""
    /// 0…1 pro vizualizaci mikrofonu.
    @Published private(set) var inputLevel: CGFloat = 0
    @Published private(set) var lastCommandLabel: String?

    private var recognizer: SFSpeechRecognizer?
    private var recorder: AVAudioRecorder?
    private var meterTimer: Timer?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var mode: VoiceScoreMode = .darts
    private var onCommand: ((VoiceScoreCommand) -> Void)?
    private var startGeneration = 0
    private var recordingURL: URL?
    private var heardSpeech = false
    private var silenceTicks = 0
    private var recordingStartedAt: Date?
    private var finishContinuation: CheckedContinuation<URL, Error>?
    private var recorderDelegate: RecorderFinishProxy?
    private var consecutiveFailures = 0
    private var sessionReady = false

    /// ~0,55 s ticha po řeči → commit (rychlejší reakce).
    private let silenceNeeded = 6
    private let maxSeconds: TimeInterval = 3.4
    private let speechThreshold: Float = -34
    private let silenceThreshold: Float = -48

    var isListening: Bool {
        switch phase {
        case .listening, .recognizing, .preparing, .askingPermission: return true
        default: return false
        }
    }

    func start(mode: VoiceScoreMode, onCommand: @escaping (VoiceScoreCommand) -> Void) {
        self.mode = mode
        self.onCommand = onCommand
        lastError = nil
        transcript = ""
        lastHeard = ""
        lastCommandLabel = nil
        inputLevel = 0
        consecutiveFailures = 0
        startGeneration += 1
        let generation = startGeneration

#if targetEnvironment(simulator)
        // SFSpeech / localspeechrecognition na simulátoru padá na 1101 — není podporované.
        phase = .unavailable("Hlasový zápis funguje jen na iPhonu. Simulátor mikrofon a češtinu pro řeč nepodporuje.")
        lastError = nil
        return
#endif

        let locale = Self.bestCzechLocale()
        let recognizer = SFSpeechRecognizer(locale: locale)
        self.recognizer = recognizer

        guard let recognizer, recognizer.isAvailable else {
            phase = .unavailable("Rozpoznávání češtiny teď není dostupná. Zkontroluj Siri a jazyk v Nastavení → Obecné → Klávesnice / Siri.")
            return
        }

        phase = .askingPermission
        Task { @MainActor in
            let speechOK = await requestSpeechAuth()
            let micOK = await requestMicAuth()
            guard generation == startGeneration else { return }
            guard speechOK else {
                phase = .unavailable("Povol rozpoznávání řeči v Nastavení.")
                return
            }
            guard micOK else {
                phase = .unavailable("Povol mikrofon v Nastavení.")
                return
            }
            phase = .preparing
            do {
                try await prepareSession()
                guard generation == startGeneration else { return }
                try beginRecording(generation: generation)
                phase = .listening
                transcript = "Poslouchám…"
            } catch {
                guard generation == startGeneration else { return }
                await tearDown(deactivate: true, expectedGeneration: generation)
                guard generation == startGeneration else { return }
                phase = .unavailable(friendlyError(error))
            }
        }
    }

    func stop() {
        startGeneration += 1
        let generation = startGeneration
        let ownedSession = sessionReady
        // Synchronní cleanup — ať asynchronní tearDown z předchozího cyklu nesahá na nový recorder.
        invalidateCapture()
        phase = .idle
        transcript = ""
        inputLevel = 0
        // Bez nahrávání nesahej na audio. Deaktivace by usekla hlasové skóre při předání tahu.
        guard ownedSession else { return }
        Task {
            guard generation == startGeneration else { return }
            await deactivateSession()
        }
    }

    func updateMode(_ value: VoiceScoreMode) {
        mode = value
    }

    // MARK: - Locale / auth

    private static func bestCzechLocale() -> Locale {
        let supported = SFSpeechRecognizer.supportedLocales()
        if let exact = supported.first(where: { $0.identifier == "cs-CZ" || $0.identifier == "cs_CZ" }) {
            return exact
        }
        if let any = supported.first(where: { $0.identifier.hasPrefix("cs") }) {
            return any
        }
        return Locale(identifier: "cs-CZ")
    }

    private func requestSpeechAuth() async -> Bool {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
    }

    private func requestMicAuth() async -> Bool {
        await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { ok in
                continuation.resume(returning: ok)
            }
        }
    }

    private func prepareSession() async throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(
            .playAndRecord,
            mode: .spokenAudio,
            options: [.defaultToSpeaker, .duckOthers, .allowBluetoothHFP, .mixWithOthers]
        )
        try? session.setPreferredSampleRate(16_000)
        try? session.setPreferredIOBufferDuration(0.01)
        if !sessionReady {
            try await activateSession(session)
            sessionReady = true
        }
    }

    private func activateSession(_ session: AVAudioSession) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            session.activate(options: []) { activated, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if activated {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: VoiceListenError.activationFailed)
                }
            }
        }
    }

    private func deactivateSession() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            AVAudioSession.sharedInstance().deactivate(options: [.notifyOthersOnDeactivation]) { _, _ in
                continuation.resume()
            }
        }
        sessionReady = false
    }

    // MARK: - Record

    private func beginRecording(generation: Int) throws {
        stopMeter()
        if recorder?.isRecording == true { recorder?.stop() }
        recorder = nil
        finishContinuation = nil
        if let old = recordingURL { try? FileManager.default.removeItem(at: old) }

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("dartiqo-voice-\(UUID().uuidString).m4a")
        recordingURL = url

        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 16_000,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
            AVEncoderBitRateKey: 32_000
        ]
        let recorder = try AVAudioRecorder(url: url, settings: settings)
        let proxy = RecorderFinishProxy { [weak self] success in
            Task { @MainActor in
                self?.handleRecorderFinished(success: success)
            }
        }
        recorder.delegate = proxy
        recorderDelegate = proxy
        recorder.isMeteringEnabled = true
        guard recorder.prepareToRecord(), recorder.record() else {
            throw VoiceListenError.recordFailed
        }
        self.recorder = recorder
        heardSpeech = false
        silenceTicks = 0
        recordingStartedAt = Date()
        inputLevel = 0
        transcript = "Poslouchám…"
        startMeter(generation: generation)
    }

    private func startMeter(generation: Int) {
        stopMeter()
        let timer = Timer.scheduledTimer(withTimeInterval: 0.08, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.pollMeters(generation: generation)
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        meterTimer = timer
    }

    private func stopMeter() {
        meterTimer?.invalidate()
        meterTimer = nil
    }

    private func pollMeters(generation: Int) {
        guard generation == startGeneration, phase == .listening, let recorder, recorder.isRecording else { return }
        recorder.updateMeters()
        let level = recorder.averagePower(forChannel: 0)
        // −55…−20 dB → 0…1
        let normalized = CGFloat(max(0, min(1, (level + 55) / 35)))
        inputLevel = inputLevel * 0.55 + normalized * 0.45

        if level > speechThreshold {
            heardSpeech = true
            silenceTicks = 0
            if transcript == "Poslouchám…" { transcript = "Slyším…" }
        } else if heardSpeech, level < silenceThreshold {
            silenceTicks += 1
        }

        let elapsed = Date().timeIntervalSince(recordingStartedAt ?? .now)
        if (heardSpeech && silenceTicks >= silenceNeeded) || (heardSpeech && elapsed >= maxSeconds) {
            commitRecording(generation: generation)
        }
    }

    private func commitRecording(generation: Int) {
        guard generation == startGeneration, phase == .listening else { return }
        stopMeter()
        phase = .recognizing
        transcript = "Rozpoznávám…"
        inputLevel = 0

        Task { @MainActor in
            do {
                let url = try await stopRecorderAndWaitForFile()
                guard generation == startGeneration else { return }

                let text = try await recognizeFile(url: url, generation: generation)
                try? FileManager.default.removeItem(at: url)
                if recordingURL == url { recordingURL = nil }

                guard generation == startGeneration else { return }
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                consecutiveFailures = 0

                if let command = VoiceScoreParser.parse(trimmed, mode: mode) {
                    lastHeard = trimmed
                    transcript = trimmed
                    lastCommandLabel = Self.label(for: command)
                    onCommand?(command)
                } else if !trimmed.isEmpty {
                    transcript = trimmed
                    lastCommandLabel = nil
                }

                guard generation == startGeneration else { return }
                try beginRecording(generation: generation)
                phase = .listening
            } catch {
                guard generation == startGeneration else { return }
                consecutiveFailures += 1
                let ns = error as NSError
                // 1101 = lokální speech služba / on-device — nespamuj alertem, zkus dál.
                if ns.domain == "kAFAssistantErrorDomain", ns.code == 1101 {
                    transcript = "Čekám na řeč…"
                    if consecutiveFailures >= 5 {
                        lastError = "Rozpoznávání řeči není připravené. Zapni internet nebo v Nastavení stáhni hlasové data pro češtinu (Siri)."
                        await tearDown(deactivate: true, expectedGeneration: generation)
                        guard generation == startGeneration else { return }
                        phase = .idle
                        return
                    }
                } else if !(error is CancellationError) {
                    if consecutiveFailures >= 3 {
                        lastError = friendlyError(error)
                    }
                }
                do {
                    try beginRecording(generation: generation)
                    phase = .listening
                } catch {
                    lastError = friendlyError(error)
                    await tearDown(deactivate: true, expectedGeneration: generation)
                    guard generation == startGeneration else { return }
                    phase = .idle
                }
            }
        }
    }

    private static func label(for command: VoiceScoreCommand) -> String {
        switch command {
        case .bust: return "Přehoz"
        case .total(let score): return "Součet \(score)"
        case .darts(let darts): return darts.map(\.label).joined(separator: " · ")
        }
    }

    private func stopRecorderAndWaitForFile() async throws -> URL {
        guard let recorder, let url = recordingURL else {
            throw VoiceListenError.recordFailed
        }
        if !recorder.isRecording {
            return url
        }
        return try await withCheckedThrowingContinuation { continuation in
            finishContinuation = continuation
            recorder.stop()
            // Pojistka, kdyby delegate nepřišel.
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 900_000_000)
                if let cont = self.finishContinuation {
                    self.finishContinuation = nil
                    if FileManager.default.fileExists(atPath: url.path) {
                        cont.resume(returning: url)
                    } else {
                        cont.resume(throwing: VoiceListenError.recordFailed)
                    }
                }
            }
        }
    }

    private func handleRecorderFinished(success: Bool) {
        guard let cont = finishContinuation else { return }
        finishContinuation = nil
        recorder = nil
        guard success, let url = recordingURL, FileManager.default.fileExists(atPath: url.path) else {
            cont.resume(throwing: VoiceListenError.recordFailed)
            return
        }
        cont.resume(returning: url)
    }

    private func recognizeFile(url: URL, generation: Int) async throws -> String {
        guard let recognizer, recognizer.isAvailable else {
            throw VoiceListenError.recognizerUnavailable
        }
        let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
        let size = (attrs?[.size] as? NSNumber)?.intValue ?? 0
        if size < 800 { return "" }

        // Krátká pauza — soubor musí dojít na disk (FigExport -12785).
        try await Task.sleep(nanoseconds: 40_000_000)

        let request = SFSpeechURLRecognitionRequest(url: url)
        request.shouldReportPartialResults = false
        // Důležité: nevynucovat on-device — u cs-CZ často chybí a padá 1101.
        request.requiresOnDeviceRecognition = false
        request.taskHint = .dictation
        if #available(iOS 16, *) {
            request.addsPunctuation = false
        }
        request.contextualStrings = Self.dartContextHints

        return try await withCheckedThrowingContinuation { continuation in
            var settled = false
            recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
                Task { @MainActor in
                    guard let self, generation == self.startGeneration else { return }
                    if let result {
                        self.transcript = result.bestTranscription.formattedString
                        if result.isFinal, !settled {
                            settled = true
                            self.recognitionTask = nil
                            continuation.resume(returning: result.bestTranscription.formattedString)
                        }
                        return
                    }
                    if let error, !settled {
                        settled = true
                        self.recognitionTask = nil
                        let ns = error as NSError
                        if ns.domain == "kAFAssistantErrorDomain", (ns.code == 216 || ns.code == 1110) {
                            continuation.resume(returning: self.transcript)
                        } else {
                            continuation.resume(throwing: error)
                        }
                    }
                }
            }
        }
    }

    private static let dartContextHints = [
        "trojitá", "dvojitá", "single", "triple", "double",
        "dvacet", "devatenáct", "osmnáct", "sedmnáct", "šestnáct", "patnáct",
        "čtrnáct", "třináct", "dvanáct", "jedenáct", "deset",
        "devět", "osm", "sedm", "šest", "pět", "čtyři", "tři", "dva", "jedna",
        "bull", "bullseye", "mimo", "přehoz", "bust", "nula",
        "sto", "osmdesát", "sedmdesát", "šedesát", "padesát", "čtyřicet", "třicet",
        "sto osmdesát", "sto čtyřicet", "sto dvacet", "sto",
        "T20", "T19", "D20", "D16", "S20", "S19",
        "20", "19", "18", "17", "16", "15", "14", "13", "12", "11",
        "10", "9", "8", "7", "6", "5", "4", "3", "2", "1", "0",
        "180", "140", "100", "60", "45", "26"
    ]

    private func invalidateCapture() {
        stopMeter()
        recognitionTask?.cancel()
        recognitionTask = nil
        if let cont = finishContinuation {
            finishContinuation = nil
            cont.resume(throwing: CancellationError())
        }
        if recorder?.isRecording == true { recorder?.stop() }
        recorder = nil
        recorderDelegate = nil
        if let url = recordingURL {
            try? FileManager.default.removeItem(at: url)
        }
        recordingURL = nil
        heardSpeech = false
        silenceTicks = 0
        inputLevel = 0
    }

    private func tearDown(deactivate: Bool, expectedGeneration: Int? = nil) async {
        if let expectedGeneration, expectedGeneration != startGeneration { return }
        invalidateCapture()
        if deactivate {
            if let expectedGeneration, expectedGeneration != startGeneration { return }
            await deactivateSession()
        }
    }

    private func friendlyError(_ error: Error) -> String {
        if let listen = error as? VoiceListenError { return listen.localizedDescription }
        let ns = error as NSError
        if ns.domain == "kAFAssistantErrorDomain" {
            return "Rozpoznávání řeči teď nejde. Zkus zapnout internet a v Nastavení zkontrolovat Siri / češtinu."
        }
        if ns.domain == "com.apple.coreaudio.avfaudio" {
            return "Mikrofon se nepodařilo spustit. Zkus Hlas vypnout a zapnout."
        }
        return "Hlasový zápis selhal. Zkus to znovu."
    }
}

private enum VoiceListenError: LocalizedError {
    case activationFailed
    case recordFailed
    case recognizerUnavailable

    var errorDescription: String? {
        switch self {
        case .activationFailed: return "Nepodařilo se zapnout mikrofon."
        case .recordFailed: return "Nahrávání se nespustilo. Zkus to znovu."
        case .recognizerUnavailable: return "Rozpoznávání češtiny teď není dostupné."
        }
    }
}

/// AVAudioRecorderDelegate mimo MainActor izolaci.
private final class RecorderFinishProxy: NSObject, AVAudioRecorderDelegate {
    private let handler: (Bool) -> Void
    init(handler: @escaping (Bool) -> Void) { self.handler = handler }
    func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        handler(flag)
    }
}
