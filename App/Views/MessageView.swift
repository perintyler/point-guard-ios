import SwiftUI

/// A chat-LOOKING UI over point-guard's Heartbeat pattern (see
/// bags/point-guard/server/src/index.ts: POST /message) — but this is
/// explicitly NOT a conversation thread. Every send is a fresh, independent
/// call; point-guard carries no context between messages. The scrollback
/// below is just a log of past independent exchanges (GET /message/history),
/// not a memory the server has — nothing here should imply the model
/// "remembers" an earlier turn.
struct MessageView: View {
    @EnvironmentObject private var store: AppStore
    @State private var history: [MessageLogEntry] = []
    @State private var draft = ""
    @State private var isSending = false
    @State private var sendError: String?
    @State private var isLoadingHistory = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if isLoadingHistory && history.isEmpty {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 16) {
                                if history.isEmpty {
                                    Text("No messages yet. Each message below is answered independently — point-guard keeps no memory between sends.")
                                        .font(.footnote)
                                        .foregroundStyle(.secondary)
                                        .padding()
                                }
                                ForEach(history) { entry in
                                    MessageExchangeView(entry: entry)
                                        .id(entry.id)
                                }
                            }
                            .padding()
                        }
                        .onChange(of: history.count) {
                            if let last = history.last {
                                withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                            }
                        }
                    }
                }

                if let sendError {
                    Text(sendError)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .padding(.horizontal)
                }

                composer
            }
            .navigationTitle("Message")
            .task {
                await loadHistory()
            }
        }
    }

    private var composer: some View {
        HStack(spacing: 8) {
            TextField("Ask point-guard...", text: $draft, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(1...4)
                .accessibilityIdentifier("messageField")
            Button {
                Task { await send() }
            } label: {
                if isSending {
                    ProgressView()
                } else {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title2)
                }
            }
            .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSending)
            .accessibilityIdentifier("sendButton")
        }
        .padding()
    }

    private func loadHistory() async {
        isLoadingHistory = true
        defer { isLoadingHistory = false }
        do {
            let response = try await store.client.messageHistory(limit: 50)
            // Server returns newest-first per recentMessageLog's ORDER BY;
            // reverse for a natural top-to-bottom chat reading order.
            history = response.messages.sorted { $0.createdAt < $1.createdAt }
        } catch {
            sendError = error.localizedDescription
        }
    }

    private func send() async {
        let content = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty else { return }
        isSending = true
        sendError = nil
        defer { isSending = false }
        do {
            let result = try await store.client.sendMessage(content: content)
            draft = ""
            // Optimistic append: the server's history log is the source of
            // truth, but there's no id from the send response itself, so a
            // synthetic local id keeps this entry addressable in the list
            // until the next loadHistory() reconciles with the real log.
            history.append(MessageLogEntry(
                id: "local-\(UUID().uuidString)",
                message: content,
                reply: result.reply,
                createdAt: Date().timeIntervalSince1970 * 1000
            ))
        } catch {
            sendError = error.localizedDescription
        }
    }
}

struct MessageExchangeView: View {
    let entry: MessageLogEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Spacer(minLength: 40)
                Text(entry.message)
                    .padding(10)
                    .background(Theme.accent)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            HStack {
                Text(entry.reply)
                    .padding(10)
                    .background(Theme.accentSoft)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                Spacer(minLength: 40)
            }
        }
    }
}
