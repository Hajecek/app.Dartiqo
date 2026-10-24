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
    /// Lokální handle pro hledání mezi profily na zařízení.
    var username: String?
    var email: String?
    /// Dokončené a zrušené zápasy. Historie se dá smazat, tahle bilance ne.
    var matchCompletion: MatchCompletionLedger?
    /// Webový účet Dartiqo, ke kterému profil patří.
    var accountID: Int?
}
struct Friend: Codable, Identifiable, Equatable {
    var id = UUID()
    var owner: UUID
    var name: String
    var lastPlayed: Date?
    var photoJPEG: Data?
    var username: String?
    var email: String?
    /// Propojení s profilem na stejném telefonu (stejné UUID v zápasech / H2H).
    var linkedProfileID: UUID?
}
/// Výsledek hledání profilu v Dartiqo na tomto zařízení.
struct DartiqoPersonHit: Identifiable, Equatable {
    var id: UUID
    var name: String
    var username: String?
    var email: String?
    var photoJPEG: Data?
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
    /// Zápasové XP zapsané jednou pro hráče a zápas. Trénink zůstává v `xpEvents`.
    var matchXPAwards: [MatchXPAward]?
    /// Trvalé učení Zrcadla stylu (klíč owner|start|out).
    var ghostStyleMemories: [String: GhostStyleMemory]?
    /// `nil` a `true` znamenají zapnuto. Vypnutí nechá bota na ručně zvolené úrovni.
    var adaptiveAI: Bool?
    /// Jak se během hry kreslí průměr a další čísla. `nil` = celkový průměr zápasu, nic navíc.
    var matchDisplay: MatchDisplay?
    /// Komentátor podle profilu. `nil` a `system` = výchozí hlas, `custom` = namluvené hlášky.
    var commentators: [String: String]?
    /// Zrušené zápasy, které ještě čekají na odeslání na web. V historii nejsou.
    var pendingAbandoned: [Match]?
    /// Zápasy smazané z historie, které se ještě musí smazat i na webu.
    var pendingMatchDeletes: [UUID]?
    /// Dohrané zápasy, které už jsou na webu. Když pak na webu chybí, hráč je tam smazal.
    var uploadedMatches: [UUID]?
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
    /// Průvodce z karty Hrát lokálně zakryje spodní lištu rozehraného zápasu.
    @Published var localSetupCoversBar = false
    /// Nová hodnota zavře zápas i průvodce a vrátí čistou domovskou obrazovku.
    @Published private(set) var homeGeneration = 0
    /// Namluvené hlášky aktuálního profilu.
    let commentary = CommentaryLibrary()
    /// Posune seznamy nahrávek po uložení nebo smazání.
    @Published private(set) var commentaryTick = 0
    /// Vlastní audio relace, ať přesun tahu ani vypnutí mikrofonu větu neusekne.
    private let speaker: AVSpeechSynthesizer = {
        let speaker = AVSpeechSynthesizer()
        speaker.usesApplicationAudioSession = false
        return speaker
    }()
    @Published private(set) var needsRecovery = false
    private let file: URL
    /// Spojí rychlé zápisy (šipky) do jednoho zápisu na disk.
    private var saveTask: Task<Void, Never>?
    /// Jedna připravená odezva. Nový generátor na každý stisk při rychlých třech šipkách zasekne hlavní vlákno.
    private let lightImpact = UIImpactFeedbackGenerator(style: .light)
    private let softImpact = UIImpactFeedbackGenerator(style: .soft)
    private let mediumImpact = UIImpactFeedbackGenerator(style: .medium)
    private let selectionFeedback = UISelectionFeedbackGenerator()
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
        if !needsRecovery {
            wipeLocalOnlyDataOnce()
            backfillMatchXP()
            backfillMatchCompletion()
        }
        locked = data.biometricLock && profile != nil
        prepareHaptics()
    }
