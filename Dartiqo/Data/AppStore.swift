import SwiftUI
import UIKit
import Combine
import LocalAuthentication
import AVFoundation
import UniformTypeIdentifiers

struct Profile: Codable, Identifiable {
    var id = UUID()
    var name: String
    var createdAt = Date()
    /// Malý JPEG portrét. Chybějící klíč ve starších souborech zůstane prázdný.
    var photoJPEG: Data?
}
struct Friend: Codable, Identifiable, Equatable {
    var id = UUID()
    var owner: UUID
    var name: String
    var lastPlayed: Date?
}
struct StoredData: Codable {
    var version = 1
    var profiles: [Profile] = []
    var selectedProfile: UUID?
    var matches: [Match] = []
    var activeMatches: [String: Match] = [:]
    var haptics = true
    var voice = false
    var appearance = "dark"
    var biometricLock = false
    var presets: [GamePreset]?
    var lastSetups: [String: SetupDraft]?
    /// Camera-to-board mapping for autoscore. Optional so older saves still decode.
    var boardCalibration: BoardCalibration?
    var friends: [Friend]?
    /// Trénink. Volitelná pole, aby starší soubor verze 1 dál šel načíst.
    var trainingSessions: [TrainingSession]?
    var activeTraining: [String: TrainingSession]?
    var trainingFavorites: [String: [String]]?
    var xpEvents: [XPEvent]?
    var trainingPlan: [String: TrainingPlan]?
    var achievementUnlocks: [AchievementUnlock]?
}
struct JSONDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    var data: Data
    init(data: Data) { self.data = data }
    init(configuration: ReadConfiguration) throws { data = configuration.file.regularFileContents ?? Data() }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: data) }
}
enum AppSection: Hashable {
    case home, play, training, games, profile
}

