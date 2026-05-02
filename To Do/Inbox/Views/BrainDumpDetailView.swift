import SwiftUI
import SwiftData

struct BrainDumpDetailView: View {
    let dump: BrainDump
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @State private var showDeleteConfirmation = false

    private var dateFormatter: DateFormatter {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }

    var body: some View {
        Form {
            Section {
                HStack {
                    Image(systemName: "calendar")
                        .foregroundStyle(.secondary)
                    Text(dateFormatter.string(from: dump.createdAt))
                        .foregroundStyle(.secondary)
                }
                if !dump.processingSummary.isEmpty {
                    HStack {
                        Image(systemName: "sparkles")
                            .foregroundStyle(.blue)
                        Text(dump.processingSummary)
                            .foregroundStyle(.primary)
                    }
                }
            }

            Section("Transcript") {
                Text(dump.transcript)
                    .font(.body)
                    .textSelection(.enabled)
            }
        }
        .navigationTitle("Brain Dump")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(role: .destructive) {
                    showDeleteConfirmation = true
                } label: {
                    Image(systemName: "trash")
                }
            }
        }
        .confirmationDialog(
            "Delete this brain dump?",
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                let sid = dump.supabaseId
                modelContext.delete(dump)
                try? modelContext.save()
                Task { await SupabaseService.shared.deleteBrainDump(sid) }
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The transcript will be permanently deleted. Tasks and contact notes already created from it will not be affected.")
        }
    }
}
