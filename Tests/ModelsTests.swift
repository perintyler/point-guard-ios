import XCTest
@testable import PointGuard

/// Decoding tests pinned to REAL payload shapes captured from the live
/// point-guard service (127.0.0.1:3868) on 2026-09-15. If these fail after
/// an API change, the contract moved — update the models AND the fixtures
/// together.
final class ModelsTests: XCTestCase {

    func testDecodesBookPayload() throws {
        let json = """
        {"sessions":[{"sessionId":"zkwFFBjLNzbn_D0F1qFQ8","repo":"/Users/tyler/repos/barry/.git",
        "branch":null,"worktree":"/Users/tyler/repos/barry","lastActivityAt":1789504864907,
        "status":"ok","flaggedReason":null,"mergeTreeCheckedAt":1789504839982,
        "updatedAt":1789505020012}]}
        """
        let response = try JSONDecoder().decode(BookResponse.self, from: Data(json.utf8))
        XCTAssertEqual(response.sessions.count, 1)
        let s = response.sessions[0]
        XCTAssertEqual(s.sessionId, "zkwFFBjLNzbn_D0F1qFQ8")
        XCTAssertEqual(s.repoName, "barry")
        XCTAssertNil(s.branch)
        XCTAssertEqual(s.status, "ok")
        XCTAssertNil(s.flaggedReason)
        XCTAssertNotNil(s.mergeTreeCheckedAt)
    }

    /// Regression: repo is a git-common-dir path ending in ".git" — repoName
    /// must strip that suffix and use the PARENT directory's basename, not
    /// just the last path component (which would be ".git" itself).
    func testRepoNameStripsGitSuffix() throws {
        let session = try decodeSession(repo: "/Users/tyler/vantage/scout/.git")
        XCTAssertEqual(session.repoName, "scout")
    }

    func testRepoNameNilWhenRepoIsNil() throws {
        let session = try decodeSession(repo: nil)
        XCTAssertNil(session.repoName)
    }

    /// `repo: null` / `worktree: null` means the session has no git working
    /// directory at all (a non-code task) — not an error, and repoName must
    /// degrade to nil rather than crash or fabricate a name.
    func testDecodesSessionWithNoRepo() throws {
        let json = """
        {"sessionId":"abc123","repo":null,"branch":null,"worktree":null,
        "lastActivityAt":null,"status":"ok","flaggedReason":null,
        "mergeTreeCheckedAt":null,"updatedAt":1789505020012}
        """
        let session = try JSONDecoder().decode(BookSession.self, from: Data(json.utf8))
        XCTAssertNil(session.repo)
        XCTAssertNil(session.worktree)
        XCTAssertNil(session.repoName)
        XCTAssertNil(session.lastActivityAt)
    }

    /// flaggedReason is only ever non-null when status isn't "ok" — but
    /// visibleFlaggedReason must still defensively hide it for an "ok" row
    /// even if the server ever sent one, per the field's documented contract.
    func testVisibleFlaggedReasonHiddenWhenStatusOK() throws {
        let json = """
        {"sessionId":"abc","repo":null,"branch":null,"worktree":null,
        "lastActivityAt":null,"status":"ok","flaggedReason":"should not show",
        "mergeTreeCheckedAt":null,"updatedAt":1}
        """
        let session = try JSONDecoder().decode(BookSession.self, from: Data(json.utf8))
        XCTAssertNil(session.visibleFlaggedReason)
    }

    func testVisibleFlaggedReasonShownWhenStuck() throws {
        let json = """
        {"sessionId":"abc","repo":null,"branch":null,"worktree":null,
        "lastActivityAt":null,"status":"stuck","flaggedReason":"no activity for 20 minutes",
        "mergeTreeCheckedAt":null,"updatedAt":1}
        """
        let session = try JSONDecoder().decode(BookSession.self, from: Data(json.utf8))
        XCTAssertEqual(session.visibleFlaggedReason, "no activity for 20 minutes")
    }

    /// The one field where getting null vs. present wrong reproduces a real
    /// defect class (per point-guard's own merge-tree backstop design):
    /// mergeTreeCheckedAt == nil means the backstop has NEVER run for this
    /// session, which is materially different from "ran and found nothing".
    /// These two states must decode distinctly and must never collapse.
    func testMergeTreeCheckedAtNullMeansNeverChecked() throws {
        let neverChecked = try decodeSession(mergeTreeCheckedAt: "null")
        XCTAssertNil(neverChecked.mergeTreeCheckedAt)

        let checkedClean = try decodeSession(mergeTreeCheckedAt: "1789504839982")
        XCTAssertNotNil(checkedClean.mergeTreeCheckedAt)
        XCTAssertEqual(checkedClean.mergeTreeCheckedAt, 1789504839982)
    }

    func testDecodesMessageReply() throws {
        let json = #"{"reply":"3 sessions are active, all ok."}"#
        let reply = try JSONDecoder().decode(MessageReply.self, from: Data(json.utf8))
        XCTAssertEqual(reply.reply, "3 sessions are active, all ok.")
    }

    func testDecodesMessageHistoryPayload() throws {
        let json = """
        {"messages":[{"id":"m1","message":"status?","reply":"all clear","createdAt":1789505000000}]}
        """
        let response = try JSONDecoder().decode(MessageHistoryResponse.self, from: Data(json.utf8))
        XCTAssertEqual(response.messages.count, 1)
        XCTAssertEqual(response.messages[0].message, "status?")
        XCTAssertEqual(response.messages[0].reply, "all clear")
    }

    func testDecodesEmptyMessageHistory() throws {
        let json = #"{"messages":[]}"#
        let response = try JSONDecoder().decode(MessageHistoryResponse.self, from: Data(json.utf8))
        XCTAssertTrue(response.messages.isEmpty)
    }

