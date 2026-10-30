import SwiftUI

/// The keys and connections the Health and Food tabs need. Everything secret goes to the
/// Keychain; nothing is compiled into the app.
struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var whoopClientID = KeychainStore.get(.whoopClientID) ?? ""
    @State private var whoopClientSecret = KeychainStore.get(.whoopClientSecret) ?? ""
    @State private var anthropicKey = KeychainStore.get(.anthropicAPIKey) ?? ""
    @State private var imageKey = KeychainStore.get(.imageAPIKey) ?? ""

    @State private var whoopConnected = WhoopTokenStore.shared.isConnected
    @State private var isConnecting = false
    @State private var message: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    SecureField("Client ID", text: $whoopClientID)
                    SecureField("Client secret", text: $whoopClientSecret)
                    if whoopConnected {
                        Label("Connected", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        Button("Disconnect WHOOP", role: .destructive) {
                            Task {
                                await WhoopTokenStore.shared.disconnect()
                                whoopConnected = false
                            }
                        }
                    } else {
                        Button {
                            Task { await connectWhoop() }
                        } label: {
                            if isConnecting { ProgressView() } else { Text("Connect WHOOP") }
                        }
                        .disabled(whoopClientID.isEmpty || whoopClientSecret.isEmpty || isConnecting)
                    }
                } header: {
                    Text("WHOOP")
                } footer: {
                    Text("Same client ID and secret as Baseline (developer.whoop.com). The redirect URL already registered there keeps working.")
                }

                Section {
                    SecureField("sk-ant-…", text: $anthropicKey)
                } header: {
                    Text("Anthropic API key")
                } footer: {
                    Text("Writes the morning health brief and plans the day's meals.")
                }

                Section {
                    SecureField("sk-…", text: $imageKey)
                } header: {
                    Text("OpenAI API key (food photos)")
                } footer: {
                    Text("Draws one photo per new dish, once, then reuses it. Optional: without it, dishes show an illustrated card.")
                }

                if let message {
                    Section { Text(message).foregroundStyle(.secondary) }
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        save()
                        dismiss()
                    }
                }
            }
        }
    }

    private func save() {
        KeychainStore.set(whoopClientID, for: .whoopClientID)
        KeychainStore.set(whoopClientSecret, for: .whoopClientSecret)
        KeychainStore.set(anthropicKey, for: .anthropicAPIKey)
        KeychainStore.set(imageKey, for: .imageAPIKey)
    }

    private func connectWhoop() async {
        save()
        isConnecting = true
        defer { isConnecting = false }
        do {
            try await WhoopAuthService.shared.connect()
            whoopConnected = true
            message = "WHOOP connected. The Health tab will sync on open."
        } catch {
            message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
}
