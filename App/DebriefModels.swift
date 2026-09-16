import Foundation

/// GET /debrief — what the whole team is doing, as opposed to the book's
/// per-session status. Shape pinned to the live service's `Debrief` interface
/// (bags/point-guard/src/debrief.ts). The payload is wrapped in a `debrief`
/// key the way /book wraps in `sessions`.
struct DebriefResponse: Decodable {
    let debrief: Debrief
}

struct Debrief: Decodable {
    let generatedAt: Double
    let counts: DebriefCounts
    let sessions: [DebriefSession]

    /// An EMPTY array means the plans service answered and had none — a
    /// different fact from "we could not ask it". `sources.plans` separates
    /// the two; see `SourceHealth`.
    let plans: [DebriefPlanLink]

    let trouble: [DebriefTrouble]

    /// `nil` means NO NARRATIVE HAS BEEN GENERATED YET — first boot, or every
    /// attempt failed. Never a placeholder string. Read it through
    /// `NarrativeState`, never directly.
    let narrative: DebriefNarrative?

    let inputsHash: String
    let sources: DebriefSources
}

/// Every count is a real number. `0` is a measured zero, not "unknown" — a
/// hidden row and a zero look identical to someone checking whether anything
/// is stuck, and only one of them answers the question.
struct DebriefCounts: Decodable {
    let total: Int
    let working: Int
    let idle: Int
    let stuck: Int
    let conflicted: Int
}

struct DebriefSession: Decodable, Identifiable {
    let sessionId: String

    /// Never nil — the service's getName() always returns something.
    let name: String
    let nameSource: String

    let repo: String?
    let repoName: String?
    let branch: String?
    let worktree: String?
    let lifecycleStatus: String

    /// The book's verdict, read verbatim — never recomputed here.
    let status: String

    /// Non-nil ONLY when status != "ok".
    let flaggedReason: String?

    let createdAt: Double

    /// `nil` means this session has produced NO messages at all — distinct
    /// from old activity, which is a real number.
    let lastActivityAt: Double?

    /// How long the session has EXISTED, not working time. Label it "alive".
    let aliveMs: Double

    let idleMs: Double?

    /// `nil` means the bookkeeping job has never summarized this session.
    /// MODEL-WRITTEN text from another job — a description, not a status.
    let latestSummary: String?

    /// `0` is a measured zero (a read-only session touched none).
    let filesTouched: Int

    /// `nil` means THE SLOW MERGE-TREE CHECK HAS NEVER RUN. A timestamp means
    /// it ran and found no TEXTUAL conflict. These must never collapse.
    let mergeTreeCheckedAt: Double?

    let plans: [DebriefPlanLink]

    var id: String { sessionId }

    /// Mirrors `BookSession.visibleFlaggedReason`: a reason is only
    /// interesting when something is actually flagged, and is hidden for an
    /// "ok" row even if the server ever sent one.
    var visibleFlaggedReason: String? {
        guard status != "ok", let flaggedReason, !flaggedReason.isEmpty else { return nil }
        return flaggedReason
    }

    /// Absence is the fact here, so it gets its own sentence rather than being
    /// hidden — the mirror image of `visibleFlaggedReason`.
    var mergeTreeCheckedLabel: String {
        guard let checkedAt = mergeTreeCheckedAt else {
            return "Merge-tree backstop: not yet checked"
        }
        return "Merge-tree backstop: last checked \(UnixMillis.compactAge(checkedAt)) ago"
    }
}

struct DebriefPlanLink: Decodable, Identifiable {
    let id: String
    let title: String
    let status: String
    let progress: DebriefPlanProgress
    let url: String

    /// Raw wire string; `PlanMatch` is where it becomes something a view can
    /// render honestly.
    let match: String
}

struct DebriefPlanProgress: Decodable {
    let done: Int
    let total: Int
    let of: String
}

struct DebriefTrouble: Decodable, Identifiable {
    let id: String
    let kind: String

