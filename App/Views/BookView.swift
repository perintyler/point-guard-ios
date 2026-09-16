import SwiftUI

/// The book: every Barry session point-guard is currently watching, per
/// GET /book. REST-poll only (no realtime layer) — pull-to-refresh plus a
/// background timer (see AppStore.startPolling).
struct BookView: View {
    @EnvironmentObject private var store: AppStore
    @State private var showSettings = false

    var body: some View {
        NavigationStack {
            Group {
                if store.isLoading && store.sessions.isEmpty {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let error = store.listError, store.sessions.isEmpty {
                    ContentUnavailableView {
                        Label("Can't reach point-guard", systemImage: "wifi.slash")
                    } description: {
                        Text(error)
                    } actions: {
                        Button("Settings") { showSettings = true }
                        Button("Retry") { Task { await store.refreshBook() } }
                    }
                } else if store.sessions.isEmpty {
                    ContentUnavailableView("No sessions", systemImage: "checkmark.circle")
                } else {
                    sessionList
                }
            }
            .navigationTitle("Point Guard")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                    .accessibilityIdentifier("settingsButton")
                }
            }
            .sheet(isPresented: $showSettings) {
                SettingsView()
            }
            // No .onDisappear { stopPolling() } here: that fires on a tab
            // switch, which silently stopped refreshing the moment you looked
            // at another tab. RootTabView owns the timer now.
            .task { await store.refreshBook() }
        }
    }

    private var sessionList: some View {
        List(store.sessions) { session in
            BookSessionRow(session: session)
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: 6, leading: 20, bottom: 6, trailing: 20))
        }
        .listStyle(.plain)
        .refreshable { await store.refreshBook() }
        .accessibilityIdentifier("bookList")
    }
}

struct BookSessionRow: View {
    let session: BookSession

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                StatusDot(status: session.status)
                Text(String(session.sessionId.prefix(12)))
                    .font(.body.weight(.medium).monospaced())
                    .lineLimit(1)
                Spacer(minLength: 8)
                Text(UnixMillis.compactAge(session.lastActivityAt))
                    .font(.footnote)
                    .foregroundStyle(.tertiary)
                    .monospacedDigit()
            }
            HStack(spacing: 6) {
                if let repo = session.repoName {
                    Text(repo)
                }
                if let branch = session.branch {
                    Text(branch)
                        .foregroundStyle(Theme.accent)
                }
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .padding(.leading, 16)

            if let reason = session.visibleFlaggedReason {
                Text(reason)
                    .font(.footnote)
                    .foregroundStyle(Theme.statusColor(session.status))
                    .padding(.leading, 16)
                    .lineLimit(2)
            }

            // mergeTreeCheckedAt is NOT a "conflict-free" indicator — null
            // means the merge-tree backstop has never run for this session
            // yet, which is a materially different fact from "checked and
            // found nothing". These must never collapse into one display.
            Text(mergeTreeCheckedLabel)
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .padding(.leading, 16)
        }
        .padding(.vertical, 6)
    }

    private var mergeTreeCheckedLabel: String {
        guard let checkedAt = session.mergeTreeCheckedAt else {
            return "Merge-tree backstop: not yet checked"
        }
        return "Merge-tree backstop: last checked \(UnixMillis.compactAge(checkedAt)) ago"
    }
}
