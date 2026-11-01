import SwiftUI

/// The WHOOP connection the Health tab needs. The secret goes to the Keychain; nothing is
/// compiled into the app. Writing and pictures run on-device, so there are no other keys.
struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var whoopClientID = KeychainStore.get(.whoopClientID) ?? ""
    @State private var whoopClientSecret = KeychainStore.get(.whoopClientSecret) ?? ""

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
                    Label(OnDeviceModel.unavailableReason ?? "Apple Intelligence is on.", systemImage: "apple.intelligence")
                } header: {
                    Text("Health brief and food")
                } footer: {
                    Text("The morning brief, meal choices and dish pictures run on this device with Apple Intelligence. Free, and nothing leaves the phone.")
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
