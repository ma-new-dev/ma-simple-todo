import SwiftUI
import SwiftData

struct RecordingSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @Query(sort: \TodoList.sortOrder) private var lists: [TodoList]
    @Query(sort: \Contact.name)        private var contacts: [Contact]

    @StateObject private var recorder = RecordingService()

    @State private var isProcessing = false
    @State private var savedSummary: String?
    @State private var errorMessage: String?
    @State private var permissionRequested = false
    @State private var isHolding = false   // true while finger is on the button

    var body: some View {
        NavigationStack {
            VStack(spacing: 28) {
                Spacer()

                statusArea

                pushToTalkButton

                hintText

                Spacer()
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 40)
            .navigationTitle("Brain Dump")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    // MARK: - Status area (transcript / processing / saved / error)

    @ViewBuilder
    private var statusArea: some View {
        if isProcessing {
            VStack(spacing: 14) {
                ProgressView().controlSize(.large)
                Text("Processing…")
                    .font(.headline)
                    .foregroundStyle(.secondary)
                if !recorder.transcript.isEmpty {
                    Text(recorder.transcript)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                        .lineLimit(4)
                        .padding(.top, 4)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 180)
            .padding()
            .background(Color(.systemGray6))
            .clipShape(RoundedRectangle(cornerRadius: 16))
        } else if let summary = savedSummary {
            VStack(spacing: 12) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(.green)
                Text("Saved")
                    .font(.title3.bold())
                Text(summary)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity, minHeight: 180)
            .padding()
            .background(Color.green.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 16))
        } else if let err = errorMessage {
            VStack(spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 36))
                    .foregroundStyle(.orange)
                Text("Couldn't process")
                    .font(.headline)
                Text(err)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Text("Your transcript was still saved to the Inbox.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)
            }
            .frame(maxWidth: .infinity, minHeight: 180)
            .padding()
            .background(Color.orange.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 16))
        } else if recorder.isRecording || !recorder.transcript.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                if recorder.isRecording {
                    HStack(spacing: 6) {
                        Circle().fill(.red).frame(width: 8, height: 8)
                            .symbolEffect(.pulse, isActive: true)
                        Text("Listening…").font(.caption.bold()).foregroundStyle(.red)
                    }
                }
                ScrollView {
                    Text(recorder.transcript.isEmpty ? "…" : recorder.transcript)
                        .font(.body)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 140)
            }
            .frame(maxWidth: .infinity, minHeight: 180)
            .padding()
            .background(Color(.systemGray6))
            .clipShape(RoundedRectangle(cornerRadius: 16))
        } else {
            VStack(spacing: 8) {
                Image(systemName: "mic.fill")
                    .font(.system(size: 36))
                    .foregroundStyle(.blue.opacity(0.6))
                Text("Hold to record")
                    .font(.headline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, minHeight: 180)
        }
    }

    // MARK: - Push-to-talk button

    private var pushToTalkButton: some View {
        ZStack {
            // Outer pulse ring while recording
            if recorder.isRecording {
                Circle()
                    .stroke(Color.red.opacity(0.35), lineWidth: 6)
                    .frame(width: 200, height: 200)
                    .scaleEffect(1.1)
                    .opacity(0)
                    .animation(
                        .easeOut(duration: 1.2).repeatForever(autoreverses: false),
                        value: recorder.isRecording
                    )
            }

            Circle()
                .fill(recorder.isRecording ? Color.red : Color.blue)
                .frame(width: 160, height: 160)
                .shadow(color: .black.opacity(0.25), radius: 10, y: 4)

            Image(systemName: "mic.fill")
                .font(.system(size: 56, weight: .semibold))
                .foregroundStyle(.white)
        }
        .scaleEffect(isHolding ? 1.08 : 1.0)
        .animation(.spring(response: 0.25, dampingFraction: 0.7), value: isHolding)
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    guard !isHolding && !isProcessing else { return }
                    isHolding = true
                    startRecording()
                }
                .onEnded { _ in
                    guard isHolding else { return }
                    isHolding = false
                    stopAndProcess()
                }
        )
        .accessibilityLabel("Hold to record brain dump")
        .accessibilityHint("Press and hold this button while speaking. Release to save.")
    }

    private var hintText: some View {
        Text("Press and hold while you speak.\nRelease to save.")
            .font(.footnote)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
    }

    // MARK: - Recording control

    private func startRecording() {
        // Reset previous state
        savedSummary = nil
        errorMessage = nil
        recorder.transcript = ""

        Task {
            if !permissionRequested {
                permissionRequested = true
                let ok = await recorder.requestPermissions()
                guard ok else {
                    isHolding = false
                    errorMessage = "Microphone or speech recognition permission denied. Enable in Settings."
                    return
                }
            }
            recorder.start()
        }

        // Light haptic on press
        let gen = UIImpactFeedbackGenerator(style: .medium)
        gen.impactOccurred()
    }

    private func stopAndProcess() {
        recorder.stop()
        let transcript = recorder.transcript.trimmingCharacters(in: .whitespacesAndNewlines)

        // Light haptic on release
        let gen = UIImpactFeedbackGenerator(style: .light)
        gen.impactOccurred()

        guard !transcript.isEmpty else { return }   // empty press, nothing to do

        isProcessing = true
        Task {
            do {
                let result = try await BrainDumpProcessor.process(
                    transcript: transcript,
                    lists: lists.map(\.name),
                    contacts: contacts.map(\.name)
                )
                let summary = applyResults(transcript: transcript, parsed: result)
                isProcessing = false
                savedSummary = summary

                // Success haptic
                let success = UINotificationFeedbackGenerator()
                success.notificationOccurred(.success)

                // Auto-dismiss after a beat so user gets confirmation
                try? await Task.sleep(nanoseconds: 1_400_000_000)
                if savedSummary != nil { dismiss() }
            } catch {
                // Save raw transcript anyway so it isn't lost
                _ = saveDumpOnly(transcript: transcript, error: error.localizedDescription)
                isProcessing = false
                errorMessage = error.localizedDescription
            }
        }
    }

    // MARK: - Apply AI results to SwiftData + Supabase

    private func applyResults(transcript: String, parsed: ParsedDump) -> String {
        // 1) Tasks
        for p in parsed.tasks {
            let title = p.title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty else { continue }

            let suggested = p.list_name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let parentList = resolveOrCreateList(name: suggested)
            guard let parent = parentList else { continue }

            let nextOrder = ((parent.tasks ?? []).map(\.sortOrder).min() ?? 1) - 1
            let task = TaskItem(title: title, list: parent, sortOrder: nextOrder)
            modelContext.insert(task)
            Task { await SupabaseService.shared.push(task: task) }
        }

        // 2) Contact notes
        for p in parsed.contact_notes {
            let note = p.note.trimmingCharacters(in: .whitespacesAndNewlines)
            let name = p.contact_name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !note.isEmpty, !name.isEmpty else { continue }

            let contact = resolveOrCreateContact(name: name)
            let interaction = Interaction(date: .now, type: .note, notes: note)
            interaction.contact = contact
            modelContext.insert(interaction)
            contact.lastContacted = .now
            contact.updatedAt = .now
            Task { await SupabaseService.shared.push(interaction: interaction) }
            Task { await SupabaseService.shared.push(contact: contact) }
        }

        // 3) Save the brain dump itself (combine transcript + floating notes)
        var combined = transcript
        for n in parsed.notes {
            let t = n.content.trimmingCharacters(in: .whitespacesAndNewlines)
            if !t.isEmpty { combined += "\n• \(t)" }
        }

        let summary = formatSummary(
            tasks: parsed.tasks.count,
            contacts: parsed.contact_notes.count,
            notes: parsed.notes.count
        )

        let dump = BrainDump(transcript: combined, processingSummary: summary, processedAt: .now)
        modelContext.insert(dump)
        try? modelContext.save()
        Task { await SupabaseService.shared.push(brainDump: dump) }

        return summary
    }

    // Save just the raw transcript when AI processing fails
    private func saveDumpOnly(transcript: String, error: String) -> BrainDump {
        let dump = BrainDump(
            transcript: transcript,
            processingSummary: "Processing failed — try again later",
            processedAt: nil
        )
        modelContext.insert(dump)
        try? modelContext.save()
        Task { await SupabaseService.shared.push(brainDump: dump) }
        return dump
    }

    // MARK: - Helpers

    private func resolveOrCreateList(name: String) -> TodoList? {
        if name.isEmpty {
            return lists.first   // fall back to first list
        }
        if let existing = lists.first(where: { $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame }) {
            return existing
        }
        // Create the list the AI suggested if it doesn't exist yet
        let newOrder = (lists.map(\.sortOrder).min() ?? 1) - 1
        let list = TodoList(name: name, sortOrder: newOrder)
        modelContext.insert(list)
        Task { await SupabaseService.shared.push(list: list) }
        return list
    }

    private func resolveOrCreateContact(name: String) -> Contact {
        if let existing = contacts.first(where: { $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame }) {
            return existing
        }
        let c = Contact(name: name)
        modelContext.insert(c)
        Task { await SupabaseService.shared.push(contact: c) }
        return c
    }

    private func formatSummary(tasks: Int, contacts: Int, notes: Int) -> String {
        var bits: [String] = []
        if tasks > 0    { bits.append("\(tasks) task\(tasks == 1 ? "" : "s")") }
        if contacts > 0 { bits.append("\(contacts) contact note\(contacts == 1 ? "" : "s")") }
        if notes > 0    { bits.append("\(notes) note\(notes == 1 ? "" : "s")") }
        return bits.isEmpty ? "Transcript saved to Inbox" : bits.joined(separator: ", ")
    }
}

#Preview {
    RecordingSheet()
        .modelContainer(for: [TodoList.self, TaskItem.self, Contact.self, Interaction.self, BrainDump.self], inMemory: true)
}
