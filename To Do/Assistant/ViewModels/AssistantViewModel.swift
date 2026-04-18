import Foundation
import SwiftData
import Combine

@MainActor
final class AssistantViewModel: ObservableObject {
    @Published var messages:   [ChatMessage] = []
    @Published var isThinking: Bool = false

    var apiKey: String {
        get { UserDefaults.standard.string(forKey: "claude_api_key") ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: "claude_api_key") }
    }
    var hasAPIKey: Bool { !apiKey.isEmpty }

    private var executor:    ToolExecutor?
    private var apiMessages: [[String: Any]] = []   // full conversation for the API

    // Called by the view once modelContext is available
    func setContext(_ context: ModelContext) {
        executor = ToolExecutor(context: context)
    }

    // MARK: - Send

    func send(text: String) async {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, hasAPIKey else { return }

        messages.append(ChatMessage(role: "user", text: trimmed))
        apiMessages.append(["role": "user", "content": trimmed])

        let loadingID = UUID()
        messages.append(ChatMessage(role: "assistant", text: "", isLoading: true))
        isThinking = true

        do {
            try await runClaudeLoop()
        } catch {
            messages.removeLast()   // remove loading bubble
            messages.append(ChatMessage(role: "assistant",
                                        text: "⚠️ \(error.localizedDescription)",
                                        isError: true))
        }

        isThinking = false
    }

    func clearHistory() {
        messages    = []
        apiMessages = []
    }

    func saveAPIKey(_ key: String) {
        apiKey = key
    }

    // MARK: - Private: agentic Claude loop

    private func runClaudeLoop() async throws {
        var current = apiMessages

        while true {
            let response = try await ClaudeAPIService.send(messages: current, apiKey: apiKey)

            if response.toolUses.isEmpty {
                // Final text response — done
                let finalText = response.text ?? "Done."
                messages.removeLast()   // remove loading bubble
                messages.append(ChatMessage(role: "assistant", text: finalText))

                // Persist to full history
                current.append(["role": "assistant", "content": finalText])
                apiMessages = current
                return
            }

            // Build assistant content block for the API
            var assistantContent: [[String: Any]] = []
            if let t = response.text {
                assistantContent.append(["type": "text", "text": t])
            }
            for tu in response.toolUses {
                assistantContent.append([
                    "type":  "tool_use",
                    "id":    tu.id,
                    "name":  tu.name,
                    "input": tu.input
                ])
            }
            current.append(["role": "assistant", "content": assistantContent])

            // Execute tools and collect results
            var results: [[String: Any]] = []
            for tu in response.toolUses {
                let output = executor?.execute(name: tu.name, input: tu.input)
                    ?? "Error: no model context set."
                results.append([
                    "type":        "tool_result",
                    "tool_use_id": tu.id,
                    "content":     output
                ])
            }
            current.append(["role": "user", "content": results])
            // Loop — Claude will now generate a final response using tool results
        }
    }
}
