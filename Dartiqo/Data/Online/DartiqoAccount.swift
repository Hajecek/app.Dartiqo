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
    }

    @Published private(set) var user: AccountUser?
    @Published private(set) var serverURL: String
    @Published var liveSharing: Bool {
        didSet { defaults.set(liveSharing, forKey: Keys.liveSharing) }
    }
    private var token: String?
    private let defaults = UserDefaults.standard
    private lazy var live = LiveMatchSync(account: self)

    private init() {
        serverURL = defaults.string(forKey: Keys.server).flatMap(ServerConfig.normalized) ?? ServerConfig.defaultURL
        liveSharing = defaults.object(forKey: Keys.liveSharing) as? Bool ?? true
        token = TokenStore.read()
        if token != nil, let data = defaults.data(forKey: Keys.user) {
            user = try? JSONDecoder().decode(AccountUser.self, from: data)
        }
    }

    var isSignedIn: Bool { token != nil && user != nil }

    var api: DartiqoAPI? {
        guard let token, let base = URL(string: serverURL) else { return nil }
        return DartiqoAPI(baseURL: base, token: token)
    }

    func login(server: String, identity: String, password: String) async throws {
        guard let server = ServerConfig.normalized(server), let base = URL(string: server) else { throw APIError.badServer }
        let result = try await DartiqoAPI(baseURL: base, token: nil)
            .login(identity: identity, password: password, device: UIDevice.current.name)
        serverURL = server
        defaults.set(server, forKey: Keys.server)
        token = result.token
        TokenStore.save(result.token)
        store(result.user)
    }

    func logout() async {
        let api = api
        clear()
        await api?.logout()
    }

    /// Ověří token po spuštění a obnoví jméno, kdyby se na webu změnilo.
    func refresh() async {
        guard let api else { return }
        do {
            store(try await api.me())
        } catch APIError.unauthorized {
            clear()
        } catch {}
    }

    func syncLive(_ match: Match?) {
        live.update(match)
    }

    func handleUnauthorized() {
        clear()
    }

    private func store(_ user: AccountUser) {
        self.user = user
        defaults.set(try? JSONEncoder().encode(user), forKey: Keys.user)
    }

    private func clear() {
        token = nil
        user = nil
        TokenStore.save(nil)
        defaults.removeObject(forKey: Keys.user)
    }
}
