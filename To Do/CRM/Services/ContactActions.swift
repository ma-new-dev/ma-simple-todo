import Foundation
import SwiftData

/// The quick edits the table, catch-up mode and swipe actions share, so "mark contacted" or
/// "snooze" means the same thing everywhere. Each works on one contact or many, saves once,
/// and keeps reconnect reminders in step with the dates it writes.
enum ContactActions {

    /// Snooze lengths offered wherever a reconnect date can be pushed out.
    enum Snooze: Int, CaseIterable, Identifiable {
        case oneWeek = 7
        case twoWeeks = 14
        case oneMonth = 30
        case threeMonths = 90

        var id: Int { rawValue }

        var title: String {
            switch self {
            case .oneWeek:     return "1 week"
            case .twoWeeks:    return "2 weeks"
            case .oneMonth:    return "1 month"
            case .threeMonths: return "3 months"
            }
        }
    }

    // MARK: - Contacted

    /// Records that he reached out today: logs an interaction, moves `lastContacted`, and
    /// clears a reconnect date that is due within the next week — the reach-out was the
    /// reconnect. A reconnect further out is left alone, since that is a later plan.
    static func markContacted(
        _ contacts: [Contact],
        type: InteractionType = .message,
        note: String = "",
        in context: ModelContext
    ) {
        let now = Date()
        let dueHorizon = Calendar.current.date(byAdding: .day, value: 7, to: now) ?? now

        for contact in contacts {
            let interaction = Interaction(date: now, type: type, notes: note)
            if contact.interactions == nil { contact.interactions = [] }
            contact.interactions?.append(interaction)

            contact.lastContacted = now
            if type == .meeting { contact.lastMetInPerson = now }

            if let next = contact.nextReconnect, next <= dueHorizon {
                NotificationService.shared.cancelReconnect(id: contact.id)
                contact.nextReconnect = nil
            }
            contact.updatedAt = now
        }
        save(context)
    }

    /// Adds a note to the timeline without counting it as contact.
    static func logNote(_ note: String, on contact: Contact, in context: ModelContext) {
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let interaction = Interaction(date: Date(), type: .note, notes: trimmed)
        if contact.interactions == nil { contact.interactions = [] }
        contact.interactions?.append(interaction)
        contact.updatedAt = Date()
        save(context)
    }

    // MARK: - Reconnect

    /// Sets the reconnect date to `days` from today and schedules the 9am reminder.
    static func snooze(_ contacts: [Contact], _ snooze: Snooze, in context: ModelContext) {
        let date = Calendar.current.date(byAdding: .day, value: snooze.rawValue, to: Date()) ?? Date()
        setReconnect(contacts, to: date, in: context)
    }

    static func setReconnect(_ contacts: [Contact], to date: Date?, in context: ModelContext) {
        for contact in contacts {
            contact.nextReconnect = date
            contact.updatedAt = Date()
        }
        save(context)

        // Read the ids and names before suspending: the models are main-actor objects and
        // a contact deleted meanwhile must not be touched after the await.
        let targets = contacts.map { (id: $0.id, name: $0.name) }
        if let date {
            Task {
                for target in targets {
                    await NotificationService.shared.scheduleReconnect(id: target.id, name: target.name, date: date)
                }
            }
        } else {
            targets.forEach { NotificationService.shared.cancelReconnect(id: $0.id) }
        }
    }

    // MARK: - Fields

    static func setPriority(_ contacts: [Contact], _ priority: Priority, in context: ModelContext) {
        contacts.forEach { $0.priority = priority }
        save(context)
    }

    static func setLastContacted(_ contacts: [Contact], to date: Date?, in context: ModelContext) {
        for contact in contacts {
            contact.lastContacted = date
            contact.updatedAt = Date()
        }
        save(context)
    }

    static func addTag(_ tag: String, to contacts: [Contact], in context: ModelContext) {
        let trimmed = tag.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        for contact in contacts where !contact.tags.contains(trimmed) {
            contact.tags.append(trimmed)
            contact.updatedAt = Date()
        }
        save(context)
    }

    static func removeTag(_ tag: String, from contacts: [Contact], in context: ModelContext) {
        for contact in contacts where contact.tags.contains(tag) {
            contact.tags.removeAll { $0 == tag }
            contact.updatedAt = Date()
        }
        save(context)
    }

    static func delete(_ contacts: [Contact], in context: ModelContext) {
        for contact in contacts {
            // Cancel first: once the model is deleted its id is no longer readable.
            NotificationService.shared.cancelReconnect(id: contact.id)
            context.delete(contact)
        }
        save(context)
    }

    // MARK: - Catch-up queue

    /// Who catch-up mode walks through, most urgent first: overdue reconnects (oldest
    /// first), then reconnects due today, then high-priority people not contacted in 60
    /// days who have no reconnect planned.
    static func catchUpQueue(from contacts: [Contact], now: Date = Date()) -> [Contact] {
        let calendar = Calendar.current
        let endOfToday = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) ?? now
        let staleCutoff = calendar.date(byAdding: .day, value: -60, to: now) ?? now

        let due = contacts
            .filter { ($0.nextReconnect ?? .distantFuture) < endOfToday }
            .sorted { ($0.nextReconnect ?? now) < ($1.nextReconnect ?? now) }

        let neglected = contacts
            .filter { $0.nextReconnect == nil && $0.priority == .high }
            .filter { ($0.lastContacted ?? .distantPast) < staleCutoff }
            .sorted { ($0.lastContacted ?? .distantPast) < ($1.lastContacted ?? .distantPast) }

        return due + neglected
    }

    // MARK: - Save

    private static func save(_ context: ModelContext) {
        do {
            try context.save()
        } catch {
            print("Failed to save contact changes: \(error.localizedDescription)")
        }
    }
}

// MARK: - Sort keys

// Computed, not stored, so they add nothing to the SwiftData/CloudKit schema. Table sorting
// needs non-optional Comparable values; missing dates sort to the end in ascending order.
extension Contact {
    var lastContactedSortKey: Date { lastContacted ?? .distantPast }
    var nextReconnectSortKey: Date { nextReconnect ?? .distantFuture }
    var tagsSortKey: String { tags.sorted().joined(separator: ",") }
}
