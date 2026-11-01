import Foundation
import SwiftData

/// Writes a plain-JSON copy of every list, task, contact and interaction the first time
/// each app version launches, into the iCloud Documents folder (Finder: iCloud Drive ›
/// Compass › Backups). The SwiftData store is the source of truth; this is a safety net
/// that can be read without the app if an upgrade ever goes wrong. Contact photos are
/// left out to keep the file small.
enum UpgradeBackup {
    private static let lastBackedUpVersionKey = "backup.lastVersion"

    @MainActor
    static func runIfNeeded(container: ModelContainer) {
        let info = Bundle.main.infoDictionary
        let version = "\(info?["CFBundleShortVersionString"] as? String ?? "?")-\(info?["CFBundleVersion"] as? String ?? "?")"
        guard UserDefaults.standard.string(forKey: lastBackedUpVersionKey) != version else { return }

        let context = container.mainContext
        guard let data = try? snapshot(in: context) else { return }

        Task.detached(priority: .utility) {
            guard let folder = backupFolder() else { return }
            let stamp = Date().formatted(.iso8601.year().month().day())
            let file = folder.appendingPathComponent("compass-backup-\(version)-\(stamp).json")
            do {
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                try data.write(to: file, options: .atomic)
                await MainActor.run {
                    UserDefaults.standard.set(version, forKey: lastBackedUpVersionKey)
                }
            } catch {
                print("Upgrade backup failed: \(error.localizedDescription)")
            }
        }
    }

    /// iCloud Documents/Backups when iCloud is available, otherwise the app's own Documents.
    private nonisolated static func backupFolder() -> URL? {
        if let container = FileManager.default.url(forUbiquityContainerIdentifier: NetWorthStore.containerID) {
            return container.appendingPathComponent("Documents/Backups", isDirectory: true)
        }
        return FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?
            .appendingPathComponent("Backups", isDirectory: true)
    }

    // MARK: - Snapshot

    @MainActor
    static func snapshot(in context: ModelContext) throws -> Data {
        let lists = try context.fetch(FetchDescriptor<TodoList>(sortBy: [SortDescriptor(\.sortOrder)]))
        let contacts = try context.fetch(FetchDescriptor<Contact>(sortBy: [SortDescriptor(\.name)]))

        let payload = Backup(
            createdAt: Date(),
            lists: lists.map { list in
                Backup.List(
                    name: list.name,
                    createdAt: list.createdAt,
                    tasks: (list.tasks ?? []).sorted { $0.sortOrder < $1.sortOrder }.map {
                        Backup.Task(title: $0.title, createdAt: $0.createdAt, completedAt: $0.completedAt)
                    }
                )
            },
            contacts: contacts.map { c in
                Backup.Contact(
                    id: c.id, name: c.name, company: c.company, jobTitle: c.jobTitle,
                    city: c.city, country: c.country, emails: c.emails, phones: c.phones,
                    linkedInURL: c.linkedInURL, tags: c.tags, priority: c.priorityRaw,
                    howWeMet: c.howWeMet, notes: c.notes,
                    lastContacted: c.lastContacted, nextReconnect: c.nextReconnect, birthday: c.birthday,
                    interactions: c.interactionsList.sorted { $0.date < $1.date }.map {
                        Backup.Interaction(date: $0.date, type: $0.typeRaw, notes: $0.notes)
                    }
                )
            }
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(payload)
    }

    struct Backup: Codable {
        struct List: Codable {
            var name: String
            var createdAt: Date
            var tasks: [Task]
        }
        struct Task: Codable {
            var title: String
            var createdAt: Date
            var completedAt: Date?
        }
        struct Contact: Codable {
            var id: UUID
            var name, company, jobTitle, city, country: String
            var emails, phones: [String]
            var linkedInURL: String
            var tags: [String]
            var priority, howWeMet, notes: String
            var lastContacted, nextReconnect, birthday: Date?
            var interactions: [Interaction]
        }
        struct Interaction: Codable {
            var date: Date
            var type: String
            var notes: String
        }

        var createdAt: Date
        var lists: [List]
        var contacts: [Contact]
    }
}
