import Foundation

struct ChatMessage: Identifiable {
    let id = UUID()
    let role: String   // "user" or "assistant"
    var text: String
    var isLoading: Bool = false
    var isError: Bool = false
}
