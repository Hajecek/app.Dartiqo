import Foundation
import UIKit
import Combine

/// Přihlášení k webovému účtu Dartiqo. Lokální hráčské profily zůstávají, jak jsou.
@MainActor final class DartiqoAccount: ObservableObject {
    static let shared = DartiqoAccount()

    private enum Keys {
        static let server = "dartiqo.server"
        static let user = "dartiqo.user"
        static let liveSharing = "dartiqo.liveSharing"
        static let guest = "dartiqo.guest"
    }

    @Published private(set) var user: AccountUser?
    /// Hraje se bez účtu na místním profilu. Nic se neodesílá na web.
    @Published private(set) var isGuest = false
    @Published private(set) var serverURL: String
    @Published var liveSharing: Bool {
        didSet { defaults.set(liveSharing, forKey: Keys.liveSharing) }
    }
    private var token: String?
    private let defaults = UserDefaults.standard
    private lazy var live = LiveMatchSync(account: self)
    private lazy var matches = MatchSync(account: self)
    /// Poslední revision, kterou jsme propsali do AppStore (brání smyčce push↔pull).
    private var appliedRevision = 0
    private var watchTask: Task<Void, Never>?
    private var pushTask: Task<Void, Never>?
    private var uploadedPushToken: String?

    private init() {
        serverURL = defaults.string(forKey: Keys.server).flatMap(ServerConfig.normalized) ?? ServerConfig.defaultURL
        liveSharing = defaults.object(forKey: Keys.liveSharing) as? Bool ?? true
        token = TokenStore.read()
        if token != nil, let data = defaults.data(forKey: Keys.user) {
            user = try? JSONDecoder().decode(AccountUser.self, from: data)
            appliedRevision = user?.profileRevision ?? 0
        }
        isGuest = user == nil && defaults.bool(forKey: Keys.guest)
    }

    var isSignedIn: Bool { token != nil && user != nil }

    func continueAsGuest() {
        isGuest = true
        defaults.set(true, forKey: Keys.guest)
    }

    /// Vrátí hosta na přihlašovací obrazovku. Místní profil i jeho hry zůstanou v telefonu.
    func leaveGuest() {
        isGuest = false
        defaults.removeObject(forKey: Keys.guest)
    }

    var api: DartiqoAPI? {
        guard let token, let base = URL(string: serverURL) else { return nil }
        return DartiqoAPI(baseURL: base, token: token)
    }

    func login(server: String, identity: String, password: String) async throws {
        guard let server = ServerConfig.normalized(server), let base = URL(string: server) else { throw APIError.badServer }
        let result = try await DartiqoAPI(baseURL: base, token: nil)
            .login(identity: identity, password: password, device: UIDevice.current.name)
        signIn(server: server, token: result.token, user: result.user)
    }

    func login(server: String, provider: SocialProvider, idToken: String, name: String) async throws {
        guard let server = ServerConfig.normalized(server), let base = URL(string: server) else { throw APIError.badServer }
        let result = try await DartiqoAPI(baseURL: base, token: nil)
            .login(with: provider, idToken: idToken, name: name, device: UIDevice.current.name)
        signIn(server: server, token: result.token, user: result.user)
    }

    private func signIn(server: String, token: String, user: AccountUser) {
        serverURL = server
        defaults.set(server, forKey: Keys.server)
        self.token = token
        TokenStore.save(token)
        persistUser(user)
        appliedRevision = 0
        leaveGuest()
    }

    func logout() async {
        watchTask?.cancel()
        watchTask = nil
        pushTask?.cancel()
        let api = api
        clear()
        await api?.logout()
    }

    /// Pošle FCM token na server. Stejný token se neposílá znovu, dokud se nezmění nebo se uživatel odhlásí.
    func uploadPushToken(_ token: String) async {
        guard isSignedIn, !token.isEmpty, token != uploadedPushToken, let api else { return }
        #if DEBUG
        let environment = "development"
        #else
        let environment = "production"
        #endif
        do {
            try await api.registerPush(token: token, environment: environment)
            uploadedPushToken = token
        } catch APIError.unauthorized {
            clear()
        } catch {}
    }

    /// Ověří token a stáhne profil včetně fotky z webu.
    func refresh(into appStore: AppStore? = nil) async {
        guard let api else { return }
        do {
            let remote = try await api.me()
            await applyRemote(remote, into: appStore)
        } catch APIError.unauthorized {
            clear()
        } catch {}
    }

