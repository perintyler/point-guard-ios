import Foundation
import SwiftUI

/// App-wide state: server config, the book, connectivity. REST-poll only —
/// point-guard has no WebSocket surface this app uses, so a timer is the
/// entire "live update" mechanism.
@MainActor
final class AppStore: ObservableObject {
    @Published var config: ServerConfig
    @Published var sessions: [BookSession] = []
    @Published var listError: String?
    @Published var isLoading = false

    var client: PointGuardClient { PointGuardClient(config: config) }

    private var pollTimer: Timer?

    init(config: ServerConfig = .load()) {
        self.config = config
    }

    func updateConfig(_ newConfig: ServerConfig) {
        config = newConfig
        newConfig.save()
        Task { await refreshBook() }
    }

    func refreshBook() async {
        if sessions.isEmpty { isLoading = true }
        defer { isLoading = false }
        do {
            let response = try await client.book()
            // Stuck/conflicted first, then most-recently-active — surfaces
            // what needs attention without hiding the rest.
            sessions = response.sessions.sorted { lhs, rhs in
                let lhsPriority = lhs.status == "ok" ? 0 : 1
                let rhsPriority = rhs.status == "ok" ? 0 : 1
                if lhsPriority != rhsPriority { return lhsPriority > rhsPriority }
                return (lhs.lastActivityAt ?? 0) > (rhs.lastActivityAt ?? 0)
            }
            listError = nil
        } catch {
            listError = error.localizedDescription
        }
    }

    /// point-guard has no realtime push for the book; 45s balances
    /// freshness against not hammering the service.
    func startPolling() {
        stopPolling()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 45, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in await self?.refreshBook() }
        }
    }

    func stopPolling() {
        pollTimer?.invalidate()
        pollTimer = nil
    }
}
