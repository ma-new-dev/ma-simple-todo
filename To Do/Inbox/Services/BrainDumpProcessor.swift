import Foundation

// Calls the Cloudflare Worker's /process-brain-dump endpoint.
// Returns a ParsedDump or throws.

enum BrainDumpProcessorError: LocalizedError {
    case invalidResponse
    case httpError(Int, String)
    case decodingFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:        return "Invalid response from server."
        case .httpError(let c, let m): return "Server error \(c): \(m)"
        case .decodingFailed(let s):   return "Could not parse server response: \(s)"
        }
    }
}

struct BrainDumpProcessor {
    static var endpoint: String { "\(Secrets.workerURL)/process-brain-dump" }
    static var authKey: String  { Secrets.workerAuthKey }

    /// Send a transcript to the Worker for AI structuring.
    /// - Parameters:
    ///   - transcript: the raw spoken text
    ///   - lists: known list names (helps the AI route tasks)
    ///   - contacts: known contact names (helps the AI match people)
    static func process(transcript: String, lists: [String], contacts: [String]) async throws -> ParsedDump {
        guard !transcript.trimmingCharacters(in: .whitespaces).isEmpty else {
            return ParsedDump.empty
        }

        let body: [String: Any] = [
            "transcript": transcript,
            "lists": lists,
            "contacts": contacts.map { ["name": $0] },
        ]
        let bodyData = try JSONSerialization.data(withJSONObject: body)

        var req = URLRequest(url: URL(string: endpoint)!)
        req.httpMethod = "POST"
        req.timeoutInterval = 30
        req.setValue("application/json",        forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(authKey)",       forHTTPHeaderField: "Authorization")
        req.httpBody = bodyData

        let (data, response) = try await URLSession.shared.data(for: req)

        guard let http = response as? HTTPURLResponse else {
            throw BrainDumpProcessorError.invalidResponse
        }
        guard (200...299).contains(http.statusCode) else {
            let msg = String(data: data, encoding: .utf8) ?? "Unknown"
            throw BrainDumpProcessorError.httpError(http.statusCode, msg)
        }

        do {
            return try JSONDecoder().decode(ParsedDump.self, from: data)
        } catch {
            let raw = String(data: data, encoding: .utf8) ?? "<binary>"
            throw BrainDumpProcessorError.decodingFailed(raw)
        }
    }
}