#if DEBUG
    /// In-memory store pro SwiftUI Previews — nečte ani nepřepisuje produkční soubor.
    init(preview data: StoredData) {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("Dartiqo-Preview", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        file = directory.appendingPathComponent("preview-\(UUID().uuidString).json")
        self.data = data
        locked = false
        needsRecovery = false
        backfillMatchXP()
        backfillMatchCompletion()
        prepareHaptics()
    }
#endif
    var presets: [GamePreset] { (data.presets ?? []).filter { $0.owner == profile?.id } }
    func remember(_ setup: SetupDraft) {
        guard let id = profile?.id.uuidString else { return }
        if data.lastSetups == nil { data.lastSetups = [:] }
        data.lastSetups?[id] = setup; save()
    }
    /// Poslední sestava zápasu pro předvyplnění obrazovky Hrát.
    var lastSetup: SetupDraft? {
        guard let id = profile?.id.uuidString else { return nil }
        return data.lastSetups?[id]
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
        createFriend(name: name)
    }
    @discardableResult func createFriend(
        name: String,
        username: String? = nil,
        email: String? = nil,
        photo: UIImage? = nil,
        linkedProfileID: UUID? = nil
    ) -> Friend? {
        guard let owner = profile?.id else { return nil }
        let clean = String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(24))
        guard !clean.isEmpty else { return nil }
        let handle = Self.normalizeHandle(username)
        let mail = Self.normalizeEmail(email)
        if let linked = linkedProfileID,
           let existing = friends.first(where: { $0.id == linked || $0.linkedProfileID == linked }) {
            return attachPhotoIfMissing(existing.id, photo: photo)
        }
        if let existing = friends.first(where: {
            $0.name.compare(clean, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
        }) { return attachPhotoIfMissing(existing.id, photo: photo) }
        var friend = Friend(
            id: linkedProfileID ?? UUID(),
            owner: owner,
            name: clean,
            username: handle,
            email: mail,
            linkedProfileID: linkedProfileID
        )
        if let photo { friend.photoJPEG = Self.jpegThumb(photo) }
        if data.friends == nil { data.friends = [] }
        data.friends?.append(friend)
        save()
        return friend
    }
    /// Doplní portrét jen tam, kde ještě žádný není. Ručně zvolená fotka zůstane.
    private func attachPhotoIfMissing(_ id: UUID, photo: UIImage?) -> Friend? {
        guard var all = data.friends,
              let index = all.firstIndex(where: { $0.id == id }) else { return nil }
        if all[index].photoJPEG == nil, let photo, let jpeg = Self.jpegThumb(photo) {
            all[index].photoJPEG = jpeg
            data.friends = all
            save()
        }
        return data.friends?.first { $0.id == id }
    }
    /// Najde jiné profily na zařízení podle jména, username nebo e-mailu.
    func findDartiqoPeople(query: String) -> [DartiqoPersonHit] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard needle.count >= 2 else { return [] }
        let options: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]
        return housemates.compactMap { person in
            let haystacks = [person.name, person.username, person.email].compactMap { $0 }
            guard haystacks.contains(where: { $0.range(of: needle, options: options) != nil }) else { return nil }
            return DartiqoPersonHit(
                id: person.id,
                name: person.name,
                username: person.username,
                email: person.email,
                photoJPEG: person.photoJPEG
            )
        }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
    func deleteFriend(_ id: UUID) { data.friends?.removeAll { $0.id == id }; save() }
    /// Upraví lokální profil kamaráda. Fotku mění jen když přijde nový snímek.
    @discardableResult func updateFriend(
        _ id: UUID,
        name: String,
        username: String?,
        email: String?,
        photo: UIImage? = nil
    ) -> Friend? {
        guard var all = data.friends,
              let index = all.firstIndex(where: { $0.id == id && $0.owner == profile?.id }) else { return nil }
        let clean = String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(24))
        guard !clean.isEmpty else { return nil }
        all[index].name = clean
        all[index].username = Self.normalizeHandle(username)
        all[index].email = Self.normalizeEmail(email)
        if let photo { all[index].photoJPEG = Self.jpegThumb(photo) }
        data.friends = all
        save()
        return all[index]
    }
    func notePlayed(with ids: [UUID]) {
        guard var all = data.friends else { return }
        let now = Date()
        for index in all.indices where ids.contains(all[index].id) || ids.contains(where: { all[index].linkedProfileID == $0 }) {
            all[index].lastPlayed = now
        }
        data.friends = all; save()
    }
    var profile: Profile? { data.profiles.first { $0.id == data.selectedProfile } }
    func photo(for playerID: UUID) -> Data? {
        let friend = data.friends?.first { $0.id == playerID || $0.linkedProfileID == playerID }
        if let jpeg = friend?.photoJPEG { return jpeg }
        if let jpeg = data.profiles.first(where: { $0.id == playerID })?.photoJPEG { return jpeg }
        if let linked = friend?.linkedProfileID {
            return data.profiles.first { $0.id == linked }?.photoJPEG
        }
        return nil
    }
    func updateProfileContact(username: String?, email: String?) {
        guard let index = data.profiles.firstIndex(where: { $0.id == data.selectedProfile }) else { return }
        data.profiles[index].username = Self.normalizeHandle(username)
        data.profiles[index].email = Self.normalizeEmail(email)
        save()
    }
    private static func normalizeHandle(_ raw: String?) -> String? {
        guard let raw else { return nil }
        var clean = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if clean.hasPrefix("@") { clean.removeFirst() }
        clean = String(clean.prefix(24))
        return clean.isEmpty ? nil : clean
    }
    private static func normalizeEmail(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let clean = String(raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased().prefix(64))
        return clean.isEmpty ? nil : clean
    }
    private static func jpegThumb(_ image: UIImage) -> Data? {
        let thumb = image.preparingThumbnail(of: CGSize(width: 320, height: 320)) ?? image
        return thumb.jpegData(compressionQuality: 0.82)
    }
    var matches: [Match] { guard let id = profile?.id else { return [] }; return data.matches.filter { $0.players.contains { $0.id == id } }.sorted { ($0.completedAt ?? $0.createdAt) > ($1.completedAt ?? $1.createdAt) } }
    var activeMatch: Match? {
        get { guard let id = profile?.id.uuidString else { return nil }; return data.activeMatches[id] }
        set {
            guard let id = profile?.id.uuidString else { return }
            if let old = data.activeMatches[id], old.id != newValue?.id {
                resolveMatchCompletion(old)
            }
            data.activeMatches[id] = newValue
            save()
        }
    }

    /// Bilance aktuálního profilu. Bez zápasů je prázdná, ne sto procent.
    var matchCompletion: MatchCompletionLedger {
        guard let id = profile?.id else { return MatchCompletionLedger() }
        return matchCompletion(for: id) ?? MatchCompletionLedger()
    }

    /// Bilance místního profilu. Bot, ghost ani cizí jméno bez profilu `nil`.
    func matchCompletion(for playerID: UUID) -> MatchCompletionLedger? {
        guard let profile = data.profiles.first(where: { $0.id == playerID }) else { return nil }
        return profile.matchCompletion ?? MatchCompletionLedger()
    }

    /// Krátký řádek do klasického zápasu. Bez rozhodnuté hry se nezobrazí.
    func completionCaption(for playerID: UUID) -> String? {
        guard let percent = matchCompletion(for: playerID)?.percent else { return nil }
        return "Dokončí \(Int(percent.rounded())) %"
    }

    /// Sestava jde spustit jako lokální zápas (aspoň jeden soupeř, platní hráči / ghost).
    func canStartLocalMatch(from draft: SetupDraft) -> Bool {
        guard profile != nil, !draft.seats.isEmpty else { return false }
        let opponents = draft.seats.indices.filter { !(draft.includesMe && $0 == 0) }
        guard !opponents.isEmpty else { return false }
        for i in draft.seats.indices {
            let seat = draft.seats[i]
            let isMe = draft.includesMe && i == 0
            if isMe { continue }
            if seat.ghostSeat {
                guard draft.config.mode == .x01, let kind = draft.ghostKind else { return false }
                guard ghostOffer(
                    kind,
                    startingScore: draft.config.startingScore,
                    outRule: draft.config.outRule,
                    matchID: draft.ghostMatchID
                ) != nil else { return false }
            } else if !seat.isBot {
                if seat.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return false }
            }
        }
        return true
    }

    /// Spustí lokální zápas ze sestavy. `firstPlayer == nil` = náhodný začátek při víc hráčích.
    @discardableResult
    func startLocalMatch(from source: SetupDraft, firstPlayer: Int? = nil) -> Bool {
        guard let profile, canStartLocalMatch(from: source) else { return false }
        var draft = source

        for i in draft.seats.indices {
            let seat = draft.seats[i]
            let isMe = draft.includesMe && i == 0
            if !isMe && !seat.isBot && !seat.ghostSeat && seat.friendID == nil {
                draft.seats[i].friendID = addFriend(seat.name)?.id
            }
        }

        var players: [Player] = []
        var activeGhost: GhostOffer?
        var ghostSeat = -1
        for i in draft.seats.indices {
            let seat = draft.seats[i]
            let isMe = draft.includesMe && i == 0
            if isMe {
                players.append(Player(id: profile.id, name: profile.name))
            } else if seat.ghostSeat {
                guard let kind = draft.ghostKind,
                      let offer = ghostOffer(
                        kind,
                        startingScore: draft.config.startingScore,
                        outRule: draft.config.outRule,
                        matchID: draft.ghostMatchID
                      )
                else { return false }
                activeGhost = offer
                ghostSeat = players.count
                players.append(Player(id: UUID(), name: offer.displayName))
            } else {
                let resolved = resolvedBot(seat)
                let name: String
                if seat.isBot {
                    name = botPersona(seat, before: i, in: draft.seats)
                } else {
                    name = String(seat.name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(24))
                }
                players.append(Player(
                    id: seat.isBot ? UUID() : seat.friendID ?? UUID(),
                    name: name,
                    botLevel: seat.isBot ? resolved.level : nil,
                    botStyle: seat.isBot ? resolved.style : nil,
                    adaptiveBot: seat.isBot && resolved.adaptive ? true : nil,
                    botAverage: seat.isBot ? resolved.average : nil,
                    botCheckout: seat.isBot ? resolved.checkout : nil,
                    botConsistency: seat.isBot ? resolved.consistency : nil,
                    botPressure: seat.isBot ? resolved.pressure : nil,
                    botIntelligence: seat.isBot ? resolved.intelligence : nil
                ))
            }
        }
        guard !players.isEmpty else { return false }

        notePlayed(with: draft.seats.compactMap(\.friendID))
        if [.aroundClock, .countUp].contains(draft.config.mode) {
            draft.config.legsToWin = 1
            draft.config.setsToWin = 1
        }
        draft.config.startingScore = min(GameConfig.maximumScore, max(GameConfig.minimumScore, draft.config.startingScore))
        let hasHandicap = draft.config.mode == .x01 && draft.seats.contains { !($0.handicap?.isEmpty ?? true) }
        draft.config.handicaps = hasHandicap ? draft.seats.map { $0.handicap ?? Handicap() } : nil

        let first: Int
        if players.count <= 1 {
            first = 0
        } else if let firstPlayer {
            first = min(max(0, firstPlayer), players.count - 1)
        } else {
            first = Int.random(in: 0..<players.count)
        }
        draft.starter = first
        remember(draft)

        var match = Match(config: draft.config, players: players, firstPlayer: first)
        if let offer = activeGhost, ghostSeat >= 0 {
            match.ghostKind = offer.kind
            match.ghostLabel = offer.kind.title
            match.ghostAverage = offer.average
            match.ghostVisits = offer.visits
            match.ghostVisitIndex = 0
            match.ghostPlayerIndex = ghostSeat
        }
        activeMatch = match
        feedback()
        announceMoment(.matchStart)
        return true
    }

    private func suggestedBotLevel() -> Int {
        guard let id = profile?.id else { return AdaptiveBotEngine.fallbackLevel }
        return AdaptiveBotEngine.recommendedLevel(matches: matches, playerID: id)
    }

    private func resolvedBot(_ seat: SeatDraft) -> ResolvedBot {
        seat.resolve(adaptiveAllowed: data.adaptiveAI != false, suggestedLevel: suggestedBotLevel())
    }

    private func botPersona(_ seat: SeatDraft, before index: Int, in seats: [SeatDraft]) -> String {
        seat.botTitle(earlier: seats[..<index], adaptiveAllowed: data.adaptiveAI != false, suggestedLevel: suggestedBotLevel())
    }
    var xp: Int {
        guard let id = profile?.id else { return 0 }
        let played = (data.matchXPAwards ?? []).filter { $0.owner == id }.reduce(0) { $0 + $1.amount }
        let trained = (data.xpEvents ?? []).filter { $0.owner == id }.reduce(0) { $0 + $1.amount }
        return max(0, played + trained)
    }

    /// Rozklad XP za konkrétní zápas. Uložená odměna má přednost, ať se po čase nepřepočítá jinak.
    func matchXP(for match: Match) -> MatchXPBreakdown {
        guard let id = profile?.id else { return MatchXPBreakdown() }
        if let stored = data.matchXPAwards?.first(where: { $0.owner == id && $0.matchID == match.id }) {
            return stored.breakdown
        }
        return MatchRewards.award(match: match, playerID: id, history: data.matches)
    }
    var level: Int { PlayerLevel.level(forXP: xp) }
    /// XP v aktuálním levelu / kolik chce další level / progress 0…1.
    var levelProgress: (intoLevel: Int, needed: Int, fraction: Double) {
        let p = PlayerLevel.progress(forXP: xp)
        return (p.intoLevel, p.needed, p.fraction)
    }
    var x01Matches: [Match] { matches.filter { $0.config.mode == .x01 } }
    /// Ghost nabídky pro zvolená X01 pravidla.
    func ghostOffers(startingScore: Int, outRule: OutRule) -> [GhostOffer] {
        guard let id = profile?.id else { return [] }
        return GhostMode.offers(
            matches: matches,
            playerID: id,
            startingScore: startingScore,
            outRule: outRule,
            memory: ghostStyleMemory(startingScore: startingScore, outRule: outRule)
        )
    }
    func ghostOffer(_ kind: GhostKind, startingScore: Int, outRule: OutRule, matchID: UUID? = nil) -> GhostOffer? {
        guard let id = profile?.id else { return nil }
        return GhostMode.offer(
            kind: kind,
            matches: matches,
            playerID: id,
            startingScore: startingScore,
            outRule: outRule,
            matchID: matchID,
            memory: ghostStyleMemory(startingScore: startingScore, outRule: outRule)
        )
    }
    func ghostMatchCandidates(startingScore: Int, outRule: OutRule) -> [GhostOffer] {
        guard let id = profile?.id else { return [] }
        return GhostMode.matchCandidates(matches: matches, playerID: id, startingScore: startingScore, outRule: outRule)
    }
    func ghostStyleMemory(startingScore: Int, outRule: OutRule) -> GhostStyleMemory? {
        guard let id = profile?.id else { return nil }
        let key = GhostStyleMemory.key(owner: id, startingScore: startingScore, outRule: outRule)
        if let existing = data.ghostStyleMemories?[key] { return existing }
        seedGhostStyleMemoryIfNeeded(owner: id, startingScore: startingScore, outRule: outRule)
        return data.ghostStyleMemories?[key]
    }

    /// Jednou naplní paměť z dosavadní historie (starší účty bez průběžného učení).
    private func seedGhostStyleMemoryIfNeeded(owner: UUID, startingScore: Int, outRule: OutRule) {
        let key = GhostStyleMemory.key(owner: owner, startingScore: startingScore, outRule: outRule)
        guard data.ghostStyleMemories?[key] == nil else { return }
        let pool = matches.filter {
            $0.finished && $0.config.mode == .x01
                && $0.config.startingScore == startingScore
                && $0.config.outRule == outRule
                && $0.players.contains { $0.id == owner }
        }
        .sorted { ($0.completedAt ?? $0.createdAt) < ($1.completedAt ?? $1.createdAt) }
        guard pool.count >= GhostMode.mirrorUnlockCount else { return }
        var memory = GhostStyleMemory(owner: owner, startingScore: startingScore, outRule: outRule)
        for match in pool {
            guard let index = match.players.firstIndex(where: { $0.id == owner }) else { continue }
            memory.learn(from: match, playerIndex: index)
        }
        if data.ghostStyleMemories == nil { data.ghostStyleMemories = [:] }
        data.ghostStyleMemories?[key] = memory
        save()
    }

    /// Po dohraném X01 aktualizuje učení Zrcadla stylu.
    func learnGhostStyle(from match: Match) {
        guard match.finished, match.config.mode == .x01 else { return }
        guard let owner = profile?.id,
              let index = match.players.firstIndex(where: { $0.id == owner })
        else { return }
        let key = GhostStyleMemory.key(
            owner: owner,
            startingScore: match.config.startingScore,
            outRule: match.config.outRule
        )
        var memory = data.ghostStyleMemories?[key] ?? GhostStyleMemory(
            owner: owner,
            startingScore: match.config.startingScore,
            outRule: match.config.outRule
        )
        memory.learn(from: match, playerIndex: index)
        if data.ghostStyleMemories == nil { data.ghostStyleMemories = [:] }
        data.ghostStyleMemories?[key] = memory
        save()
    }
    var ownVisits: [Visit] { x01Matches.flatMap { m in m.visits.filter { m.players[$0.player].id == profile?.id } } }
    var average: Double {
        let darts = ownVisits.reduce(0) { $0 + $1.darts.count }
        return darts == 0 ? 0 : Double(ownVisits.reduce(0) { $0 + $1.credited }) * 3 / Double(darts)
    }
    var wins: Int {
        matches.filter { match in
            guard match.countsForCompetitiveRecord, let winner = match.winner else { return false }
            return match.players[winner].id == profile?.id
        }.count
    }
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
    /// Naplánuje zápis na disk. Rychlé klikání čísel se sloučí do jednoho zápisu.
    func save() {
        guard !needsRecovery else { return }
        saveTask?.cancel()
        saveTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 250_000_000)
            guard !Task.isCancelled else { return }
            saveTask = nil
            writeToDisk()
        }
    }

    /// Okamžitý zápis — odchod do pozadí / opuštění zápasu, ať se nic neztratí.
    func flushSave() {
        saveTask?.cancel()
        saveTask = nil
        writeToDisk()
    }

    private func writeToDisk() {
        guard !needsRecovery else { return }
        do {
            try JSONEncoder().encode(data).write(to: file, options: [.atomic, .completeFileProtection])
        } catch {
            storageError = "Změny se nepodařilo uložit. \(error.localizedDescription)"
        }
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
        if data.profiles[index].accountID != nil {
            DartiqoAccount.shared.pushLocalProfile(name: clean, photoJPEG: nil, clearPhoto: false, store: self)
        }
    }
    func setPhoto(_ image: UIImage?) {
        guard let index = data.profiles.firstIndex(where: { $0.id == data.selectedProfile }) else { return }
        let jpeg = image.flatMap(Self.jpegThumb)
        data.profiles[index].photoJPEG = jpeg
        save()
        if data.profiles[index].accountID != nil {
            DartiqoAccount.shared.pushLocalProfile(name: nil, photoJPEG: jpeg, clearPhoto: image == nil, store: self)
        }
    }
    func signOut() { data.selectedProfile = nil; save() }

    /// Profil přihlášeného webového účtu. Při prvním přihlášení na tomto telefonu ho založí.
    func bindAccount(_ user: AccountUser) {
        if let existing = data.profiles.first(where: { $0.accountID == user.id }) {
            data.selectedProfile = existing.id
            applyAccount(user, photoJPEG: nil, replacePhoto: false)
        } else {
            let name = String((user.first.isEmpty ? user.username : user.first).prefix(24))
            var profile = Profile(name: name)
            profile.username = user.username
            profile.email = user.email
            profile.accountID = user.id
            data.profiles.append(profile)
            data.selectedProfile = profile.id
            flushSave()
        }
        locked = false
        Task { await DartiqoAccount.shared.refresh(into: self) }
    }

    /// Propsání údajů z webu (jméno, username, e-mail, případně fotka).
    func applyAccount(_ user: AccountUser, photoJPEG: Data?, replacePhoto: Bool) {
        guard let index = data.profiles.firstIndex(where: { $0.accountID == user.id }) else { return }
        let display = String((user.first.isEmpty ? user.username : user.first).prefix(24))
        if !display.isEmpty { data.profiles[index].name = display }
        data.profiles[index].username = user.username
        data.profiles[index].email = user.email
        if replacePhoto {
            data.profiles[index].photoJPEG = photoJPEG
        } else if data.profiles[index].photoJPEG == nil, let photoJPEG {
            data.profiles[index].photoJPEG = photoJPEG
        }
        if data.selectedProfile != data.profiles[index].id {
            data.selectedProfile = data.profiles[index].id
        }
        flushSave()
    }

    /// Jednorázově smaže lokální profily a hry z doby před účty. Nastavení zařízení zůstane.
    private func wipeLocalOnlyDataOnce() {
        let key = "dartiqo.wipedBeforeAccounts"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        for profile in data.profiles {
            commentary.deleteAll(owner: profile.id)
        }
        var fresh = StoredData()
        fresh.appearance = data.appearance
        fresh.haptics = data.haptics
        fresh.voice = data.voice
        fresh.boardCalibration = data.boardCalibration
        data = fresh
        writeToDisk()
        UserDefaults.standard.set(true, forKey: key)
    }
    func finish() {
        guard let match = activeMatch, match.finished else { return }
        if !data.matches.contains(where: { $0.id == match.id }) {
            commitMatchXP(for: match)
            var archived = match
            archived.undoStack = []
            data.matches.append(archived)
            learnGhostStyle(from: archived)
        }
        activeMatch = nil
        flushSave()
    }
    func deleteMatch(_ id: UUID) {
        guard data.matches.contains(where: { $0.id == id }) else { return }
        data.matches.removeAll { $0.id == id }
        data.matchXPAwards?.removeAll { $0.matchID == id }
        if profile?.accountID != nil {
            data.pendingMatchDeletes = (data.pendingMatchDeletes ?? []) + [id]
        }
        // Bilance dokončení zůstává. Smazání z historie ji nesmí vylepšit.
        flushSave()
    }

    /// Jednorázově započte už uložené dohrané zápasy. Zrušené z minula v historii nejsou.
    private func backfillMatchCompletion() {
        let profiles = Set(data.profiles.map(\.id))
        var changed = false
        for match in data.matches where match.finished {
            for playerID in humanProfiles(in: match, known: profiles) where noteMatchCompletion(playerID, match: match.id, outcome: .completed) {
                changed = true
            }
        }
        if changed { save() }
    }

    /// Dohrání připíše všem místním profilům v zápase. Zrušení jen tomu, kdo ho zahodil.
    private func resolveMatchCompletion(_ match: Match) {
        if match.finished {
            let profiles = Set(data.profiles.map(\.id))
            for playerID in humanProfiles(in: match, known: profiles) {
                noteMatchCompletion(playerID, match: match.id, outcome: .completed)
            }
        } else if let owner = profile?.id, match.players.contains(where: { $0.id == owner && $0.botLevel == nil }) {
            noteMatchCompletion(owner, match: match.id, outcome: .abandoned)
            if profile?.accountID != nil, !match.visits.isEmpty {
                var abandoned = match
                abandoned.undoStack = []
                data.pendingAbandoned = (data.pendingAbandoned ?? []) + [abandoned]
            }
        }
    }

    func abandonedMatchSynced(_ id: UUID) {
        data.pendingAbandoned?.removeAll { $0.id == id }
        save()
    }

    func matchDeleteSynced(_ id: UUID) {
        data.pendingMatchDeletes?.removeAll { $0 == id }
        data.uploadedMatches?.removeAll { $0 == id }
        save()
    }

    /// Verze před sledováním nahraných zápasů posílala dohrané zápasy hned po hře,
    /// takže všechny dosavadní dohrané zápasy už na webu byly.
    func trackUploadsOnce() {
        guard data.uploadedMatches == nil else { return }
        data.uploadedMatches = matches.filter(\.finished).map(\.id)
        save()
    }

    func matchesUploaded(_ ids: [UUID]) {
        let fresh = ids.filter { !(data.uploadedMatches ?? []).contains($0) }
        guard !fresh.isEmpty else { return }
        data.uploadedMatches = (data.uploadedMatches ?? []) + fresh
        save()
    }

    /// Zápasy smazané na webu zmizí i z telefonu. Na web se už nic neposílá.
    func removeMatchesDeletedOnWeb(_ ids: Set<UUID>) {
        guard !ids.isEmpty else { return }
        data.matches.removeAll { ids.contains($0.id) }
        data.matchXPAwards?.removeAll { ids.contains($0.matchID) }
        data.uploadedMatches?.removeAll { ids.contains($0) }
        flushSave()
    }

    /// Mění se, když je na web co poslat. Podle toho aplikace spouští synchronizaci zápasů.
    var matchSyncKey: String {
        "\(profile?.accountID ?? 0)|\(data.matches.count)|\(data.pendingAbandoned?.count ?? 0)|\(data.pendingMatchDeletes?.count ?? 0)"
    }

    private func humanProfiles(in match: Match, known: Set<UUID>) -> [UUID] {
        var seen: [UUID] = []
        for player in match.players where player.botLevel == nil && known.contains(player.id) && !seen.contains(player.id) {
            seen.append(player.id)
        }
        return seen
    }

    @discardableResult
    private func noteMatchCompletion(_ playerID: UUID, match matchID: UUID, outcome: MatchCompletionOutcome) -> Bool {
        guard let index = data.profiles.firstIndex(where: { $0.id == playerID }) else { return false }
        var ledger = data.profiles[index].matchCompletion ?? MatchCompletionLedger()
        guard ledger.note(matchID, outcome: outcome) else { return false }
        data.profiles[index].matchCompletion = ledger
        return true
    }

    /// Jednorázově doplní odměny ke starším dohraným zápasům. Stejné id znovu nezapíše.
    private func backfillMatchXP() {
        let before = data.matchXPAwards?.count ?? 0
        for match in data.matches where match.finished {
            commitMatchXP(for: match)
        }
        if (data.matchXPAwards?.count ?? 0) != before { save() }
    }

    /// Zapíše XP všem místním profilům v zápase. Historie v tu chvíli tenhle zápas ještě neobsahuje, nebo ho výpočet vynechá.
    private func commitMatchXP(for match: Match) {
        guard match.finished else { return }
        var awards = data.matchXPAwards ?? []
        let profiles = Set(data.profiles.map(\.id))
        for (index, player) in match.players.enumerated() {
            guard player.botLevel == nil, !match.isGhost(index), profiles.contains(player.id) else { continue }
            let key = MatchXPAward.key(owner: player.id, match: match.id)
            if awards.contains(where: { $0.id == key }) { continue }
            let breakdown = MatchRewards.award(match: match, playerID: player.id, history: data.matches)
            let award = MatchXPAward(owner: player.id, matchID: match.id, breakdown: breakdown, createdAt: match.completedAt ?? Date())
            _ = MatchXPBook.insert(award, into: &awards)
        }
        data.matchXPAwards = awards
    }
    func deleteTraining(_ id: UUID) {
        guard let owner = profile?.id else { return }
        guard data.trainingSessions?.contains(where: { $0.id == id && $0.owner == owner }) == true else { return }
        data.trainingSessions?.removeAll { $0.id == id && $0.owner == owner }
        data.xpEvents?.removeAll { $0.sessionID == id && $0.owner == owner }
        if var plan = data.trainingPlan?[owner.uuidString] {
            for index in plan.items.indices where plan.items[index].sessionID == id {
                plan.items[index].sessionID = nil
            }
            data.trainingPlan?[owner.uuidString] = plan
        }
        if data.activeTraining?[owner.uuidString]?.id == id {
            data.activeTraining?[owner.uuidString] = nil
        }
        save()
    }
    /// Uloží dohraný zápas a otevře záložku Domů bez rozehrané obrazovky zápasu.
    func returnHome() {
        finish()
        section = .home
        homeGeneration += 1
    }
    /// Výchozí hlas, nebo namluvené hlášky tohoto profilu.
    var commentator: Commentator {
        get {
            guard let key = profile?.id.uuidString else { return .system }
            return Commentator(rawValue: data.commentators?[key] ?? "") ?? .system
        }
        set {
            guard let key = profile?.id.uuidString else { return }
            if data.commentators == nil { data.commentators = [:] }
            data.commentators?[key] = newValue.rawValue
            if newValue == .custom { data.voice = true }
            save()
        }
    }

    var commentaryCount: Int {
        guard let owner = profile?.id else { return 0 }
        _ = commentaryTick
        return commentary.count(owner: owner)
    }

    func noteCommentaryChanged() { commentaryTick += 1 }

    func feedback(_ score: Int? = nil, announce: Bool = true, spoken: String? = nil, checkout: Bool = false, matchWon: Bool = false) {
        tapHaptic(.light)
        // Při hlasovém zápisu nemluvit — přehrávání bojuje s mikrofonem a AVAudioSession.
        guard announce, data.voice else { return }
        let cues = CommentaryCue.playbackOrder(score: score, spoken: spoken, checkout: checkout, matchWon: matchWon)
        if commentator == .custom, let owner = profile?.id, commentary.play(owner: owner, cues: cues) {
            if speaker.isSpeaking { speaker.stopSpeaking(at: .immediate) }
            return
        }
        let phrase = spoken ?? score.map(String.init)
        guard let phrase else { return }
        commentary.stop()
        // Fronta, ne přerušení — skóre se dočte i když šipka už ukazuje na dalšího hráče.
        let line = AVSpeechUtterance(string: phrase)
        line.voice = AVSpeechSynthesisVoice(language: "cs-CZ")
        speaker.speak(line)
    }

    /// Zvláštní moment mimo skóre kola. Pustí se jen uložená nahrávka vlastního komentátora.
    func announceMoment(_ cue: CommentaryCue, fallback: CommentaryCue? = nil) {
        guard data.voice, commentator == .custom, let owner = profile?.id else { return }
        var cues = [cue]
        if let fallback { cues.append(fallback) }
        guard commentary.play(owner: owner, cues: cues) else { return }
        if speaker.isSpeaking { speaker.stopSpeaking(at: .immediate) }
    }

    /// Krátká odezva na stisk tlačítka (čísla, double/triple, součet…).
    func tapHaptic(_ style: UIImpactFeedbackGenerator.FeedbackStyle = .light) {
        guard data.haptics else { return }
        let generator = impactGenerator(style)
        generator.impactOccurred()
        generator.prepare()
    }

    func selectionHaptic() {
        guard data.haptics else { return }
        selectionFeedback.selectionChanged()
        selectionFeedback.prepare()
    }

    private func prepareHaptics() {
        lightImpact.prepare()
        softImpact.prepare()
        mediumImpact.prepare()
        selectionFeedback.prepare()
    }

    private func impactGenerator(_ style: UIImpactFeedbackGenerator.FeedbackStyle) -> UIImpactFeedbackGenerator {
        switch style {
        case .soft: return softImpact
        case .medium, .heavy, .rigid: return mediumImpact
        default: return lightImpact
        }
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
        let removedMatchIDs = Set(data.matches.filter { $0.players.contains { $0.id == id } }.map(\.id))
        data.matches.removeAll { removedMatchIDs.contains($0.id) }
        data.activeMatches[id.uuidString] = nil
        data.pendingAbandoned?.removeAll { $0.players.contains { $0.id == id } }
        data.presets?.removeAll { $0.owner == id }; data.lastSetups?[id.uuidString] = nil
        data.profiles.removeAll { $0.id == id }; data.selectedProfile = nil
        data.trainingSessions?.removeAll { $0.owner == id }
        data.activeTraining?[id.uuidString] = nil
        data.trainingFavorites?[id.uuidString] = nil
        data.xpEvents?.removeAll { $0.owner == id }
        data.matchXPAwards?.removeAll { $0.owner == id || removedMatchIDs.contains($0.matchID) }
        data.trainingPlan?[id.uuidString] = nil
        data.achievementUnlocks?.removeAll { $0.owner == id }
        data.commentators?[id.uuidString] = nil
        commentary.deleteAll(owner: id)
        commentaryTick += 1
        flushSave()
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

    var trainingStreak: Int { TrainingStreaks.daily(sessions: trainingHistory) }
    /// Součet od startu do konce uložených tréninků, včetně přerušených.
    var trainingPlayed: TimeInterval {
        trainingHistory.reduce(0) { sum, session in
            guard let end = session.finishedAt else { return sum }
            return sum + max(0, end.timeIntervalSince(session.startedAt))
        }
    }
    var trainingWeekXP: Int {
        guard let id = profile?.id else { return 0 }
        let start = Calendar.current.dateInterval(of: .weekOfYear, for: Date())?.start ?? .distantPast
        return (data.xpEvents ?? []).filter { $0.owner == id && $0.createdAt >= start }.reduce(0) { $0 + $1.amount }
    }
    /// Přesnost z tréninků za posledních 7 dní. Bez šipek je prázdná.
    var trainingAccuracy: Double? {
        let start = Calendar.current.date(byAdding: .day, value: -6, to: Calendar.current.startOfDay(for: Date())) ?? .distantPast
        let recent = trainingHistory.filter { $0.status == .completed && ($0.finishedAt ?? $0.startedAt) >= start && ($0.result?.darts ?? 0) > 0 }
        let rows = recent.isEmpty ? trainingHistory.filter { $0.status == .completed && ($0.result?.darts ?? 0) > 0 } : recent
        guard !rows.isEmpty else { return nil }
        return rows.reduce(0) { $0 + ($1.result?.accuracy ?? 0) } / Double(rows.count)
    }
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
    /// Rozklad XP za trénink (i před uložením). Už zapsaná session bere počet dokončení bez sebe.
    func trainingXP(for session: TrainingSession) -> TrainingXPBreakdown {
        guard let owner = profile?.id, session.owner == owner, session.status == .completed, session.result != nil else {
            return TrainingXPBreakdown()
        }
        let calendar = Calendar.current
        let day = calendar.startOfDay(for: session.finishedAt ?? Date())
        let prior = (data.trainingSessions ?? []).filter {
            $0.id != session.id &&
            $0.owner == owner && $0.definitionID == session.definitionID && $0.status == .completed &&
            calendar.startOfDay(for: $0.finishedAt ?? $0.startedAt) == day
        }.count
        return trainingXP(for: session, priorCompletionsToday: prior)
    }

    private func trainingXP(for session: TrainingSession, priorCompletionsToday: Int) -> TrainingXPBreakdown {
        guard let definition = TrainingCatalog.find(session.definitionID), let result = session.result else {
            return TrainingXPBreakdown()
        }
        // Bez této session — jinak by po uložení „nový rekord“ zmizel.
        let priorBest = trainingHistory
            .filter { $0.id != session.id }
            .compactMap { item -> TrainingResult? in
                guard item.definitionID == session.definitionID, item.status == .completed, item.result?.success == true else { return nil }
                return item.result
            }
            .max { lhs, rhs in
                if lhs.higherIsBetter { return lhs.score < rhs.score }
                return lhs.score > rhs.score
            }
        let record = result.success && isBetterTraining(result, than: priorBest)
        return TrainingRewards.award(
            definition: definition,
            config: session.config,
            result: result,
            completionsToday: priorCompletionsToday,
            isRecord: record,
            isDaily: session.config.isDaily,
            isWeekly: session.config.isWeekly
        )
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
        let amount = trainingXP(for: session, priorCompletionsToday: prior).total
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
        flushSave()
        return amount
    }
    func abandonTraining(_ session: TrainingSession) {
        guard let owner = profile?.id.uuidString else { return }
        if data.activeTraining?[owner]?.id == session.id { data.activeTraining?[owner] = nil; flushSave() }
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
