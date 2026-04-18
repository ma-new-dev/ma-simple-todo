import SwiftUI
import SwiftData

struct AssistantSheetView: View {
    @ObservedObject var viewModel: AssistantViewModel
    @Environment(\.modelContext) private var modelContext

    @StateObject private var voice = VoiceInputService()
    @State private var inputText = ""
    @State private var showKeySetup = false
    @FocusState private var fieldFocused: Bool

    var body: some View {
        NavigationStack {
            Group {
                if !viewModel.hasAPIKey {
                    APIKeySetupView { key in
                        viewModel.saveAPIKey(key)
                    }
                } else {
                    VStack(spacing: 0) {
                        messageList
                        Divider()
                        inputBar
                    }
                }
            }
            .navigationTitle("Assistant")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("Clear conversation", role: .destructive) {
                            viewModel.clearHistory()
                        }
                        Divider()
                        Button("Change API Key") { showKeySetup = true }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
            .sheet(isPresented: $showKeySetup) {
                APIKeySetupView { key in
                    viewModel.saveAPIKey(key)
                    showKeySetup = false
                }
                .presentationDetents([.medium])
            }
        }
        .onAppear {
            viewModel.setContext(modelContext)
        }
    }

    // MARK: - Message list

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 12) {
                    if viewModel.messages.isEmpty {
                        emptyState
                    }
                    ForEach(viewModel.messages) { msg in
                        ChatBubbleView(message: msg)
                            .id(msg.id)
                    }
                }
                .padding(.horizontal)
                .padding(.top, 12)
                .padding(.bottom, 8)
            }
            .onChange(of: viewModel.messages.count) { _, _ in
                if let last = viewModel.messages.last {
                    withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "bubble.left.and.sparkles")
                .font(.system(size: 48))
                .foregroundStyle(.blue.opacity(0.7))
            Text("What can I help you with?")
                .font(.headline)
            VStack(alignment: .leading, spacing: 6) {
                suggestionChip("Add 'Call dentist' to Personal list")
                suggestionChip("Add John Smith, VP at Acme, high priority")
                suggestionChip("Show all my tasks")
                suggestionChip("Log a call with Sarah")
            }
        }
        .padding(.top, 60)
        .padding(.bottom, 20)
    }

    private func suggestionChip(_ text: String) -> some View {
        Button {
            inputText = text
            sendMessage()
        } label: {
            Text(text)
                .font(.caption)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color(.systemGray5))
                .clipShape(Capsule())
                .foregroundStyle(.primary)
        }
    }

    // MARK: - Input bar

    private var inputBar: some View {
        HStack(spacing: 10) {
            // Mic button
            Button {
                if voice.isRecording {
                    voice.stopRecording()
                    if !voice.transcript.isEmpty {
                        inputText = voice.transcript
                        voice.transcript = ""
                    }
                } else {
                    Task {
                        let ok = await voice.requestPermissions()
                        if ok { voice.startRecording() }
                    }
                }
            } label: {
                Image(systemName: voice.isRecording ? "stop.circle.fill" : "mic.circle.fill")
                    .font(.system(size: 30))
                    .foregroundStyle(voice.isRecording ? .red : .blue)
                    .symbolEffect(.pulse, isActive: voice.isRecording)
            }

            // Text field
            TextField(voice.isRecording ? "Listening…" : "Message…",
                      text: voice.isRecording ? $voice.transcript : $inputText)
                .textFieldStyle(.roundedBorder)
                .focused($fieldFocused)
                .submitLabel(.send)
                .onSubmit(sendMessage)
                .disabled(voice.isRecording)

            // Send button
            Button(action: sendMessage) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 30))
                    .foregroundStyle(canSend ? .blue : Color(.systemGray3))
            }
            .disabled(!canSend)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(.bar)
    }

    private var canSend: Bool {
        let text = voice.isRecording ? voice.transcript : inputText
        return !text.trimmingCharacters(in: .whitespaces).isEmpty && !viewModel.isThinking
    }

    private func sendMessage() {
        let text: String
        if voice.isRecording {
            voice.stopRecording()
            text = voice.transcript.isEmpty ? inputText : voice.transcript
            voice.transcript = ""
        } else {
            text = inputText
        }

        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }

        inputText   = ""
        fieldFocused = false

        Task { await viewModel.send(text: trimmed) }
    }
}
