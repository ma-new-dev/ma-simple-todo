import Foundation
import SwiftData

@Model
final class BrainDump {
    var id: UUID = UUID()
    var supabaseId: UUID = UUID()
    var transcript: String = ""
    var processingSummary: String = ""    // e.g. "→ 3 tasks, 1 contact note"
    var processedAt: Date?
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    init(transcript: String, processingSummary: String = "", processedAt: Date? = nil) {
        self.id = UUID()
        self.supabaseId = UUID()
        self.transcript = transcript
        self.processingSummary = processingSummary
        self.processedAt = processedAt
        self.createdAt = Date()
        self.updatedAt = Date()
    }
}