@MainActor final class AppStore: ObservableObject {
    @Published var data = StoredData()
    @Published var locked = false
    @Published var storageError: String?
    @Published var authError: String?
    @Published var section: AppSection = .home
    /// Nová hodnota zavře zápas i průvodce a vrátí čistou domovskou obrazovku.
    @Published private(set) var homeGeneration = 0
    private let speaker = AVSpeechSynthesizer()
    @Published private(set) var needsRecovery = false
    private let file: URL
    init() {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Dartiqo", isDirectory: true)
        file = directory.appendingPathComponent("dartiqo-v1.json")
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            if FileManager.default.fileExists(atPath: file.path) {
                let decoded = try JSONDecoder().decode(StoredData.self, from: Data(contentsOf: file))
                guard decoded.version == 1, decoded.matches.allSatisfy(\.isSane), decoded.activeMatches.values.allSatisfy(\.isSane) else { throw CocoaError(.fileReadCorruptFile) }
                data = decoded
            }
        } catch { needsRecovery = true; storageError = "Data se nepodařilo načíst. Původní soubor nebyl přepsán. Použij obrazovku obnovy pro uložení kopie dat. \(error.localizedDescription)" }
        locked = data.biometricLock && profile != nil
    }
    var presets: [GamePreset] { (data.presets ?? []).filter { $0.owner == profile?.id } }
    func remember(_ setup: SetupDraft) {
        guard let id = profile?.id.uuidString else { return }
        if data.lastSetups == nil { data.lastSetups = [:] }
        data.lastSetups?[id] = setup; save()
    }
    func addPreset(name: String, setup: SetupDraft) {
        guard let id = profile?.id else { return }
        let clean = String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(32))
        guard !clean.isEmpty else { return }
        if data.presets == nil { data.presets = [] }
        data.presets?.append(GamePreset(owner: id, name: clean, setup: setup)); save()
    }
    func deletePreset(_ id: UUID) { data.presets?.removeAll { $0.id == id }; save() }
    var friends: [Friend] {
        (data.friends ?? []).filter { $0.owner == profile?.id }.sorted {
            ($0.lastPlayed ?? .distantPast, $1.name) > ($1.lastPlayed ?? .distantPast, $0.name)
        }
    }
    /// Ostatní profily na tomhle telefonu.
    var housemates: [Profile] { data.profiles.filter { $0.id != profile?.id } }
    @discardableResult func addFriend(_ name: String) -> Friend? {
        guard let owner = profile?.id else { return nil }
        let clean = String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(24))
        guard !clean.isEmpty else { return nil }
        if let existing = friends.first(where: { $0.name.compare(clean, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame }) { return existing }
        let friend = Friend(owner: owner, name: clean)
        if data.friends == nil { data.friends = [] }
        data.friends?.append(friend); save()
        return friend
    }
    func deleteFriend(_ id: UUID) { data.friends?.removeAll { $0.id == id }; save() }
    func notePlayed(with ids: [UUID]) {
        guard var all = data.friends else { return }
        let now = Date()
        for index in all.indices where ids.contains(all[index].id) { all[index].lastPlayed = now }
        data.friends = all; save()
    }
    var profile: Profile? { data.profiles.first { $0.id == data.selectedProfile } }
    func photo(for playerID: UUID) -> Data? {
        data.profiles.first { $0.id == playerID }?.photoJPEG
    }
    var matches: [Match] { guard let id = profile?.id else { return [] }; return data.matches.filter { $0.players.contains { $0.id == id } }.sorted { ($0.completedAt ?? $0.createdAt) > ($1.completedAt ?? $1.createdAt) } }
    var activeMatch: Match? {
        get { guard let id = profile?.id.uuidString else { return nil }; return data.activeMatches[id] }
        set { guard let id = profile?.id.uuidString else { return }; data.activeMatches[id] = newValue; save() }
    }
    var xp: Int {
        let played = matches.reduce(0) { sum, match in sum + 50 + ((match.winner.map { match.players[$0].id == profile?.id } ?? false) ? 50 : 0) }
        let trained = (data.xpEvents ?? []).filter { $0.owner == profile?.id }.reduce(0) { $0 + $1.amount }
        return played + trained
    }
    var level: Int { xp / 500 + 1 }
    var x01Matches: [Match] { matches.filter { $0.config.mode == .x01 } }
    var ownVisits: [Visit] { x01Matches.flatMap { m in m.visits.filter { m.players[$0.player].id == profile?.id } } }
    var average: Double {
        let darts = ownVisits.reduce(0) { $0 + $1.darts.count }
        return darts == 0 ? 0 : Double(ownVisits.reduce(0) { $0 + $1.credited }) * 3 / Double(darts)
    }
    var wins: Int { matches.filter { m in m.winner.map { m.players[$0].id == profile?.id } ?? false }.count }
    var n180: Int { ownVisits.filter { $0.credited == 180 }.count }
    func recoveryDocument() throws -> JSONDocument { JSONDocument(data: try Data(contentsOf: file)) }
    func resetAfterRecovery() {
        do {
            if FileManager.default.fileExists(atPath: file.path) {
                let backup = file.deletingLastPathComponent().appendingPathComponent("recovery-\(UUID().uuidString).json")
                try FileManager.default.copyItem(at: file, to: backup)
            }
            let fresh = StoredData()
            try JSONEncoder().encode(fresh).write(to: file, options: [.atomic, .completeFileProtection])
            data = fresh; needsRecovery = false; locked = false; storageError = nil
        } catch { storageError = "Obnovu se nepodařilo dokončit. Původní data zůstala zachována. \(error.localizedDescription)" }
    }
    func save() {
        guard !needsRecovery else { return }
        do { try JSONEncoder().encode(data).write(to: file, options: [.atomic, .completeFileProtection]) }
        catch { storageError = "Změny se nepodařilo uložit. \(error.localizedDescription)" }
    }
    func createProfile(_ name: String) {
        let clean = String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(24)); guard !clean.isEmpty else { return }
        let p = Profile(name: clean); data.profiles.append(p); data.selectedProfile = p.id; save()
    }
    func select(_ profile: Profile) { data.selectedProfile = profile.id; save() }
    func rename(_ name: String) {
        let clean = String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(24))
        guard !clean.isEmpty, let index = data.profiles.firstIndex(where: { $0.id == data.selectedProfile }) else { return }
        data.profiles[index].name = clean; save()
    }
    func setPhoto(_ image: UIImage?) {
        guard let index = data.profiles.firstIndex(where: { $0.id == data.selectedProfile }) else { return }
        if let image {
            let thumb = image.preparingThumbnail(of: CGSize(width: 320, height: 320)) ?? image
            data.profiles[index].photoJPEG = thumb.jpegData(compressionQuality: 0.82)
        } else {
            data.profiles[index].photoJPEG = nil
        }
        save()
    }
    func signOut() { data.selectedProfile = nil; save() }
    func finish() {
        guard let match = activeMatch, match.finished else { return }
        if !data.matches.contains(where: { $0.id == match.id }) { var archived = match; archived.undoStack = []; data.matches.append(archived) }
        activeMatch = nil
    }
    func deleteMatch(_ id: UUID) {
        guard data.matches.contains(where: { $0.id == id }) else { return }
        data.matches.removeAll { $0.id == id }
        save()
    }
    /// Uloží dohraný zápas a otevře záložku Domů bez rozehrané obrazovky zápasu.
    func returnHome() {
        finish()
        section = .home
        homeGeneration += 1
    }
    func feedback(_ score: Int? = nil) {
        if data.haptics { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
        if data.voice, let score { speaker.stopSpeaking(at: .immediate); let line = AVSpeechUtterance(string: "\(score)"); line.voice = AVSpeechSynthesisVoice(language: "cs-CZ"); speaker.speak(line) }
    }
    private var authInFlight = false

    func authenticate(enabling: Bool = false) async {
        guard enabling || locked else { return }
        guard !authInFlight else { return }
        authInFlight = true
        defer { authInFlight = false }
        let context = LAContext()
        do {
            let success = try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "Odemkni svůj hráčský profil v Dartiqo.")
            if success {
                authError = nil
                locked = false
                if enabling { data.biometricLock = true; save() }
            }
        } catch let error as LAError where error.code == .userCancel || error.code == .appCancel || error.code == .systemCancel {
        } catch {
            authError = error.localizedDescription
        }
    }
    func deleteProfile() {
        guard let id = profile?.id else { return }
        data.matches.removeAll { $0.players.contains { $0.id == id } }
        data.activeMatches[id.uuidString] = nil
        data.presets?.removeAll { $0.owner == id }; data.lastSetups?[id.uuidString] = nil
        data.profiles.removeAll { $0.id == id }; data.selectedProfile = nil
        data.trainingSessions?.removeAll { $0.owner == id }
        data.activeTraining?[id.uuidString] = nil
        data.trainingFavorites?[id.uuidString] = nil
        data.xpEvents?.removeAll { $0.owner == id }
        data.trainingPlan?[id.uuidString] = nil
        data.achievementUnlocks?.removeAll { $0.owner == id }
        save()
    }
    var boardCalibration: BoardCalibration? { data.boardCalibration }
    var boardMapper: BoardMapper? {
        guard let calibration = data.boardCalibration, calibration.isCalibrated else { return nil }
        let mapper = BoardMapper(calibration: calibration)
        return mapper.isReady ? mapper : nil
    }
    func saveBoardCalibration(_ calibration: BoardCalibration) {
        data.boardCalibration = calibration.sanitized()
        save()
    }
    func clearBoardCalibration() {
        data.boardCalibration = nil
        save()
    }
    /// Hody z kamery v obrazu kamery. Opravené posunou mapu, potvrzené ji drží.
    func learnDarts(_ samples: [DartSample]) {
        guard !samples.isEmpty, let calibration = data.boardCalibration, calibration.isCameraMapped else { return }
        data.boardCalibration = DartLearning.learn(calibration, adding: samples).sanitized()
        save()
    }
    var learnedCorrections: Int { data.boardCalibration?.samples?.filter(\.corrected).count ?? 0 }
    func forgetLearning() {
        data.boardCalibration?.samples = nil
        data.boardCalibration?.learned = nil
        save()
    }
    func export() throws -> JSONDocument { let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]; return JSONDocument(data: try encoder.encode(data)) }

    var trainingHistory: [TrainingSession] {
        guard let id = profile?.id else { return [] }
        return (data.trainingSessions ?? []).filter { $0.owner == id }.sorted { ($0.finishedAt ?? $0.startedAt) > ($1.finishedAt ?? $1.startedAt) }
    }
    var activeTrainingSession: TrainingSession? {
        guard let id = profile?.id.uuidString else { return nil }
        return data.activeTraining?[id]
    }
    var favoriteTrainingIDs: [String] {
        guard let id = profile?.id.uuidString else { return [] }
        return data.trainingFavorites?[id] ?? []
    }
    var currentTrainingPlan: TrainingPlan? {
        guard let id = profile?.id.uuidString else { return nil }
        return data.trainingPlan?[id]
    }
    func isFavoriteTraining(_ id: String) -> Bool { favoriteTrainingIDs.contains(id) }
    func trainingContext() -> TrainingContext {
        TrainingCoach.context(matches: matches, sessions: trainingHistory, profileID: profile?.id)
    }
    func trainingRecommendation() -> TrainingRecommendation {
        TrainingCoach.recommend(matches: matches, sessions: trainingHistory, profileID: profile?.id)
    }
    func ghostThrows(for definitionID: String) -> [Dart]? {
        guard let session = trainingHistory.first(where: { $0.definitionID == definitionID && $0.status == .completed && ($0.result?.darts ?? 0) > 0 }) else { return nil }
        let darts = session.actions.compactMap { action -> Dart? in
            if case .dart(let dart) = action { return dart }
            return nil
        }
        return darts.isEmpty ? nil : darts
    }
    func bestTrainingResult(for definitionID: String) -> TrainingResult? {
        trainingHistory.compactMap { session -> TrainingResult? in
            guard session.definitionID == definitionID, session.status == .completed, session.result?.success == true else { return nil }
            return session.result
        }.max { lhs, rhs in
            if lhs.higherIsBetter { return lhs.score < rhs.score }
            return lhs.score > rhs.score
        }
    }
    func stageTraining(_ session: TrainingSession) {
        guard let key = profile?.id.uuidString, session.owner == profile?.id else { return }
        if data.activeTraining == nil { data.activeTraining = [:] }
        data.activeTraining?[key] = session
        save()
    }
    func toggleTrainingFavorite(_ id: String) {
        guard let key = profile?.id.uuidString else { return }
        if data.trainingFavorites == nil { data.trainingFavorites = [:] }
        var list = data.trainingFavorites?[key] ?? []
        if let index = list.firstIndex(of: id) { list.remove(at: index) } else { list.append(id) }
        data.trainingFavorites?[key] = list
        save()
    }
    func saveTrainingPlan(_ plan: TrainingPlan) {
        guard let key = profile?.id.uuidString, plan.owner == profile?.id else { return }
        if data.trainingPlan == nil { data.trainingPlan = [:] }
        data.trainingPlan?[key] = plan
        save()
    }
    /// Zapíše výsledek jednou. Stejné id session XP ani historii nezdvojí.
    @discardableResult
    func commitTraining(_ session: TrainingSession) -> Int {
        guard let owner = profile?.id, session.owner == owner, session.status == .completed, session.result != nil else { return 0 }
        if data.trainingSessions?.contains(where: { $0.id == session.id }) == true {
            if data.activeTraining?[owner.uuidString]?.id == session.id { data.activeTraining?[owner.uuidString] = nil; save() }
            return data.xpEvents?.first { $0.sessionID == session.id }?.amount ?? 0
        }
        if data.trainingSessions == nil { data.trainingSessions = [] }
        let calendar = Calendar.current
        let day = calendar.startOfDay(for: session.finishedAt ?? Date())
        let prior = (data.trainingSessions ?? []).filter {
            $0.owner == owner && $0.definitionID == session.definitionID && $0.status == .completed &&
            calendar.startOfDay(for: $0.finishedAt ?? $0.startedAt) == day
        }.count
        let result = session.result!
        let previous = bestTrainingResult(for: session.definitionID)
        let record = result.success && isBetterTraining(result, than: previous)
        let amount: Int
        if let definition = TrainingCatalog.find(session.definitionID) {
            amount = TrainingRewards.award(
                definition: definition,
                config: session.config,
                result: result,
                completionsToday: prior,
                isRecord: record,
                isDaily: session.config.isDaily,
                isWeekly: session.config.isWeekly
            )
        } else {
            amount = 0
        }
        data.trainingSessions?.append(session)
        if amount > 0 {
            if data.xpEvents == nil { data.xpEvents = [] }
            if data.xpEvents?.contains(where: { $0.sessionID == session.id }) != true {
                data.xpEvents?.append(XPEvent(owner: owner, sessionID: session.id, definitionID: session.definitionID, amount: amount, createdAt: session.finishedAt ?? Date()))
            }
        }
        if data.activeTraining?[owner.uuidString]?.id == session.id { data.activeTraining?[owner.uuidString] = nil }
        if var plan = data.trainingPlan?[owner.uuidString] {
            if let index = plan.items.firstIndex(where: { $0.sessionID == nil && $0.definitionID == session.definitionID }) {
                plan.items[index].sessionID = session.id
            }
            let history = (data.trainingSessions ?? []).filter { $0.owner == owner }
            TrainingPlans.react(&plan, sessions: history)
            data.trainingPlan?[owner.uuidString] = plan
        }
        let owned = (data.trainingSessions ?? []).filter { $0.owner == owner }
        let earned = TrainingAchievements.earned(sessions: owned, matchOneEighties: n180, streak: TrainingStreaks.daily(sessions: owned))
        if data.achievementUnlocks == nil { data.achievementUnlocks = [] }
        let have = Set((data.achievementUnlocks ?? []).filter { $0.owner == owner }.map(\.key))
        for key in earned.subtracting(have) {
            data.achievementUnlocks?.append(AchievementUnlock(owner: owner, key: key))
        }
        save()
        return amount
    }
    func abandonTraining(_ session: TrainingSession) {
        guard let owner = profile?.id.uuidString else { return }
        if data.activeTraining?[owner]?.id == session.id { data.activeTraining?[owner] = nil; save() }
    }
    func trainingUnlocked(_ key: String) -> Bool {
        guard let owner = profile?.id else { return false }
        if (data.achievementUnlocks ?? []).contains(where: { $0.owner == owner && $0.key == key }) { return true }
        let owned = trainingHistory
        return TrainingAchievements.earned(sessions: owned, matchOneEighties: n180, streak: TrainingStreaks.daily(sessions: owned)).contains(key)
    }
    private func isBetterTraining(_ result: TrainingResult, than previous: TrainingResult?) -> Bool {
        guard result.success else { return false }
        guard let previous else { return true }
        if result.higherIsBetter { return result.score > previous.score }
        return result.score < previous.score
    }
}
