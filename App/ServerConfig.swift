import Foundation

/// Where the app talks to point-guard, and how it authenticates.
///
///  - Simulator: straight to the loopback port point-guard listens on. That
///    works only because the simulator runs on the same Mac as the service.
///  - Device: HTTPS over the personal tailnet to a userspace `tailscaled`
///    sidecar, which terminates TLS and proxies to point-guard on
///    `127.0.0.1:3868`.
///
/// point-guard binds loopback ONLY — which is why the old device default,
/// `http://100.101.38.91:3868`, could never have worked. It named a raw
/// service port on the WORK tailnet: nothing listens on :3868 across any
/// tailnet, and the phone is not on that tailnet either. There was no device
/// path at all; the `:8447` serve endpoint is what creates one.
///
/// The device host is a real tailnet DNS name with a real Let's Encrypt
/// certificate, so there is no certificate prompt and no pinning to do. The
/// endpoint proxies straight to point-guard, so there is no Host header to
/// select a site block with.
///
/// The secret is REQUIRED on the device path — every route but `/health`
/// rejects an unauthenticated caller with 403, even from loopback.
struct ServerConfig: Equatable {
    var baseURL: String
    var secret: String

    static let defaultsKeyBase = "server.baseURL"
    static let keychainSecretKey = "rocks.barry.pointguard.secret"

    static let defaultDeviceURL = "https://barry-mac.tail5cb2f2.ts.net:8447"
    static let simulatorURL = "http://127.0.0.1:3868"

    /// The one route point-guard answers without a secret. The probe uses it to
    /// tell "the server is not there" apart from "the secret is wrong".
    static let healthPath = "/health"

    static var platformDefault: ServerConfig {
        #if targetEnvironment(simulator)
        ServerConfig(baseURL: simulatorURL, secret: "")
        #else
        ServerConfig(baseURL: defaultDeviceURL, secret: "")
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
            return ServerConfig(baseURL: args[flagIndex + 1], secret: secret)
        }

        let d = UserDefaults.standard
        var c = platformDefault
        if let base = d.string(forKey: defaultsKeyBase), !base.isEmpty { c.baseURL = base }
        c.secret = Keychain.read(key: keychainSecretKey) ?? ""
        return c
    }

    func save() {
        let d = UserDefaults.standard
        d.set(baseURL, forKey: Self.defaultsKeyBase)
        if secret.isEmpty {
            Keychain.delete(key: Self.keychainSecretKey)
        } else {
            Keychain.write(key: Self.keychainSecretKey, value: secret)
        }
    }

    /// Build a request for an API path, applying auth.
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
