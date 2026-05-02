import Foundation

// MARK: - Configuration (values live in Secrets.swift, which is gitignored)
private let kSupabaseURL = Secrets.supabaseURL
private let kSupabaseKey = Secrets.supabaseKey

// MARK: - Codable mirror structs (match the Supabase table columns)

struct SBList: Codable {
    var id: UUID
    var name: String
    var sort_order: Int
    var updated_at: String?
}

struct SBTask: Codable {
    var id: UUID
    var list_id: UUID?
    var title: String
    var is_completed: Bool
    var completed_at: String?
    var sort_order: Int
    var updated_at: String?
}

struct SBContact: Codable {
    var id: UUID
    var name: String
    var company: String
    var job_title: String
    var emails: [String]
    var phones: [String]
    var city: String
    var country: String
    var priority: String
    var tags: [String]
    var notes: String
    var how_we_met: String
    var linkedin_url: String
    var twitter_url: String
    var instagram_url: String
    var last_contacted: String?
    var next_reconnect: String?
    var birthday: String?
    var updated_at: String?
}

struct SBInteraction: Codable {
    var id: UUID
    var contact_id: UUID?
    var type: String
    var notes: String
    var date: String
}

struct SBBrainDump: Codable {
    var id: UUID
    var transcript: String
    var processing_summary: String
    var processed_at: String?
    var updated_at: String?
}

// MARK: - Service

final class SupabaseService {
    static let shared = SupabaseService()
    private init() {}

    private let base = kSupabaseURL
    private let key  = kSupabaseKey

    // ── Low-level helpers ────────────────────────────────────────────────────

    private func req(method: String, path: String, body: Data? = nil, prefer: String? = nil) async {
        guard var comps = URLComponents(string: "\(base)/rest/v1/\(path)") else { return }
        var r = URLRequest(url: comps.url!)
        r.httpMethod = method
        r.setValue("application/json",    forHTTPHeaderField: "Content-Type")
        r.setValue(key,                   forHTTPHeaderField: "apikey")
        r.setValue("Bearer \(key)",       forHTTPHeaderField: "Authorization")
        if let p = prefer { r.setValue(p, forHTTPHeaderField: "Prefer") }
        r.httpBody = body
        _ = try? await URLSession.shared.data(for: r)
    }

    private func get<T: Decodable>(_ table: String, query: String = "") async -> [T] {
        let path = "\(table)?select=*\(query.isEmpty ? "" : "&\(query)")"
        guard let url = URL(string: "\(base)/rest/v1/\(path)") else { return [] }
        var r = URLRequest(url: url)
        r.setValue("application/json", forHTTPHeaderField: "Content-Type")
        r.setValue(key,                forHTTPHeaderField: "apikey")
        r.setValue("Bearer \(key)",    forHTTPHeaderField: "Authorization")
        guard let (data, _) = try? await URLSession.shared.data(for: r) else { return [] }
        return (try? JSONDecoder().decode([T].self, from: data)) ?? []
    }

    private func upsert(_ table: String, body: Data) async {
        await req(method: "POST", path: table,
                  body: body,
                  prefer: "resolution=merge-duplicates,return=minimal")
    }

    // ── Lists ────────────────────────────────────────────────────────────────

    func push(list: TodoList) async {
        let r = SBList(id: list.supabaseId, name: list.name,
                       sort_order: list.sortOrder, updated_at: iso(list.updatedAt))
        guard let data = try? JSONEncoder().encode([r]) else { return }
        await upsert("todo_lists", body: data)
    }

    func deleteList(_ id: UUID) async {
        await req(method: "DELETE", path: "todo_lists?id=eq.\(id)")
    }

    func fetchLists() async -> [SBList] {
        await get("todo_lists")
    }

    // ── Tasks ────────────────────────────────────────────────────────────────

    func push(task: TaskItem) async {
        guard let listId = task.list?.supabaseId else { return }
        let r = SBTask(id: task.supabaseId, list_id: listId,
                       title: task.title, is_completed: task.isCompleted,
                       completed_at: task.completedAt.map(iso),
                       sort_order: task.sortOrder, updated_at: iso(task.updatedAt))
        guard let data = try? JSONEncoder().encode([r]) else { return }
        await upsert("tasks", body: data)
    }

    func deleteTask(_ id: UUID) async {
        await req(method: "DELETE", path: "tasks?id=eq.\(id)")
    }

    func fetchTasks() async -> [SBTask] {
        await get("tasks")
    }

    // ── Contacts ─────────────────────────────────────────────────────────────

    func push(contact: Contact) async {
        let r = SBContact(
            id: contact.id,
            name: contact.name,
            company: contact.company,
            job_title: contact.jobTitle,
            emails: contact.emails,
            phones: contact.phones,
            city: contact.city,
            country: contact.country,
            priority: contact.priorityRaw,
            tags: contact.tags,
            notes: contact.notes,
            how_we_met: contact.howWeMet,
            linkedin_url: contact.linkedInURL,
            twitter_url: contact.twitterURL,
            instagram_url: contact.instagramURL,
            last_contacted: contact.lastContacted.map(iso),
            next_reconnect: contact.nextReconnect.map(iso),
            birthday: contact.birthday.map(iso),
            updated_at: iso(contact.updatedAt)
        )
        guard let data = try? JSONEncoder().encode([r]) else { return }
        await upsert("contacts", body: data)
    }

    func deleteContact(_ id: UUID) async {
        await req(method: "DELETE", path: "contacts?id=eq.\(id)")
    }

    func fetchContacts() async -> [SBContact] {
        await get("contacts")
    }

    // ── Interactions ──────────────────────────────────────────────────────────

    func push(interaction: Interaction) async {
        guard let contactId = interaction.contact?.id else { return }
        let r = SBInteraction(id: interaction.id, contact_id: contactId,
                              type: interaction.typeRaw,
                              notes: interaction.notes,
                              date: iso(interaction.date))
        guard let data = try? JSONEncoder().encode([r]) else { return }
        await upsert("interactions", body: data)
    }

    func fetchInteractions() async -> [SBInteraction] {
        await get("interactions")
    }

    // ── Brain Dumps ───────────────────────────────────────────────────────────

    func push(brainDump dump: BrainDump) async {
        let r = SBBrainDump(
            id: dump.supabaseId,
            transcript: dump.transcript,
            processing_summary: dump.processingSummary,
            processed_at: dump.processedAt.map(iso),
            updated_at: iso(dump.updatedAt)
        )
        guard let data = try? JSONEncoder().encode([r]) else { return }
        await upsert("brain_dumps", body: data)
    }

    func deleteBrainDump(_ id: UUID) async {
        await req(method: "DELETE", path: "brain_dumps?id=eq.\(id)")
    }

    func fetchBrainDumps() async -> [SBBrainDump] {
        await get("brain_dumps")
    }

    // ── Date helper ───────────────────────────────────────────────────────────

    private func iso(_ date: Date) -> String {
        ISO8601DateFormatter().string(from: date)
    }
}
