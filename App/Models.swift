import Foundation

/// GET /book — one row per Barry session point-guard is watching. Shape
/// pinned to the live service's `store.bookRows()` (bags/point-guard/src/store.ts):
/// `repo` is a git-common-dir path (ends in ".git"), not a display name.
struct BookSession: Decodable, Identifiable {
    let sessionId: String
    let repo: String?
    let branch: String?
    let worktree: String?
    let lastActivityAt: Double?
    let status: String
    let flaggedReason: String?
    let mergeTreeCheckedAt: Double?
    let updatedAt: Double

    var id: String { sessionId }

    /// `repo` is a git-common-dir path like "/Users/tyler/repos/barry/.git" —
    /// strip the trailing ".git" and take the parent directory's basename for
    /// a readable name ("barry"). Falls back to the raw value (or nil) if the
    /// shape doesn't match what's expected.
    var repoName: String? {
        guard let repo else { return nil }
        var path = repo
        if path.hasSuffix("/.git") {
            path.removeLast("/.git".count)
        } else if path.hasSuffix(".git") {
            path.removeLast(".git".count)
            if path.hasSuffix("/") { path.removeLast() }
        }
        let last = (path as NSString).lastPathComponent
        return last.isEmpty ? repo : last
    }

    /// Secondary text is only interesting when something's actually flagged —
    /// an "ok" session's flaggedReason (always nil in practice) shouldn't be
    /// surfaced even if the server ever sent one.
    var visibleFlaggedReason: String? {
        guard status != "ok", let flaggedReason, !flaggedReason.isEmpty else { return nil }
        return flaggedReason
    }
}

struct BookResponse: Decodable {
    let sessions: [BookSession]
}

/// POST /message response.
struct MessageReply: Decodable {
    let reply: String
}

/// One row of GET /message/history — a single independent heartbeat
/// exchange (no conversation threading server-side).
struct MessageLogEntry: Decodable, Identifiable {
    let id: String
    let message: String
    let reply: String
    let createdAt: Double
}

struct MessageHistoryResponse: Decodable {
    let messages: [MessageLogEntry]
}

/// Shared helpers for the unix-ms timestamps this API uses everywhere
/// (unlike barry's main API, which uses ISO8601 strings).
enum UnixMillis {
    static func date(_ ms: Double?) -> Date? {
        guard let ms else { return nil }
        return Date(timeIntervalSince1970: ms / 1000)
    }

    /// Compact relative-age string ("now", "30m", "6h", "10d") matching the
    /// barry-iphone app's own `ISO8601.compactAge` vocabulary, adapted for a
    /// unix-ms source instead of an ISO8601 string.
    static func compactAge(_ ms: Double?, now: Date = Date()) -> String {
        guard let date = date(ms) else { return "" }
        let seconds = now.timeIntervalSince(date)
        if seconds < 60 { return "now" }
        let minutes = Int(seconds / 60)
        if minutes < 60 { return "\(minutes)m" }
        let hours = minutes / 60
        if hours < 24 { return "\(hours)h" }
        let days = hours / 24
        return "\(days)d"
    }
}
