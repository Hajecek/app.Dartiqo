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

    var fullName: String { "\(first) \(last)".trimmingCharacters(in: .whitespaces) }
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

struct DartiqoAPI {
    var baseURL: URL
    var token: String?

    private struct Response: Decodable {
        var token: String?
        var user: AccountUser?
        var message: String?
    }

    func login(identity: String, password: String, device: String) async throws -> (token: String, user: AccountUser) {
        let body = try JSONEncoder().encode(["identity": identity, "password": password, "device": device])
        let response = try await send("api/v1/auth/login", body: body)
        guard let token = response.token, let user = response.user else { throw APIError.server("Server vrátil neúplnou odpověď.") }
        return (token, user)
    }

    func me() async throws -> AccountUser {
        guard let user = try await send("api/v1/me", method: "GET").user else { throw APIError.server("Server vrátil neúplnou odpověď.") }
        return user
    }

    func logout() async {
        _ = try? await send("api/v1/auth/logout", body: Data("{}".utf8))
    }

    func pushLiveMatch(id: UUID, body: Data) async throws {
        _ = try await send("api/v1/live-matches/\(id.uuidString.lowercased())", body: body)
    }

    private func send(_ path: String, method: String = "POST", body: Data? = nil) async throws -> Response {
        var request = URLRequest(url: baseURL.appending(path: path))
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
