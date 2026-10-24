import Foundation
import Security

/// Adresa webu Dartiqo. Uživatel ji může změnit v Nastavení → Dartiqo účet.
enum ServerConfig {
#if DEBUG
    /// Simulátor vidí XAMPP na stejném Macu. Fyzický iPhone potřebuje IP adresu Macu.
    static let defaultURL = "http://localhost/dartiqo"
#else
    static let defaultURL = "https://dartiqo.cz"
#endif

    /// Ořízne mezery a koncové lomítko. Bez http(s) a hostitele vrátí `nil`.
    static func normalized(_ raw: String) -> String? {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        while text.hasSuffix("/") { text.removeLast() }
        guard let url = URL(string: text), let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https", url.host?.isEmpty == false else { return nil }
        return text
    }
}

struct AccountUser: Codable, Equatable {
    var id: Int
    var username: String
    var email: String
    var first: String
    var last: String
    /// Relativní cesta na serveru, např. /uploads/avatars/….jpg?v=3
    var photo: String?
    var profileRevision: Int

    var fullName: String { "\(first) \(last)".trimmingCharacters(in: .whitespaces) }

    enum CodingKeys: String, CodingKey {
        case id, username, email, first, last, photo, profileRevision
    }

    init(id: Int, username: String, email: String, first: String, last: String, photo: String? = nil, profileRevision: Int = 1) {
        self.id = id
        self.username = username
        self.email = email
        self.first = first
        self.last = last
        self.photo = photo
        self.profileRevision = profileRevision
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        username = try c.decode(String.self, forKey: .username)
        email = try c.decode(String.self, forKey: .email)
        first = try c.decode(String.self, forKey: .first)
        last = try c.decode(String.self, forKey: .last)
        photo = try c.decodeIfPresent(String.self, forKey: .photo)
        profileRevision = try c.decodeIfPresent(Int.self, forKey: .profileRevision) ?? 1
    }
}

/// Hráč z hledání na serveru. E-mail se do aplikace neposílá.
struct DirectoryPerson: Codable, Identifiable, Equatable {
    var id: Int
    var username: String
    var first: String
    var last: String
    var photo: String?
    /// none, outgoing, incoming, accepted nebo declined. Starší odpověď klíč nemá.
    var relation: String?

    var fullName: String { "\(first) \(last)".trimmingCharacters(in: .whitespaces) }
}

struct FriendRecord: Codable, Equatable {
    struct Career: Codable, Equatable {
        var played: Int
        var wins: Int
        var losses: Int
        var draws: Int
        var average: Double?

        var winRate: Int? {
            played == 0 ? nil : Int((Double(wins) / Double(played) * 100).rounded())
        }
    }

    struct Mutual: Codable, Equatable {
        var wins: Int
        var losses: Int
        var draws: Int

        var played: Int { wins + losses + draws }
    }

    struct Game: Codable, Equatable, Identifiable {
        var id: String
        var when: String
        var mode: String
        var title: String
        var score: String
        var result: String
        var label: String
        var mine: Bool
        var myAverage: Double?
        var theirAverage: Double?
    }

    var career: Career
    var mutual: Mutual
    var myAverage: Double?
    var theirAverage: Double?
    var standing: String
    var games: [Game]
}

struct FriendSummary: Codable, Equatable {
    var career: FriendRecord.Career
    var mutual: FriendRecord.Mutual
}

struct FriendLink: Codable, Identifiable, Equatable {
    var id: Int
    var status: String
    var user: DirectoryPerson
    /// Bilance a průměr. Starší odpověď klíč nemá a žádosti ho nenesou.
    var summary: FriendSummary?
}

struct FriendBook: Equatable {
    var friends: [FriendLink]
    var incoming: [FriendLink]
    var outgoing: [FriendLink]

    static let empty = FriendBook(friends: [], incoming: [], outgoing: [])
}

enum APIError: LocalizedError {
    case badServer
    case unauthorized(String)
    case server(String)
    case network(String)

    var errorDescription: String? {
        switch self {
        case .badServer: return "Zadej adresu serveru, třeba http://localhost/dartiqo."
        case .unauthorized(let message), .server(let message): return message
        case .network(let message): return "Server není dostupný. \(message)"
        }
    }
}

enum SocialProvider: String {
    case apple, google

    var title: String { self == .apple ? "Apple" : "Google" }
}

struct DartiqoAPI {
    var baseURL: URL
    var token: String?

    private struct Response: Decodable {
        var token: String?
        var user: AccountUser?
        var message: String?
        var ids: [String]?
        var people: [DirectoryPerson]?
        var friends: [FriendLink]?
        var incoming: [FriendLink]?
        var outgoing: [FriendLink]?
        var friendship: FriendLink?
        var relation: String?
        var record: FriendRecord?
    }

    func login(identity: String, password: String, device: String) async throws -> (token: String, user: AccountUser) {
        let body = try JSONEncoder().encode(["identity": identity, "password": password, "device": device])
        let response = try await send("api/v1/auth/login", body: body)
        guard let token = response.token, let user = response.user else { throw APIError.server("Server vrátil neúplnou odpověď.") }
        return (token, user)
    }

    func login(with provider: SocialProvider, idToken: String, name: String, device: String) async throws -> (token: String, user: AccountUser) {
        let body = try JSONEncoder().encode(["idToken": idToken, "name": name, "device": device])
        let response = try await send("api/v1/auth/social/\(provider.rawValue)", body: body)
        guard let token = response.token, let user = response.user else { throw APIError.server("Server vrátil neúplnou odpověď.") }
        return (token, user)
    }

