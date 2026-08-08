import SwiftUI
import SwiftData

struct ImportContactsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var isImporting = false
    @State private var importCount: Int?
    @State private var importError: String?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ImportOptionRow(
                        icon: "person.crop.circle.fill",
                        iconColor: .green,
                        title: "Apple Contacts",
                        subtitle: "Import from your iPhone/Mac address book"
                    ) {
                        importAppleContacts()
                    }
                } header: {
                    Text("Import From")
                } footer: {
                    Text("Only new contacts are imported — anyone already here is skipped, matched on email, then phone number, then name.\n\nImported contacts are stored in your own private iCloud account so they sync across your devices. They are never sent anywhere else.")
                }

                if let count = importCount {
                    Section {
                        Label("\(count) contacts imported successfully", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    }
                }

                if let error = importError {
                    Section {
                        Label(error, systemImage: "xmark.circle.fill")
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Import Contacts")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .overlay {
                if isImporting {
                    ZStack {
                        Color.black.opacity(0.3).ignoresSafeArea()
                        VStack(spacing: 12) {
                            ProgressView()
                            Text("Importing…")
                                .font(.subheadline)
                                .foregroundStyle(.white)
                        }
                        .padding(24)
                        .background(.ultraThinMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                    }
                }
            }
        }
    }

    private func importAppleContacts() {
        isImporting = true
        importCount = nil
        importError = nil

        Task {
            do {
                let count = try await AppleContactsService.shared.importIntoStore(context: modelContext)
                await MainActor.run {
                    importCount = count
                    isImporting = false
                }
            } catch {
                await MainActor.run {
                    importError = error.localizedDescription
                    isImporting = false
                }
            }
        }
    }
}

// MARK: - ImportOptionRow

private struct ImportOptionRow: View {
    let icon: String
    let iconColor: Color
    let title: String
    let subtitle: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundStyle(iconColor)
                    .frame(width: 32)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundStyle(.primary)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