    /// `nil` for troubles belonging to no single session (the outbox).
    let sessionId: String?

    /// Taken from the underlying row, never synthesized.
    let detail: String
    let at: Double
}

struct DebriefSources: Decodable {
    let sessions: DebriefSourceStatus
    let plans: DebriefSourceStatus
}

struct DebriefSourceStatus: Decodable, Equatable {
    /// `nil` means never read successfully since the service started — NOT
    /// "the read returned zero rows", which is a success with a timestamp.
    let lastSucceededAt: Double?

    /// `nil` means the most recent attempt SUCCEEDED.
    let lastError: String?
}

struct DebriefNarrative: Decodable, Equatable {
    let text: String
    let model: String
    let generatedAt: Double

    /// Hash of the inputs this text was written FROM. Differing from the
    /// debrief's own hash means the prose describes an older state.
    let inputsHash: String
}

// MARK: - States

/// Whether the prose overview exists, and whether it still describes now.
///
/// Three cases rather than an optional, for the same reason
/// `mergeTreeCheckedLabel` renders absence as a sentence: an empty region
/// reads as "nothing to report", and both "nothing was written" and "written
/// from older inputs" mean something else.
enum NarrativeState: Equatable {
    case notGenerated
    case current(DebriefNarrative)
    case stale(DebriefNarrative)

    init(debrief: Debrief) {
        guard let narrative = debrief.narrative else {
            self = .notGenerated
            return
        }
        self = narrative.inputsHash == debrief.inputsHash ? .current(narrative) : .stale(narrative)
    }

    /// `nil` where nothing was written. Deliberately does not invent a
    /// sentence — a caller wanting placeholder copy writes it knowingly.
    var text: String? {
        switch self {
        case .notGenerated: return nil
        case .current(let n), .stale(let n): return n.text
        }
    }

    /// Prose about measurements must be attributable, or a reader cannot tell
    /// it from the measurements.
    func attribution(now: Date = Date()) -> String? {
        switch self {
        case .notGenerated:
            return nil
        case .current(let n):
            return "\(n.model) · \(UnixMillis.compactAge(n.generatedAt, now: now)) ago"
        case .stale(let n):
            return "\(n.model) · \(UnixMillis.compactAge(n.generatedAt, now: now)) ago · describes an earlier state"
        }
    }

    var isStale: Bool {
        if case .stale = self { return true }
        return false
    }
}

/// How a plan came to be tied to a session. Today only `.repo` occurs, and it
/// means "this plan names the same repo this session is in" — NOT "this
/// session is working on it". A repo with fourteen sessions attaches the same
/// plan to all fourteen, which is why the qualifier is the honest part.
enum PlanMatch: Equatable {
    case repo
    case session
    case unknown(String)

    init(rawValue: String) {
        switch rawValue {
        case "repo": self = .repo
        case "session": self = .session
        default: self = .unknown(rawValue)
        }
    }

    var qualifier: String {
        switch self {
        case .repo: return "in this repo"
        case .session: return "this session"
        case .unknown(let raw): return raw
        }
    }
}

/// Whether a source answered, and therefore what an empty result means.
enum SourceHealth: Equatable {
    case ok(lastSucceededAt: Double?)
    case stale(lastSucceededAt: Double, error: String)
    case unavailable(error: String)

    init(status: DebriefSourceStatus) {
        switch (status.lastError, status.lastSucceededAt) {
        case (nil, let succeeded):
            self = .ok(lastSucceededAt: succeeded)
        case (let error?, let succeeded?):
            self = .stale(lastSucceededAt: succeeded, error: error)
        case (let error?, nil):
            self = .unavailable(error: error)
        }
    }

    /// Whether an empty list can be read as a real zero.
    var emptyMeansNone: Bool {
        if case .ok = self { return true }
        return false
    }

    var warning: String? {
        switch self {
        case .ok: return nil
        case .stale(_, let error): return "showing older data — \(error)"
        case .unavailable(let error): return "unavailable — \(error)"
        }
    }
}
