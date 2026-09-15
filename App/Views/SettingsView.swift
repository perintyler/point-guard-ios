import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss

    @State private var baseURL = ""
    @State private var hostHeader = ""
    @State private var secret = ""
    @State private var healthResult: TestResult?
    @State private var authResult: TestResult?
    @State private var isTesting = false

    enum TestResult { case ok, failed(String) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Server URL", text: $baseURL)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .accessibilityIdentifier("serverURLField")
                    TextField("Host header (optional)", text: $hostHeader)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    SecureField("Secret (BARRY_SECRET)", text: $secret)
                        .accessibilityIdentifier("secretField")
                } header: {
                    Text("Server")
                } footer: {
                    Text("On Tailscale, use your Mac's address with host header barry.lan. point-guard listens on port 3868.")
                }
                Section {
                    Button("Test connection") { Task { await test() } }
                        .disabled(isTesting)
                        .accessibilityIdentifier("testConnectionButton")
                    resultRow(label: "Reachable (/health, no auth)", result: healthResult)
                    resultRow(label: "Authenticated (/book)", result: authResult)
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") {
                        store.updateConfig(currentConfig())
                        dismiss()
                    }
                }
            }
            .onAppear {
                baseURL = store.config.baseURL
                hostHeader = store.config.hostHeader
                secret = store.config.secret
            }
        }
    }

    @ViewBuilder
    private func resultRow(label: String, result: TestResult?) -> some View {
        switch result {
        case .ok:
            Label(label, systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .failed(let reason):
            VStack(alignment: .leading, spacing: 2) {
                Label(label, systemImage: "xmark.circle.fill")
                    .foregroundStyle(.red)
                Text(reason)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        case nil:
            EmptyView()
        }
    }

    private func currentConfig() -> ServerConfig {
        ServerConfig(
            baseURL: baseURL.trimmingCharacters(in: .whitespaces),
            hostHeader: hostHeader.trimmingCharacters(in: .whitespaces),
            secret: secret
        )
    }

    /// Two independent checks: /health needs no secret at all (a probe that
    /// itself requires the secret can't distinguish "server down" from
    /// "wrong secret"), so it validates reachability alone. /book requires a
    /// valid Bearer token, so success there validates the secret separately.
    private func test() async {
        isTesting = true
        defer { isTesting = false }
        let config = currentConfig()
        let client = PointGuardClient(config: config)

        do {
            healthResult = try await client.health() ? .ok : .failed("Server said not-ok")
        } catch {
            healthResult = .failed(error.localizedDescription)
            authResult = nil
            return
        }

        do {
            _ = try await client.book()
            authResult = .ok
        } catch {
            authResult = .failed(error.localizedDescription)
        }
    }
}