    func testCompactAge() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        XCTAssertEqual(UnixMillis.compactAge(1_700_000_000_000 - 40_000, now: now), "now")
        XCTAssertEqual(UnixMillis.compactAge(1_700_000_000_000 - 30 * 60 * 1000, now: now), "30m")
        XCTAssertEqual(UnixMillis.compactAge(1_700_000_000_000 - 6 * 3600 * 1000, now: now), "6h")
        XCTAssertEqual(UnixMillis.compactAge(1_700_000_000_000 - 10 * 86400 * 1000, now: now), "10d")
        XCTAssertEqual(UnixMillis.compactAge(nil, now: now), "")
    }

    func testPointGuardErrorExtractsReadablePlainErrorShape() {
        let body = #"{"error":"forbidden"}"#
        let error = PointGuardError.http(403, body)
        XCTAssertEqual(error.errorDescription, "Server error 403: forbidden")
    }

    func testPointGuardErrorFallsBackToRawBodyWhenUnparseable() {
        let error = PointGuardError.http(502, "Bad Gateway")
        XCTAssertEqual(error.errorDescription, "Server error 502: Bad Gateway")
    }

    func testPointGuardErrorHandlesEmptyBody() {
        let error = PointGuardError.http(503, "")
        XCTAssertEqual(error.errorDescription, "Server error 503")
    }

    func testServerConfigAppliesBearerAuthHeader() {
        var config = ServerConfig(baseURL: "http://127.0.0.1:3868", hostHeader: "", secret: "s3cr3t")
        var req = URLRequest(url: URL(string: "http://127.0.0.1:3868/book")!)
        config.apply(to: &req)
        XCTAssertEqual(req.value(forHTTPHeaderField: "authorization"), "Bearer s3cr3t")
        config.secret = ""
        req = URLRequest(url: URL(string: "http://127.0.0.1:3868/book")!)
        config.apply(to: &req)
        XCTAssertNil(req.value(forHTTPHeaderField: "authorization"))
    }

    func testServerConfigAppliesHostHeader() {
        let config = ServerConfig(baseURL: "http://100.101.38.91:3868", hostHeader: "barry.lan", secret: "")
        var req = URLRequest(url: URL(string: "http://100.101.38.91:3868/book")!)
        config.apply(to: &req)
        XCTAssertEqual(req.value(forHTTPHeaderField: "Host"), "barry.lan")
    }

    // MARK: Helpers

    private func decodeSession(repo: String? = "irrelevant", mergeTreeCheckedAt: String = "null") throws -> BookSession {
        let repoJSON = repo.map { "\"\($0)\"" } ?? "null"
        let json = """
        {"sessionId":"abc","repo":\(repoJSON),"branch":null,"worktree":null,
        "lastActivityAt":null,"status":"ok","flaggedReason":null,
        "mergeTreeCheckedAt":\(mergeTreeCheckedAt),"updatedAt":1}
        """
        return try JSONDecoder().decode(BookSession.self, from: Data(json.utf8))
    }
}

/// Integration tests against the real local point-guard service. These make
/// the client's contract executable: they fail if the API's real shapes
/// drift from the models. Skipped automatically when the service or its
/// secret is unavailable — never fail CI for that reason.
final class LiveAPITests: XCTestCase {
    /// point-guard requires a real BARRY_SECRET; there is no way to
    /// discover it programmatically in a test target, so this reads it from
    /// the environment the same way the running service does. When unset,
    /// every test below skips rather than fails.
    private var secret: String? {
        ProcessInfo.processInfo.environment["BARRY_SECRET"]
    }

    private func requireServer() async throws -> PointGuardClient {
        guard let secret, !secret.isEmpty else {
            throw XCTSkip("BARRY_SECRET not set in test environment")
        }
        let config = ServerConfig(baseURL: "http://127.0.0.1:3868", hostHeader: "", secret: secret)
        let client = PointGuardClient(config: config)
        do {
            _ = try await client.health()
        } catch {
            throw XCTSkip("point-guard not reachable on 127.0.0.1:3868: \(error)")
        }
        return client
    }

    func testFetchesRealBook() async throws {
        let client = try await requireServer()
        let response = try await client.book()
        // A machine with zero active Barry sessions is a valid state, so
        // this only asserts shape sanity for whatever came back, not count.
        for session in response.sessions {
            XCTAssertFalse(session.sessionId.isEmpty)
            XCTAssertTrue(["ok", "stuck", "conflicted"].contains(session.status), "unexpected status: \(session.status)")
        }
    }

    func testFetchesRealMessageHistory() async throws {
        let client = try await requireServer()
        let response = try await client.messageHistory(limit: 5)
        for entry in response.messages {
            XCTAssertFalse(entry.id.isEmpty)
        }
    }

    /// An unauthenticated request to a REAL route returns 403 (auth runs
    /// before routing) — a valid Bearer token against a nonexistent route
    /// is the discriminating negative control that actually proves routing
    /// (not just auth) is reachable.
    func testUnknownRouteWithValidAuthReturns404NotForbidden() async throws {
        guard let secret, !secret.isEmpty else {
            throw XCTSkip("BARRY_SECRET not set in test environment")
        }
        let config = ServerConfig(baseURL: "http://127.0.0.1:3868", hostHeader: "", secret: secret)
        guard let req = config.request(path: "/nonexistent-route-xyz") else {
            throw XCTSkip("bad URL")
        }
        do {
            _ = try await URLSession.shared.data(for: req)
        } catch {
            throw XCTSkip("point-guard not reachable: \(error)")
        }
        let (_, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse else {
            throw XCTSkip("no HTTP response")
        }
        XCTAssertEqual(http.statusCode, 404)
    }
}
