import Foundation
import SwiftData

// MARK: - Priority

enum Priority: String, Codable, CaseIterable, Comparable {
    case high   = "High"
    case medium = "Medium"
    case low    = "Low"

    static func < (lhs: Priority, rhs: Priority) -> Bool {
        let order: [Priority] = [.high, .medium, .low]
        return (order.firstIndex(of: lhs) ?? 0) < (order.firstIndex(of: rhs) ?? 0)
    }

    var systemImage: String {
        switch self {
        case .high:   return "arrow.up.circle.fill"
        case .medium: return "minus.circle.fill"
        case .low:    return "arrow.down.circle.fill"
        }
    }
}

// MARK: - Contact

@Model
final class Contact {
    // CloudKit rule: every stored property must have a default value (or be optional).
    // Giving each a default satisfies this without making the rest of the code optional-heavy.
    var id: UUID = UUID()
    var name: String = ""
    var photoData: Data?                    // already optional ✓

    // Location
    var city: String = ""
    var country: String = ""

    // Contact details
    var emails: [String] = [String]()
    var phones: [String] = [String]()
    var linkedInURL: String = ""
    var twitterURL: String = ""
    var instagramURL: String = ""

    // Professional
    var company: String = ""
    var jobTitle: String = ""

    // CRM fields
    var tags: [String] = [String]()
    var priorityRaw: String = Priority.medium.rawValue
    var howWeMet: String = ""
    var notes: String = ""

    // Relationship tracking — already optional ✓
    var lastContacted: Date?
    var lastMetInPerson: Date?
    var nextReconnect: Date?
    var birthday: Date?

    // Metadata
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    // CloudKit rule: to-many relationships must be optional
    @Relationship(deleteRule: .cascade)
    var interactions: [Interaction]?

    init(
        id: UUID = UUID(),
        name: String,
        city: String = "",
        country: String = "",
        emails: [String] = [],
        phones: [String] = [],
        linkedInURL: String = "",
        twitterURL: String = "",
        instagramURL: String = "",
        company: String = "",
        jobTitle: String = "",
        tags: [String] = [],
        priority: Priority = .medium,
        howWeMet: String = "",
        notes: String = "",
        lastContacted: Date? = nil,
        lastMetInPerson: Date? = nil,
        nextReconnect: Date? = nil,
        birthday: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.city = city
        self.country = country
        self.emails = emails
        self.phones = phones
        self.linkedInURL = linkedInURL
        self.twitterURL = twitterURL
        self.instagramURL = instagramURL
        self.company = company
        self.jobTitle = jobTitle
        self.tags = tags
        self.priorityRaw = priority.rawValue
        self.howWeMet = howWeMet
        self.notes = notes
        self.lastContacted = lastContacted
        self.lastMetInPerson = lastMetInPerson
        self.nextReconnect = nextReconnect
        self.birthday = birthday
        self.createdAt = Date()
        self.updatedAt = Date()
        self.interactions = []
    }

    // MARK: - Computed helpers

    var priority: Priority {
        get { Priority(rawValue: priorityRaw) ?? .medium }
        set { priorityRaw = newValue.rawValue; updatedAt = Date() }
    }

    var primaryEmail: String? { emails.first }
    var primaryPhone: String? { phones.first }

    var initials: String {
        let parts = name.components(separatedBy: " ").filter { !$0.isEmpty }
        switch parts.count {
        case 0: return "?"
        case 1: return String(parts[0].prefix(1)).uppercased()
        default: return (String(parts[0].prefix(1)) + String(parts[parts.count - 1].prefix(1))).uppercased()
        }
    }

    var daysSinceLastContact: Int? {
        guard let date = lastContacted else { return nil }
        return Calendar.current.dateComponents([.day], from: date, to: Date()).day
    }

    var isReconnectOverdue: Bool {
        guard let next = nextReconnect else { return false }
        return next < Date()
    }

    var locationDisplay: String {
        [city, country].filter { !$0.isEmpty }.joined(separator: ", ")
    }

    /// Always returns a non-optional array — safe to use everywhere in the UI
    var interactionsList: [Interaction] {
        interactions ?? []
    }
}

// MARK: - Interaction

@Model
final class Interaction {
    // All properties need defaults for CloudKit
    var id: UUID = UUID()
    var date: Date = Date()
    var typeRaw: String = InteractionType.note.rawValue
    var notes: String = ""
    var createdAt: Date = Date()

    @Relationship(inverse: \Contact.interactions)
    var contact: Contact?

    init(
        id: UUID = UUID(),
        date: Date = Date(),
        type: InteractionType = .note,
        notes: String = ""
    ) {
        self.id = id
        self.date = date
        self.typeRaw = type.rawValue
        self.notes = notes
        self.createdAt = Date()
    }

    var type: InteractionType {
        get { InteractionType(rawValue: typeRaw) ?? .note }
        set { typeRaw = newValue.rawValue }
    }
}

// MARK: - InteractionType

enum InteractionType: String, Codable, CaseIterable {
    case meeting    = "Meeting"
    case call       = "Call"
    case email      = "Email"
    case message    = "Message"
    case note       = "Note"
    case introduced = "Introduction"

    var systemImage: String {
        switch self {
        case .meeting:    return "person.2.fill"
        case .call:       return "phone.fill"
        case .email:      return "envelope.fill"
        case .message:    return "message.fill"
        case .note:       return "note.text"
        case .introduced: return "person.badge.plus"
        }
    }
}
