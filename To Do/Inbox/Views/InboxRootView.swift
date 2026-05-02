import SwiftUI
import SwiftData

struct InboxRootView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \BrainDump.createdAt, order: .reverse) private var dumps: [BrainDump]

    @State private var showRecording = false
    @State private var searchText = ""

    var filteredDumps: [BrainDump] {
        guard !searchText.isEmpty else { return dumps }
        return dumps.filter {
            $0.transcript.localizedCaseInsensitiveContains(searchText) ||
            $0.processingSummary.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if dumps.isEmpty {
                    emptyState
                } else {
                    List {
                        ForEach(filteredDumps) { dump in
                            NavigationLink {
                                BrainDumpDetailView(dump: dump)
                            } label: {
                                dumpRow(dump)
                            }
                        }
                        .onDelete(perform: deleteDumps)
                    }
                    .searchable(text: $searchText, prompt: "Search brain dumps")
                }
            }
            .navigationTitle("Inbox")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showRecording = true
                    } label: {
                        Label("New", systemImage: "plus")
                    }
                }
            }
            .sheet(isPresented: $showRecording) {
                RecordingSheet()
                    .presentationDetents([.large])
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "tray")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("Your Inbox is empty")
                .font(.headline)
            Text("Tap the mic button to do a quick brain dump.\nThe AI will turn your thoughts into tasks and notes.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button {
                showRecording = true
            } label: {
                Label("New Brain Dump", systemImage: "mic.fill")
                    .font(.headline)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .background(Color.blue)
                    .foregroundStyle(.white)
                    .clipShape(Capsule())
            }
            .padding(.top, 8)
        }
        .padding()
    }

    private func dumpRow(_ dump: BrainDump) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(relativeDate(dump.createdAt))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                if !dump.processingSummary.isEmpty {
                    Text(dump.processingSummary)
                        .font(.caption2)
                        .foregroundStyle(.blue)
                }
            }
            Text(snippet(dump.transcript))
                .font(.body)
                .lineLimit(2)
                .foregroundStyle(.primary)
        }
        .padding(.vertical, 4)
    }

    private func snippet(_ text: String) -> String {
        let cleaned = text.replacingOccurrences(of: "\n", with: " ")
        if cleaned.count > 140 {
            return String(cleaned.prefix(140)) + "…"
        }
        return cleaned
    }

    private func relativeDate(_ date: Date) -> String {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .short
        return f.localizedString(for: date, relativeTo: .now)
    }

    private func deleteDumps(at offsets: IndexSet) {
        for index in offsets {
            let dump = filteredDumps[index]
            let sid = dump.supabaseId
            modelContext.delete(dump)
            Task { await SupabaseService.shared.deleteBrainDump(sid) }
        }
        try? modelContext.save()
    }
}

#Preview {
    InboxRootView()
        .modelContainer(for: [TodoList.self, TaskItem.self, Contact.self, Interaction.self, BrainDump.self], inMemory: true)
}
