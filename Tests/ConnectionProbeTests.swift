import XCTest
@testable import PointGuard

/// What "Test connection" tells the user.
///
/// The classification is the whole point of the feature: the user moves between
/// tailnets, so the failure modes that need DIFFERENT fixes must not arrive
/// wearing the same message. These drive the mapping directly — no network
/// needed, because a `URLError` is just a value.
final class ConnectionProbeTests: XCTestCase {

    // MARK: - Transport failures stay distinguishable

    func testWrongTailnetAndDownSidecarAreDifferentOutcomes() {
        let unresolvable = ConnectionProbe.classify(transportError: URLError(.cannotFindHost))
        let refused = ConnectionProbe.classify(transportError: URLError(.cannotConnectToHost))

        XCTAssertEqual(unresolvable, .cannotResolveHost)
        XCTAssertEqual(refused, .cannotConnect)
        XCTAssertNotEqual(unresolvable.message, refused.message,
                          "a wrong tailnet and a dead sidecar must not read identically")
    }

    func testDNSFailureIsReportedAsAnUnresolvableHost() {
        XCTAssertEqual(ConnectionProbe.classify(transportError: URLError(.dnsLookupFailed)),
                       .cannotResolveHost)
    }

    func testTLSFailuresAreTheirOwnCategory() {
        for code in [URLError.Code.secureConnectionFailed,
                     .serverCertificateUntrusted,
                     .serverCertificateHasUnknownRoot,
                     .serverCertificateHasBadDate] {
            let outcome = ConnectionProbe.classify(transportError: URLError(code))
            guard case .tlsFailure = outcome else {
                return XCTFail("\(code) should classify as a TLS failure, got \(outcome)")
            }
            XCTAssertFalse(outcome.isReachable)
        }
    }

    /// Removing `NSAllowsArbitraryLoads` means a plain-HTTP call to a non-local
    /// host now fails at the ATS layer. That must say "TLS", not "host is down"
    /// — the fix is a URL scheme, not a network.
    func testBlockedCleartextReadsAsATLSProblem() {
        let outcome = ConnectionProbe.classify(
            transportError: URLError(.appTransportSecurityRequiresSecureConnection)
        )
        guard case .tlsFailure = outcome else {
            return XCTFail("ATS-blocked cleartext should classify as a TLS failure, got \(outcome)")
        }
    }

    func testTimeoutIsNotConflatedWithAConnectionRefusal() {
        let timedOut = ConnectionProbe.classify(transportError: URLError(.timedOut))
        XCTAssertEqual(timedOut, .timedOut)
        XCTAssertNotEqual(timedOut.message, ProbeOutcome.cannotConnect.message)
    }

    // MARK: - The 403 is a reachability SUCCESS

    /// The case that makes this probe honest. A 403 is the server answering,
    /// which PROVES the tailnet path works — reporting it as a flat failure
    /// would send someone debugging a network that the probe just verified.
    func testForbiddenIsReachableAndSaysTheSecretIsTheProblem() {
        let outcome = ConnectionProbe.classify(apiError: .http(403, "Forbidden"))

        XCTAssertEqual(outcome, .reachableButUnauthorized)
        XCTAssertTrue(outcome.isReachable, "a 403 came from the server, so the server is reachable")
        XCTAssertFalse(outcome.isFullyWorking, "but the app still cannot read the book")

        let message = outcome.message.lowercased()
        XCTAssertTrue(message.contains("secret"), "must name the secret as the thing to fix: \(outcome.message)")
        XCTAssertTrue(message.contains("reached"), "must say the server was reached: \(outcome.message)")
    }

    func testOtherHTTPErrorsAreReachableButNotBlamedOnTheSecret() {
        let outcome = ConnectionProbe.classify(apiError: .http(502, "Bad Gateway"))

        guard case .serverError(let status, _) = outcome else {
            return XCTFail("expected a server error, got \(outcome)")
        }
        XCTAssertEqual(status, 502)
        XCTAssertTrue(outcome.isReachable)
        XCTAssertFalse(outcome.message.lowercased().contains("secret"),
                       "a 502 is not a credential problem")
    }

    // MARK: - Success reports what it actually saw

    func testSuccessReportsTheSessionCount() {
        XCTAssertTrue(ProbeOutcome.working(sessionCount: 7).message.contains("7"),
                      "a success that names no number proves nothing about the data")
        XCTAssertTrue(ProbeOutcome.working(sessionCount: 7).isFullyWorking)
    }

