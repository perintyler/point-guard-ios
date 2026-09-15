import Foundation

/// Where the app talks to point-guard, and how it authenticates.
///
/// Reaching the Mac:
///  - Simulator: straight to the loopback port point-guard listens on
///    (127.0.0.1 only — point-guard binds loopback-only, so this only works
///    when the simulator runs on the same Mac as the service).
///  - Device: over Tailscale to the Mac, with a Host header so the Mac's
///    reverse proxy can route the request — same convention barry-iphone
///    uses for its own server.
struct ServerConfig: Equatable {
    var baseURL: String
    var hostHeader: String
    var secret: String

    static let defaultsKeyBase = "server.baseURL"
    static let defaultsKeyHost = "server.hostHeader"
    static let keychainSecretKey = "rocks.barry.pointguard.secret"

    static var platformDefault: ServerConfig {
        #if targetEnvironment(simulator)
        ServerConfig(baseURL: "http://127.0.0.1:3868", hostHeader: "", secret: "")
        #else
        ServerConfig(baseURL: "http://100.101.38.91:3868", hostHeader: "barry.lan", secret: "")
        #endif
    }

    static func load() -> ServerConfig {
        // UI-test hook: `-pointGuardBaseURL <url>` overrides everything else
        // and skips the keychain, mirroring barry-iphone's own test hook.
        // `-pointGuardSecret <secret>` is an optional companion flag so a UI
        // test (or manual simulator verification) can exercise the
        // authenticated path without touching the real keychain.
        let args = ProcessInfo.processInfo.arguments
        if let flagIndex = args.firstIndex(of: "-pointGuardBaseURL"), args.count > flagIndex + 1 {
            var secret = ""
            if let secretIndex = args.firstIndex(of: "-pointGuardSecret"), args.count > secretIndex + 1 {
                secret = args[secretIndex + 1]
            }
            return ServerConfig(baseURL: args[flagIndex + 1], hostHeader: "", secret: secret)
        }

        let d = UserDefaults.standard
        var c = platformDefault
        if let base = d.string(forKey: defaultsKeyBase), !base.isEmpty { c.baseURL = base }
        if let host = d.string(forKey: defaultsKeyHost) { c.hostHeader = host }
        c.secret = Keychain.read(key: keychainSecretKey) ?? ""
        return c
    }

    func save() {
        let d = UserDefaults.standard
        d.set(baseURL, forKey: Self.defaultsKeyBase)
        d.set(hostHeader, forKey: Self.defaultsKeyHost)
        if secret.isEmpty {
            Keychain.delete(key: Self.keychainSecretKey)
        } else {
            Keychain.write(key: Self.keychainSecretKey, value: secret)
        }
    }

    /// Build a request for an API path, applying host header and auth.
    func request(path: String, query: [URLQueryItem] = []) -> URLRequest? {
        guard var components = URLComponents(string: baseURL) else { return nil }
        components.path = path
        if !query.isEmpty { components.queryItems = query }
        guard let url = components.url else { return nil }
        var req = URLRequest(url: url)
        apply(to: &req)
        return req
    }

    /// point-guard's real auth middleware accepts EITHER `authorization:
    /// Bearer <secret>` OR the `x-barry-secret` header barry-iphone's main
    /// API uses — this picks `authorization: Bearer`, the more standard
    /// header for a bearer token.
    func apply(to req: inout URLRequest) {
        if !hostHeader.isEmpty { req.setValue(hostHeader, forHTTPHeaderField: "Host") }
        if !secret.isEmpty { req.setValue("Bearer \(secret)", forHTTPHeaderField: "authorization") }
    }
}

/// Minimal keychain wrapper for the one secret the app stores.
enum Keychain {
    static func read(key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func write(key: String, value: String) {
        delete(key: key)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecValueData as String: Data(value.utf8),
        ]
        SecItemAdd(query as CFDictionary, nil)
    }

    static func delete(key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
        ]
        SecItemDelete(query as CFDictionary)
    }
}
