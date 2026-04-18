import Foundation

// MARK: - Claude API Service

enum APIError: LocalizedError {
    case invalidResponse
    case httpError(Int, String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Invalid response from Claude."
        case .httpError(let code, let msg):
            return "API error \(code): \(msg)"
        }
    }
}

struct ClaudeAPIService {

    static let model   = "claude-sonnet-4-5"
    static let apiURL  = "https://api.anthropic.com/v1/messages"
    static let version = "2023-06-01"

    // MARK: - Tool definitions

    static var tools: [[String: Any]] {
        [
            tool("list_lists",
                 "List all to-do lists with their active task counts.",
                 properties: [:], required: []),

            tool("add_list",
                 "Create a new to-do list.",
                 properties: [
                     "name": ["type": "string", "description": "Name of the new list"]
                 ], required: ["name"]),

            tool("add_task",
                 "Add a task to an existing to-do list.",
                 properties: [
                     "list_name": ["type": "string", "description": "Name of the list"],
                     "title":     ["type": "string", "description": "Task title"]
                 ], required: ["list_name", "title"]),

            tool("list_tasks",
                 "List active tasks, optionally filtered to one list.",
                 properties: [
                     "list_name": ["type": "string", "description": "List name (omit for all lists)"]
                 ], required: []),

            tool("complete_task",
                 "Mark a task as complete.",
                 properties: [
                     "task_title": ["type": "string", "description": "Full or partial task title"],
                     "list_name":  ["type": "string", "description": "List name to narrow search (optional)"]
                 ], required: ["task_title"]),

            tool("delete_task",
                 "Delete a task permanently.",
                 properties: [
                     "task_title": ["type": "string", "description": "Full or partial task title"],
                     "list_name":  ["type": "string", "description": "List name to narrow search (optional)"]
                 ], required: ["task_title"]),

            tool("add_contact",
                 "Add a new contact to the personal CRM.",
                 properties: [
                     "name":           ["type": "string",  "description": "Full name"],
                     "company":        ["type": "string",  "description": "Company or organisation"],
                     "job_title":      ["type": "string",  "description": "Job title or role"],
                     "email":          ["type": "string",  "description": "Primary email address"],
                     "phone":          ["type": "string",  "description": "Primary phone number"],
                     "city":           ["type": "string",  "description": "City"],
                     "country":        ["type": "string",  "description": "Country"],
                     "priority":       ["type": "string",  "enum": ["High", "Medium", "Low"],
                                        "description": "Contact priority"],
                     "notes":          ["type": "string",  "description": "Free-form notes"],
                     "how_we_met":     ["type": "string",  "description": "How you met this person"],
                     "next_reconnect": ["type": "string",  "description": "Next follow-up date (e.g. May 1, 2026)"],
                     "tags":           ["type": "string",  "description": "Comma-separated tags"]
                 ], required: ["name"]),

            tool("list_contacts",
                 "List contacts in the CRM, optionally filtered by priority.",
                 properties: [
                     "priority": ["type": "string", "enum": ["High", "Medium", "Low"],
                                  "description": "Filter by priority (omit for all)"],
                     "search":   ["type": "string", "description": "Name or company search term"]
                 ], required: []),

            tool("update_contact",
                 "Update fields on an existing contact.",
                 properties: [
                     "name":           ["type": "string", "description": "Current contact name to look up"],
                     "new_name":       ["type": "string", "description": "New name"],
                     "company":        ["type": "string", "description": "New company"],
                     "job_title":      ["type": "string", "description": "New job title"],
                     "email":          ["type": "string", "description": "New primary email"],
                     "phone":          ["type": "string", "description": "New primary phone"],
                     "city":           ["type": "string", "description": "New city"],
                     "country":        ["type": "string", "description": "New country"],
                     "priority":       ["type": "string", "enum": ["High", "Medium", "Low"]],
                     "notes":          ["type": "string", "description": "New notes"],
                     "next_reconnect": ["type": "string", "description": "New follow-up date"]
                 ], required: ["name"]),

            tool("log_interaction",
                 "Log an interaction with a contact (call, meeting, email, etc.).",
                 properties: [
                     "contact_name": ["type": "string", "description": "Contact name"],
                     "type":         ["type": "string",
                                      "enum": ["Meeting", "Call", "Email", "Message", "Note", "Introduction"],
                                      "description": "Interaction type"],
                     "notes":        ["type": "string", "description": "Notes about the interaction"],
                     "date":         ["type": "string", "description": "Date of interaction (defaults to today)"]
                 ], required: ["contact_name", "type"])
        ]
    }

    // MARK: - API Call

    /// Sends a conversation to Claude. Returns (text, toolUses).
    static func send(
        messages: [[String: Any]],
        apiKey: String
    ) async throws -> (text: String?, toolUses: [(id: String, name: String, input: [String: Any])]) {

        let systemPrompt = """
        You are a helpful personal assistant embedded in a productivity app. \
        You manage to-do lists/tasks and a personal CRM (contacts & interactions).

        Today is \(formattedToday()).

        Use the provided tools to act on requests. After completing an action, \
        confirm briefly in plain language. Be concise.
        """

        let body: [String: Any] = [
            "model":      model,
            "max_tokens": 1024,
            "system":     systemPrompt,
            "messages":   messages,
            "tools":      tools
        ]

        let jsonData = try JSONSerialization.data(withJSONObject: body)

        var req = URLRequest(url: URL(string: apiURL)!)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(apiKey,   forHTTPHeaderField: "x-api-key")
        req.setValue(version,  forHTTPHeaderField: "anthropic-version")
        req.httpBody = jsonData

        let (data, response) = try await URLSession.shared.data(for: req)

        guard let http = response as? HTTPURLResponse else { throw APIError.invalidResponse }
        guard http.statusCode == 200 else {
            let msg = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw APIError.httpError(http.statusCode, msg)
        }

        guard let json    = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let content = json["content"] as? [[String: Any]] else {
            throw APIError.invalidResponse
        }

        var text: String? = nil
        var toolUses: [(id: String, name: String, input: [String: Any])] = []

        for block in content {
            switch block["type"] as? String {
            case "text":
                text = block["text"] as? String
            case "tool_use":
                let id    = block["id"]    as? String ?? ""
                let name  = block["name"]  as? String ?? ""
                let input = block["input"] as? [String: Any] ?? [:]
                toolUses.append((id: id, name: name, input: input))
            default:
                break
            }
        }

        return (text: text, toolUses: toolUses)
    }

    // MARK: - Helpers

    private static func tool(
        _ name: String,
        _ description: String,
        properties: [String: Any],
        required: [String]
    ) -> [String: Any] {
        [
            "name":         name,
            "description":  description,
            "input_schema": [
                "type":       "object",
                "properties": properties,
                "required":   required
            ]
        ]
    }

    private static func formattedToday() -> String {
        let f = DateFormatter()
        f.dateStyle = .long
        return f.string(from: Date())
    }
}
