import Foundation

enum PointGuardError: LocalizedError {
    case badURL
    case http(Int, String)
    case decoding(String)

    var errorDescription: String? {
        switch self {
        case .badURL: return "Invalid server URL"
        case .http(let code, let body):
            return "Server error \(code)" + (Self.readableDetail(from: body).map { ": \($0)" } ?? "")
        case .decoding(let detail): return "Unexpected response: \(detail)"
        }
    }

    /// point-guard's error shapes are a plain `{error}` (see server/src/index.ts)
    /// but this stays defensive the same way barry-iphone's client is,
    /// in case a route ever adds RFC 7807 detail/title fields.
    private static func readableDetail(from body: String) -> String? {
        guard let data = body.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return body.isEmpty ? nil : String(body.prefix(200))
        }
        if let detail = obj["detail"] as? String, !detail.isEmpty { return detail }
        if let error = obj["error"] as? String, !error.isEmpty { return error }
        if let title = obj["title"] as? String, !title.isEmpty { return title }
        return body.isEmpty ? nil : String(body.prefix(200))
    }
}

/// REST client for point-guard (bags/point-guard, port 3868). REST-poll
/// only — point-guard does expose a WS stream, but this app doesn't use it;
/// there is no realtime surface here, matching the smaller scope of what
/// this app needs from the service.
struct PointGuardClient {
    var config: ServerConfig
    var urlSession: URLSession = .shared

    // MARK: Requests

    private func get<T: Decodable>(_ type: T.Type, path: String, query: [URLQueryItem] = []) async throws -> T {
        guard let req = config.request(path: path, query: query) else { throw PointGuardError.badURL }
        return try await run(type, req)
    }

    private func post<T: Decodable>(_ type: T.Type, path: String, body: [String: Any]) async throws -> T {
        guard var req = config.request(path: path) else { throw PointGuardError.badURL }
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        return try await run(type, req)
    }

    private func run<T: Decodable>(_ type: T.Type, _ req: URLRequest) async throws -> T {
        let (data, response) = try await urlSession.data(for: req)
        guard let http = response as? HTTPURLResponse else { throw PointGuardError.decoding("no response") }
        guard (200..<300).contains(http.statusCode) else {
            throw PointGuardError.http(http.statusCode, String(data: data, encoding: .utf8) ?? "")
        }
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw PointGuardError.decoding(String(describing: error))
        }
    }

    // MARK: API

    /// No auth required — a health probe that itself needs a secret can't
    /// tell "server down" from "wrong secret" apart.
    func health() async throws -> Bool {
        struct Health: Decodable { let ok: Bool }
        return try await get(Health.self, path: "/health").ok
    }

    /// GET /debrief. A 503 surfaces as `.http(503, _)` and MUST be handled
    /// separately by the caller: the service returns it deliberately so that
    /// "no tick has run yet" stays distinguishable from "there are no
    /// sessions". Rendered as a generic error, the UI would blame a
    /// connection it had just used successfully.
    func debrief() async throws -> DebriefResponse {
        try await get(DebriefResponse.self, path: "/debrief")
    }

    func book() async throws -> BookResponse {
        try await get(BookResponse.self, path: "/book")
    }

    /// The Heartbeat pattern: one message in, one fresh-context reply out.
    /// No context carried between calls — this is NOT a conversation turn.
    func sendMessage(content: String) async throws -> MessageReply {
        try await post(MessageReply.self, path: "/message", body: ["content": content])
    }

    func messageHistory(limit: Int = 50) async throws -> MessageHistoryResponse {
        try await get(MessageHistoryResponse.self, path: "/message/history", query: [
            URLQueryItem(name: "limit", value: String(limit)),
        ])
    }
}