    /// Průběžné stahování změn z webu, dokud je aplikace v popředí.
    func startWatching(store: AppStore) {
        watchTask?.cancel()
        watchTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh(into: store)
                try? await Task.sleep(nanoseconds: 2_500_000_000)
            }
        }
    }

    func stopWatching() {
        watchTask?.cancel()
        watchTask = nil
    }

    /// Odešle jméno / fotku na web (debounce, ať rychlé klepnutí nebombarduje API).
    func pushLocalProfile(name: String?, photoJPEG: Data?, clearPhoto: Bool, store: AppStore) {
        pushTask?.cancel()
        pushTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 350_000_000)
            guard !Task.isCancelled else { return }
            await self?.sendProfile(name: name, photoJPEG: photoJPEG, clearPhoto: clearPhoto, appStore: store)
        }
    }

    private func sendProfile(name: String?, photoJPEG: Data?, clearPhoto: Bool, appStore: AppStore) async {
        guard let api else { return }
        var photo: DartiqoAPI.ProfilePhotoUpdate = .unchanged
        if clearPhoto {
            photo = .clear
        } else if let photoJPEG {
            photo = .dataURL("data:image/jpeg;base64,\(photoJPEG.base64EncodedString())")
        }
        do {
            let remote = try await api.updateProfile(first: name, photo: photo)
            await applyRemote(remote, into: appStore, forcePhoto: photoJPEG, cleared: clearPhoto)
        } catch APIError.unauthorized {
            clear()
        } catch {
            // Lokální změna zůstane; při příštím refreshi se případně srovná.
        }
    }

    private func applyRemote(_ remote: AccountUser, into appStore: AppStore?, forcePhoto: Data? = nil, cleared: Bool = false) async {
        let revisionChanged = remote.profileRevision != appliedRevision
        persistUser(remote)
        guard let appStore else { return }
        if !revisionChanged && forcePhoto == nil && !cleared { return }

        let jpeg: Data?
        let replacePhoto: Bool
        if cleared {
            jpeg = nil
            replacePhoto = true
        } else if let forcePhoto {
            jpeg = forcePhoto
            replacePhoto = true
        } else if revisionChanged {
            if remote.photo == nil {
                jpeg = nil
                replacePhoto = true
            } else if let downloaded = await downloadPhoto(remote.photo) {
                jpeg = downloaded
                replacePhoto = true
            } else {
                jpeg = nil
                replacePhoto = false
            }
        } else {
            jpeg = nil
            replacePhoto = false
        }
        appStore.applyAccount(remote, photoJPEG: jpeg, replacePhoto: replacePhoto)
        appliedRevision = remote.profileRevision
    }

    private func downloadPhoto(_ path: String?) async -> Data? {
        guard let path, !path.isEmpty else { return nil }
        let absolute: URL?
        if path.hasPrefix("http://") || path.hasPrefix("https://") {
            absolute = URL(string: path)
        } else {
            let root = serverURL.hasSuffix("/") ? serverURL : serverURL + "/"
            absolute = URL(string: path.hasPrefix("/") ? String(path.dropFirst()) : path, relativeTo: URL(string: root))?.absoluteURL
        }
        guard let absolute else { return nil }
        var request = URLRequest(url: absolute)
        request.timeoutInterval = 12
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200, !data.isEmpty else { return nil }
            return data
        } catch {
            return nil
        }
    }

    /// Odešle na web dohrané a zrušené zápasy, které tam ještě nejsou, a provede čekající mazání.
    func syncMatches(_ store: AppStore) async {
        await matches.run(store)
    }

    func syncLive(_ match: Match?, store: AppStore) {
        let photos = match.map { livePhotos($0, store: store) } ?? []
        live.update(match, photos: photos, ownerID: store.profile?.id)
    }

    /// Stejné portréty jako na hřišti. Bot zůstane bez fotky, ghost bere portrét profilu.
    private func livePhotos(_ match: Match, store: AppStore) -> [Data?] {
        match.players.indices.map { index in
            let player = match.players[index]
            if player.botLevel != nil { return nil }
            if match.isGhost(index) { return store.profile?.photoJPEG }
            return store.photo(for: player.id)
        }
    }

    func handleUnauthorized() {
        clear()
    }

    private func persistUser(_ user: AccountUser) {
        self.user = user
        defaults.set(try? JSONEncoder().encode(user), forKey: Keys.user)
    }

    private func clear() {
        token = nil
        user = nil
        appliedRevision = 0
        uploadedPushToken = nil
        TokenStore.save(nil)
        defaults.removeObject(forKey: Keys.user)
    }
}
