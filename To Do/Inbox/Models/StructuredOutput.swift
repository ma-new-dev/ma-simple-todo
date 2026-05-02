import Foundation

// MARK: - Codable mirrors of the AI's JSON response
// (Matches the shape returned by /process-brain-dump on the Worker)

struct ParsedTask: Codable, Identifiable {
    var id = UUID()
    var title: String
    var list_name: String?

    enum CodingKeys: String, CodingKey { case title, list_name }
}

struct ParsedContactNote: Codable, Identifiable {
    var id = UUID()
    var contact_name: String
    var note: String

    enum CodingKeys: String, CodingKey { case contact_name, note }
}

struct ParsedFloatingNote: Codable, Identifiable {
    var id = UUID()
    var content: String

    enum CodingKeys: String, CodingKey { case content }
}

struct ParsedDump: Codable {
    var tasks: [ParsedTask]
    var contact_notes: [ParsedContactNote]
    var notes: [ParsedFloatingNote]

    static let empty = ParsedDump(tasks: [], contact_notes: [], notes: [])
}