    /// A probe that cannot distinguish its own states is the failure mode
    /// AGENTS.md warns about: if this were completely broken, every outcome
    /// would read the same and the user would learn nothing.
    func testEveryOutcomeProducesADistinctMessage() {
        let outcomes: [ProbeOutcome] = [
            .working(sessionCount: 1),
            .reachableButUnauthorized,
            .cannotResolveHost,
            .cannotConnect,
            .tlsFailure("certificate expired"),
            .timedOut,
            .serverError(status: 502, detail: "Bad Gateway"),
            .badURL,
            .badResponse("garbage"),
        ]
        let messages = Set(outcomes.map(\.message))
        XCTAssertEqual(messages.count, outcomes.count,
                       "two outcomes share a message — the user cannot tell them apart")
    }

    // MARK: - Which of the two requests produced the answer

    /// Pointing at something that answers HTTP but is NOT a healthy Barry API
    /// must not come back blaming the secret.
    ///
    /// The health route answers 502 while the book route answers 403. Those
    /// MUST differ: a stub returning one status to both would leave this test
    /// green even with the health check deleted, because the book call
    /// would then produce the same 502 on its own.
    func testAnUnhealthyServerIsNotBlamedOnTheSecret() async {
        let outcome = await ConnectionProbe(
            config: ServerConfig(baseURL: "http://stub.invalid", secret: "shhh"),
            urlSession: StubURLProtocol.session(health: 502, book: 403)
        ).run()

        guard case .serverError(let status, _) = outcome else {
            return XCTFail("a 502 from the health route should outrank the book route's 403, got \(outcome)")
        }
        XCTAssertEqual(status, 502)
        XCTAssertFalse(outcome.message.lowercased().contains("secret"),
                       "a broken health route is not a credential problem")
    }

    /// The mirror image, and the reason the health call happens at all: a
    /// HEALTHY server that refuses the secret must report the 403.
    func testAHealthyServerThatRefusesTheSecretReportsUnauthorized() async {
        let outcome = await ConnectionProbe(
            config: ServerConfig(baseURL: "http://stub.invalid", secret: "wrong"),
            urlSession: StubURLProtocol.session(health: 200, book: 403)
        ).run()

        XCTAssertEqual(outcome, .reachableButUnauthorized)
    }

    // MARK: - End to end against the real server

    /// The real service with no secret. Unlike the main Barry API there is no
    /// proxy that fills the secret in, so this is what BOTH the simulator and
    /// the phone see unconfigured — and it must come back as "reachable, fix
    /// the secret", never as a network failure.
    ///
    /// Skips only when the service is genuinely absent — never when it answers,
    /// because an answer is the thing under test.
    func testRealServiceWithNoSecretReportsUnauthorized() async throws {
        let config = ServerConfig(baseURL: ServerConfig.simulatorURL, secret: "")
        guard await serverIsUp(config) else {
            throw XCTSkip("point-guard not listening on 127.0.0.1:3868")
        }

        let outcome = await ConnectionProbe(config: config).run()
        XCTAssertEqual(outcome, .reachableButUnauthorized,
                       "point-guard 403s an unauthenticated caller even from loopback")
    }

    /// With the real secret the same probe must come back fully working. This
    /// is also the simulator's path, so it fails if the ATS configuration ever
    /// stops permitting localhost cleartext.
    ///
    /// Skips when BARRY_SECRET is not in the environment — a secret is not
    /// something a test may invent.
    func testRealServiceWithTheSecretReportsFullyWorking() async throws {
        guard let secret = ProcessInfo.processInfo.environment["BARRY_SECRET"], !secret.isEmpty else {
            throw XCTSkip("BARRY_SECRET not set; cannot exercise the authorized path")
        }
        let config = ServerConfig(baseURL: ServerConfig.simulatorURL, secret: secret)
        guard await serverIsUp(config) else {
            throw XCTSkip("point-guard not listening on 127.0.0.1:3868")
        }

        let outcome = await ConnectionProbe(config: config).run()
        guard case .working = outcome else {
            return XCTFail("expected a working connection with the real secret, got \(outcome)")
        }
    }

    private func serverIsUp(_ config: ServerConfig) async -> Bool {
        guard let request = config.request(path: ServerConfig.healthPath) else { return false }
        return (try? await URLSession.shared.data(for: request)) != nil
    }
}

/// Answers the health route and the book route with SEPARATE canned
/// statuses, so a test can tell which of the probe's two requests produced the
/// outcome.
private final class StubURLProtocol: URLProtocol {
    nonisolated(unsafe) static var healthStatus = 200
    nonisolated(unsafe) static var bookStatus = 200

    static func session(health: Int, book: Int) -> URLSession {
        healthStatus = health
        bookStatus = book
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let isHealth = request.url?.path == ServerConfig.healthPath
        let status = isHealth ? Self.healthStatus : Self.bookStatus
        let response = HTTPURLResponse(
            url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(#"{"sessions":[]}"#.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