    func me() async throws -> AccountUser {
        guard let user = try await send("api/v1/me", method: "GET").user else { throw APIError.server("Server vrátil neúplnou odpověď.") }
        return user
    }

    enum ProfilePhotoUpdate {
        case unchanged
        case clear
        case dataURL(String)
    }

    /// Uloží profil na web. Fotku posílej jen když se opravdu mění.
    func updateProfile(
        first: String? = nil,
        last: String? = nil,
        username: String? = nil,
        email: String? = nil,
        photo: ProfilePhotoUpdate = .unchanged
    ) async throws -> AccountUser {
        var body: [String: Any] = [:]
        if let first { body["first"] = first }
        if let last { body["last"] = last }
        if let username { body["username"] = username }
        if let email { body["email"] = email }
        switch photo {
        case .unchanged: break
        case .clear: body["photo"] = NSNull()
        case .dataURL(let value): body["photo"] = value
        }
        let data = try JSONSerialization.data(withJSONObject: body)
        guard let user = try await send("api/v1/me", body: data).user else { throw APIError.server("Server vrátil neúplnou odpověď.") }
        return user
    }

    func logout() async {
        _ = try? await send("api/v1/auth/logout", body: Data("{}".utf8))
    }

    func matchIDs() async throws -> [String] {
        try await send("api/v1/matches", method: "GET").ids ?? []
    }

    func uploadMatch(id: UUID, body: Data) async throws {
        _ = try await send("api/v1/matches/\(id.uuidString.lowercased())", body: body)
    }

    func deleteMatch(id: UUID) async throws {
        _ = try await send("api/v1/matches/\(id.uuidString.lowercased())/delete", body: Data("{}".utf8))
    }

    func pushLiveMatch(id: UUID, body: Data) async throws {
        _ = try await send("api/v1/live-matches/\(id.uuidString.lowercased())", body: body)
    }

    func friendRecord(_ id: Int) async throws -> FriendRecord {
        guard let record = try await send("api/v1/friends/\(id)", method: "GET").record else {
            throw APIError.server("Server vrátil neúplnou odpověď.")
        }
        return record
    }

    func friendBook() async throws -> FriendBook {
        let response = try await send("api/v1/friends", method: "GET")
        return FriendBook(friends: response.friends ?? [], incoming: response.incoming ?? [], outgoing: response.outgoing ?? [])
    }

    /// Pošle žádost. Když už žádost přišla od něj, rovnou ji přijme.
    func requestFriend(userId: Int) async throws -> (link: FriendLink, relation: String) {
        let body = try JSONSerialization.data(withJSONObject: ["userId": userId])
        let response = try await send("api/v1/friends", body: body)
        guard let link = response.friendship else { throw APIError.server("Server vrátil neúplnou odpověď.") }
        return (link, response.relation ?? link.status)
    }

    func acceptFriend(_ id: Int) async throws -> FriendLink {
        guard let link = try await send("api/v1/friends/\(id)/accept", body: Data("{}".utf8)).friendship else {
            throw APIError.server("Server vrátil neúplnou odpověď.")
        }
        return link
    }

    func declineFriend(_ id: Int) async throws {
        _ = try await send("api/v1/friends/\(id)/decline", body: Data("{}".utf8))
    }

    func cancelFriend(_ id: Int) async throws {
        _ = try await send("api/v1/friends/\(id)/cancel", body: Data("{}".utf8))
    }

    func removeFriend(_ id: Int) async throws {
        _ = try await send("api/v1/friends/\(id)/delete", body: Data("{}".utf8))
    }

    /// Registrovaní hráči podle jména, username, nebo přesného e-mailu.
    func searchPeople(query: String) async throws -> [DirectoryPerson] {
        try await send("api/v1/people", method: "GET", query: [URLQueryItem(name: "q", value: query)]).people ?? []
    }

    func downloadImage(_ path: String?) async -> Data? {
        guard let path, !path.isEmpty else { return nil }
        let absolute: URL?
        if path.hasPrefix("http://") || path.hasPrefix("https://") {
            absolute = URL(string: path)
        } else {
            let root = baseURL.absoluteString.hasSuffix("/") ? baseURL.absoluteString : baseURL.absoluteString + "/"
            let relative = path.hasPrefix("/") ? String(path.dropFirst()) : path
            absolute = URL(string: relative, relativeTo: URL(string: root))?.absoluteURL
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

    private func send(_ path: String, method: String = "POST", body: Data? = nil, query: [URLQueryItem] = []) async throws -> Response {
        guard var components = URLComponents(url: baseURL.appending(path: path), resolvingAgainstBaseURL: false) else {
            throw APIError.badServer
        }
        if !query.isEmpty { components.queryItems = query }
        guard let url = components.url else { throw APIError.badServer }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 10
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        if let token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw APIError.network(error.localizedDescription)
        }
        let decoded = (try? JSONDecoder().decode(Response.self, from: data)) ?? Response()
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if status == 401 {
            throw APIError.unauthorized(decoded.message ?? "Přihlášení vypršelo.")
        }
        guard (200..<300).contains(status) else {
            throw APIError.server(decoded.message ?? "Server odpověděl chybou \(status).")
        }
        return decoded
    }
}

/// Token patří do klíčenky, ne do UserDefaults ani exportu dat.
enum TokenStore {
    private static let service = "app.Dartiqo.api"
    private static let account = "token"

    static func read() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func save(_ token: String?) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
        guard let token else { return }
        var item = query
        item[kSecValueData as String] = Data(token.utf8)
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(item as CFDictionary, nil)
    }
}
