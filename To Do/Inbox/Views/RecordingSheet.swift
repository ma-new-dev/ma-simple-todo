import SwiftUI
import SwiftData

struct RecordingSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @Query(sort: \TodoList.sortOrder) private var lists: [TodoList]
    @Query(sort: \Contact.name)        private var contacts: [Contact]

    @StateObject private var recorder = RecordingService()

    @State private var manualTranscript: String = ""   // editable post-stop or for typed entries
    @State private var isProcessing = false
    @State private var processingError: String?
    @State private var parsedDump: ParsedDump?
    @State private var permissionRequested = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Spacer()

                // Mic visual + transcript
                VStack(spacing: 18) {
                    micVisual

                    transcriptArea
                }
                .padding(.horizontal)

                Spacer()

                actionButtons
            }
            .padding()
            .navigationTitle("Brain Dump")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        recorder.stop()
                        dismiss()
                    }
                }
            }
            .sheet(item: Binding(
                get: { parsedDump.map { ParsedDumpWrapper(dump: $0, transcript: bestTranscript) } },
                set: { _ in parsedDump = nil }
            )) { wrapper in
                StructuredReviewSheet(
                    transcript: wrapper.transcript,
                    parsed: wrapper.dump,
                    onDone: {
                        parsedDump = nil
                        dismiss()
                    }
                )
            }
            .alert("Couldn't process",
                   isPresented: Binding(get: { processingError != nil },
                                        set: { if !$0 { processingError = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(processingError ?? "")
            }
        }
    }

    // MARK: - Subviews

    private var micVisual: some View {
        ZStack {
            Circle()
                .fill(recorder.isRecording ? Color.red.opacity(0.15) : Color.blue.opacity(0.15))
                .frame(width: 140, height: 140)

            if recorder.isRecording {
                Circle()
                    .stroke(Color.red.opacity(0.4), lineWidth: 4)
                    .frame(width: 140, height: 140)
                    .scaleEffect(recorder.isRecording ? 1.2 : 1)
                    .opacity(recorder.isRecording ? 0 : 1)
                    .animation(
                        .easeOut(duration: 1.4).repeatForever(autoreverses: false),
                        value: recorder.isRecording
                    )
            }

            Image(systemName: recorder.isRecording ? "waveform" : "mic.fill")
                .font(.system(size: 44, weight: .semibold))
                .foregroundStyle(recorder.isRecording ? .red : .blue)
                .symbolEffect(.pulse, isActive: recorder.isRecording)
        }
    }

    private var transcriptArea: some View {
        ScrollView {
            VStack(spacing: 8) {
                if recorder.isRecording {
                    Text(recorder.transcript.isEmpty ? "Listening…" : recorder.transcript)
                        .font(.body)
                        .foregroundStyle(recorder.transcript.isEmpty ? .secondary : .primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .multilineTextAlignment(.leading)
                } else {
                    if !recorder.transcript.isEmpty || !manualTranscript.isEmpty {
                        TextField("Edit transcript…", text: editableTranscript, axis: .vertical)
                            .lineLimit(2...12)
                            .textFieldStyle(.plain)
                            .padding(8)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                            )
                    } else {
                        VStack(spacing: 6) {
                            Text("Tap the mic to start recording")
                                .foregroundStyle(.secondary)
                            Text("…or type your thoughts directly below")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        TextField("Type instead…", text: $manualTranscript, axis: .vertical)
                            .lineLimit(2...8)
                            .textFieldStyle(.plain)
                            .padding(8)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                            )
                    }
                }
            }
        }
        .frame(maxHeight: 240)
    }

    private var actionButtons: some View {
        HStack(spacing: 16) {
            // Mic toggle
            Button(action: toggleMic) {
                Label(
                    recorder.isRecording ? "Stop" : "Record",
                    systemImage: recorder.isRecording ? "stop.fill" : "mic.fill"
                )
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(recorder.isRecording ? Color.red : Color.blue)
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }

            // Process
            Button(action: process) {
                if isProcessing {
                    ProgressView().tint(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.green.opacity(0.7))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                } else {
                    Label("Process", systemImage: "sparkles")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(canProcess ? Color.green : Color.gray.opacity(0.4))
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
            }
            .disabled(!canProcess || isProcessing || recorder.isRecording)
        }
    }

    // MARK: - State helpers

    private var bestTranscript: String {
        let r = recorder.transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        let m = manualTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
        return r.isEmpty ? m : r
    }

    private var editableTranscript: Binding<String> {
        recorder.transcript.isEmpty
            ? $manualTranscript
            : Binding(get: { recorder.transcript }, set: { recorder.transcript = $0 })
    }

    private var canProcess: Bool {
        !bestTranscript.isEmpty
    }

    // MARK: - Actions

    private func toggleMic() {
        if recorder.isRecording {
            recorder.stop()
        } else {
            Task {
                if !permissionRequested {
                    permissionRequested = true
                    let ok = await recorder.requestPermissions()
                    guard ok else { return }
                }
                recorder.start()
            }
        }
    }

    private func process() {
        let transcript = bestTranscript
        guard !transcript.isEmpty else { return }
        isProcessing = true
        Task {
            do {
                let result = try await BrainDumpProcessor.process(
                    transcript: transcript,
                    lists: lists.map(\.name),
                    contacts: contacts.map(\.name)
                )
                isProcessing = false
                parsedDump = result
            } catch {
                isProcessing = false
                processingError = error.localizedDescription
            }
        }
    }
}

private struct ParsedDumpWrapper: Identifiable {
    let id = UUID()
    let dump: ParsedDump
    let transcript: String
}

#Preview {
    RecordingSheet()
        .modelContainer(for: [TodoList.self, TaskItem.self, Contact.self, Interaction.self, BrainDump.self], inMemory: true)
}
