import XCTest
@testable import PointGuard

/// Pinned to a REAL payload captured from the live point-guard service on
/// 2026-09-15, trimmed to two sessions chosen for CONTRAST: the first has a
/// present `mergeTreeCheckedAt` and four attached plans, the second has it
/// null and no plans. The narrative in it is genuinely stale — also captured,
/// not contrived; on a busy machine the team changes faster than the
/// five-minute narrative tick, so stale is the common case.
///
/// If these fail after an API change, the contract moved — update the models
/// AND the fixture together.
final class DebriefModelsTests: XCTestCase {
    private static let fixture = #"""
    {"debrief":{"generatedAt":1789524492841,"counts":{"total":31,"working":4,"idle":27,"stuck":0,"conflicted":0},"sessions":[{"sessionId":"zkwFFBjLNzbn_D0F1qFQ8","name":"barry harness architecture research","nameSource":"metadata","repo":"/Users/tyler/repos/barry/.git","repoName":"barry","branch":null,"worktree":"/Users/tyler/repos/barry","lifecycleStatus":"running","status":"ok","flaggedReason":null,"createdAt":1789017109594,"lastActivityAt":1789504864907,"aliveMs":507383247,"idleMs":19627934,"latestSummary":"### Done\n- Restarted point-guard service\n- Verified book endpoint returns sessions with correct repo\n- Created worktrees for pg-web and pg-macos\n- Checked barry-iphone's git setup\n- Confirmed iOS app strategy with Tyler\n- Initialized point-guard-iphone repo\n- Launched 3 async agents: web, macOS, iOS builds\n\n### What went right\n- Point-guard service restarted cleanly\n- Book endpoint returns session\u2026","filesTouched":0,"mergeTreeCheckedAt":1789524432587,"plans":[{"id":"plan_f7595db773bf","title":"Harness and coding bags, with inline trait bounds","status":"in-progress","progress":{"done":21,"total":35,"of":"spec"},"url":"http://127.0.0.1:4880/#plan_f7595db773bf","match":"repo"},{"id":"plan_969cb17fc525","title":"Documentation audit follow-through","status":"in-progress","progress":{"done":30,"total":37,"of":"spec"},"url":"http://127.0.0.1:4880/#plan_969cb17fc525","match":"repo"},{"id":"plan_c9f9741ac805","title":"Checks that cannot fail: the metrics defects left after the delivery fix","status":"draft","progress":{"done":0,"total":17,"of":"spec"},"url":"http://127.0.0.1:4880/#plan_c9f9741ac805","match":"repo"},{"id":"plan_c872e43bcf84","title":"Audit leftovers: deletions and two CLI rulings","status":"draft","progress":{"done":0,"total":8,"of":"spec"},"url":"http://127.0.0.1:4880/#plan_c872e43bcf84","match":"repo"}]},{"sessionId":"C1ZZJwd2BJ5zWT4LNGpaH","name":"session-bookkeeping","nameSource":"metadata","repo":"/Users/tyler/repos/bags/metrics/.git","repoName":"metrics","branch":null,"worktree":"/Users/tyler/repos/bags/metrics","lifecycleStatus":"running","status":"ok","flaggedReason":null,"createdAt":1789485824474,"lastActivityAt":1789524491245,"aliveMs":38668367,"idleMs":1596,"latestSummary":"### Done\n- Merged fix for `collector-silent` firing (commit `992eb19`)\n- Live check confirms all 10 collectors now show `firing: 0`\n\n### Learnings\n- The bug was a side effect of a previous change that split collectors into job series\n- `job` label caused alias shadowing in `src/rules.ts` (90 lines changed)\n\n### What went right\n- Live check confirmed fix in production\n- Clear commit message with co\u2026","filesTouched":0,"mergeTreeCheckedAt":null,"plans":[]}],"plans":[{"id":"plan_f7595db773bf","title":"Harness and coding bags, with inline trait bounds","status":"in-progress","progress":{"done":21,"total":35,"of":"spec"},"url":"http://127.0.0.1:4880/#plan_f7595db773bf","match":"repo"},{"id":"plan_969cb17fc525","title":"Documentation audit follow-through","status":"in-progress","progress":{"done":30,"total":37,"of":"spec"},"url":"http://127.0.0.1:4880/#plan_969cb17fc525","match":"repo"},{"id":"plan_c9f9741ac805","title":"Checks that cannot fail: the metrics defects left after the delivery fix","status":"draft","progress":{"done":0,"total":17,"of":"spec"},"url":"http://127.0.0.1:4880/#plan_c9f9741ac805","match":"repo"},{"id":"plan_c872e43bcf84","title":"Audit leftovers: deletions and two CLI rulings","status":"draft","progress":{"done":0,"total":8,"of":"spec"},"url":"http://127.0.0.1:4880/#plan_c872e43bcf84","match":"repo"}],"trouble":[],"narrative":{"text":"There are 39 total sessions, with 4 active in the last 10 minutes, 35 quiet, 0 stuck, and 0 conflicted. The listed sessions include names such as barry harness architecture research, tunnel-port-mapping, scout-api-backfill-plan-verification, session-bookkeeping, and several short ID-like session names. No troubles are recorded, and the open plans mention Harness and coding bags with inline trait bounds, Documentation audit follow-through, checks that cannot fail in the metrics defects left after the delivery fix, and audit leftovers covering deletions and two CLI rulings.","model":"gpt-5.4-mini","generatedAt":1789524435030,"inputsHash":"888aed908ed96695"},"inputsHash":"82f4ffe00c1272f0","sources":{"sessions":{"lastSucceededAt":1789524492841,"lastError":null},"plans":{"lastSucceededAt":1789524492841,"lastError":null}}}}
    """#

    private func decode() throws -> Debrief {
        try JSONDecoder().decode(DebriefResponse.self, from: Data(Self.fixture.utf8)).debrief
    }

    func testDecodesRealPayload() throws {
        let debrief = try decode()
        XCTAssertEqual(debrief.counts.total, 31)
        XCTAssertEqual(debrief.sessions.count, 2)
        XCTAssertFalse(debrief.inputsHash.isEmpty)
    }

    func testCountBucketsAccountForEverySession() throws {
        let c = try decode().counts
        XCTAssertEqual(c.working + c.idle + c.stuck + c.conflicted, c.total)
    }

    func testZeroCountsAreRealZeros() throws {
        let c = try decode().counts
        // The values a reader is most likely to be checking. If either ever
        // decoded as nil-then-defaulted, a real problem would look identical
        // to a healthy team.
        XCTAssertEqual(c.stuck, 0)
        XCTAssertEqual(c.conflicted, 0)
    }

    func testMergeTreeNullMeansNeverCheckedNotClean() throws {
        let sessions = try decode().sessions
        XCTAssertNotNil(sessions[0].mergeTreeCheckedAt)
        XCTAssertNil(sessions[1].mergeTreeCheckedAt)
        XCTAssertEqual(sessions[1].mergeTreeCheckedLabel, "Merge-tree backstop: not yet checked")
        XCTAssertTrue(sessions[0].mergeTreeCheckedLabel.contains("last checked"))
    }

    func testVisibleFlaggedReasonHiddenForOkSessions() throws {
        for session in try decode().sessions where session.status == "ok" {
            XCTAssertNil(session.visibleFlaggedReason)
        }
    }

    func testPlanMatchRendersAsQualifierNotOwnership() throws {
        let plans = try decode().sessions[0].plans
        XCTAssertFalse(plans.isEmpty)
        for plan in plans {
            let qualifier = PlanMatch(rawValue: plan.match).qualifier
            XCTAssertEqual(qualifier, "in this repo")
            XCTAssertFalse(qualifier.lowercased().contains("working"))
        }
    }

    func testCapturedNarrativeIsStaleAndLabelled() throws {
        let state = NarrativeState(debrief: try decode())
        XCTAssertTrue(state.isStale)
        XCTAssertNotNil(state.text, "a stale narrative is still shown — it was true recently")
        XCTAssertTrue(state.attribution()?.contains("describes an earlier state") == true)
    }

    func testEmptyPlansOnASucceedingSourceMeansNone() throws {
        let debrief = try decode()
        XCTAssertTrue(debrief.sessions[1].plans.isEmpty)
        XCTAssertTrue(SourceHealth(status: debrief.sources.plans).emptyMeansNone)
    }
}

/// The three state types, including the cases a live capture cannot produce.
final class DebriefStateTests: XCTestCase {
    private func narrative(_ hash: String) -> DebriefNarrative {
        DebriefNarrative(text: "Four sessions are quiet.", model: "gpt-5.4-mini", generatedAt: 1_000, inputsHash: hash)
    }

    func testNoNarrativeInventsNoSentence() {
        let state = NarrativeState.notGenerated
        XCTAssertNil(state.text)
        XCTAssertNil(state.attribution())
    }

    func testMatchingHashIsCurrentNotStale() {
        let state = NarrativeState.current(narrative("abc"))
        XCTAssertFalse(state.isStale)
        XCTAssertEqual(state.attribution()?.contains("describes an earlier state"), false)
    }

    func testUnknownPlanMatchIsShownRatherThanGuessed() {
        XCTAssertEqual(PlanMatch(rawValue: "milestone"), .unknown("milestone"))
        XCTAssertEqual(PlanMatch(rawValue: "milestone").qualifier, "milestone")
    }

    func testSourceNeverReadMeansEmptyIsUnknown() {
        let health = SourceHealth(status: DebriefSourceStatus(lastSucceededAt: nil, lastError: "refused"))
        XCTAssertFalse(health.emptyMeansNone, "an empty list here is 'could not ask', not 'none'")
        XCTAssertNotNil(health.warning)
    }

    func testSourceStaleAfterEarlierSuccess() {
        let health = SourceHealth(status: DebriefSourceStatus(lastSucceededAt: 100, lastError: "timeout"))
        XCTAssertEqual(health, .stale(lastSucceededAt: 100, error: "timeout"))
        XCTAssertFalse(health.emptyMeansNone, "rows on screen are real but old")
    }
}
