import Foundation

nonisolated enum ClaudeError: LocalizedError {
    case missingKey
    case refusal
    case truncated
    case http(status: Int, message: String)
    case emptyResponse
    case decoding(String)

    var errorDescription: String? {
        switch self {
        case .missingKey:
            "Add your Anthropic API key in Settings first."
        case .refusal:
            "Claude declined this request. Try again later."
        case .truncated:
            "Claude's answer was cut off. Try again."
        case .http(let status, let message):
            status == 401
                ? "Anthropic rejected the API key. Check it in Settings."
                : "Anthropic returned \(status). \(message.prefix(200))"
        case .emptyResponse:
            "Claude returned an empty response. Try again."
        case .decoding(let detail):
            "Could not read Claude's response. \(detail.prefix(200))"
        }
    }
}

/// Raw HTTP against the Anthropic Messages API (there is no Swift SDK). Every call in the
/// app is one structured-output request: a system prompt, one user message, and a JSON
/// schema the answer must match.
nonisolated enum ClaudeClient {
    private static let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!
    static let model = "claude-opus-5-5"

    /// Sends one request and decodes the JSON answer into `T`.
    ///
    /// Opus 5.5 always thinks; `effort` is the only depth control and defaults to medium
    /// on this model, so it is always set explicitly. `max_tokens` covers thinking and
    /// output together. Server-side fallback is on so a safety-classifier refusal is
    /// retried on another model rather than surfacing as an error.
    static func structured<T: Decodable>(
        _ type: T.Type,
        system: String,
        user: String,
        schema: [String: Any],
        effort: String = "medium",
        maxTokens: Int = 16_000
    ) async throws -> T {
        guard let key = KeychainStore.get(.anthropicAPIKey) else { throw ClaudeError.missingKey }

        let body: [String: Any] = [
            "model": model,
            "max_tokens": maxTokens,
            "system": [[
                "type": "text",
                "text": system,
                "cache_control": ["type": "ephemeral"],
            ]],
            "output_config": [
                "effort": effort,
                "format": ["type": "json_schema", "schema": schema],
            ],
            "fallbacks": "default",
            "messages": [["role": "user", "content": user]],
        ]

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 180
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(key, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("server-side-fallback-2026-07-01", forHTTPHeaderField: "anthropic-beta")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw ClaudeError.http(status: http.statusCode, message: String(data: data, encoding: .utf8) ?? "")
        }

        let decoded: APIResponse
        do {
            decoded = try JSONDecoder().decode(APIResponse.self, from: data)
        } catch {
            throw ClaudeError.decoding(String(describing: error))
        }

        // A refusal is HTTP 200 with empty or partial content, so check stop_reason before
        // reading anything. With thinking on, the answer is the last text block.
        switch decoded.stopReason {
        case "refusal":    throw ClaudeError.refusal
        case "max_tokens": throw ClaudeError.truncated
        default:           break
        }
        guard let text = decoded.content.last(where: { $0.type == "text" })?.text, !text.isEmpty else {
            throw ClaudeError.emptyResponse
        }
        do {
            return try JSONDecoder().decode(T.self, from: Data(text.utf8))
        } catch {
            throw ClaudeError.decoding(String(describing: error))
        }
    }

    private struct APIResponse: Decodable {
        struct Block: Decodable {
            let type: String
            let text: String?
        }
        let content: [Block]
        let stopReason: String?

        enum CodingKeys: String, CodingKey {
            case content
            case stopReason = "stop_reason"
        }
    }
}
