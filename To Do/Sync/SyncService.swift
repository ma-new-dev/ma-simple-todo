import Foundation
import SwiftData
import Combine

// MARK: - SyncService
// Pulls data from Supabase → SwiftData and pushes SwiftData → Supabase.
// Call sync() on app launch and every time the app returns to foreground.

@MainActor
final class SyncService: ObservableObject {
    static let shared = SyncService()
    private init() {}

    @Published var isSyncing = false
    @Published var lastSynced: Date?

    private let sb = SupabaseService.shared
    private let isoParser: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    // ── Public entry point ────────────────────────────────────────────────────

    func sync(context: ModelContext) async {
        guard !isSyncing else { return }
        isSyncing = true
        defer { isSyncing = false }

        // 1. Push all local data up (captures anything created offline)
        await pushAll(context: context)

        // 2. Pull from Supabase (captures anything added by shortcuts/Claude)
        await pullAll(context: context)

        lastSynced = .now
    }

    // ── Push (SwiftData → Supabase) ───────────────────────────────────────────

    func pushAll(context: ModelContext) async {
        let lists   = (try? context.fetch(FetchDescriptor<TodoList>())) ?? []
        let tasks   = (try? context.fetch(FetchDescriptor<TaskItem>())) ?? []
        let contacts    = (try? context.fetch(FetchDescriptor<Contact>())) ?? []
        let interactions = (try? context.fetch(FetchDescriptor<Interaction>())) ?? []
        let dumps   = (try? context.fetch(FetchDescriptor<BrainDump>())) ?? []

        await withTaskGroup(of: Void.self) { group in
            for l in lists   { group.addTask { await self.sb.push(list: l) } }
            for t in tasks   { group.addTask { await self.sb.push(task: t) } }
            for c in contacts { group.addTask { await self.sb.push(contact: c) } }
            for i in interactions { group.addTask { await self.sb.push(interaction: i) } }
            for d in dumps    { group.addTask { await self.sb.push(brainDump: d) } }
        }
    }

    // ── Pull (Supabase → SwiftData) ───────────────────────────────────────────

    func pullAll(context: ModelContext) async {
        async let sbLists  = sb.fetchLists()
        async let sbTasks  = sb.fetchTasks()
        async let sbConts  = sb.fetchContacts()
        async let sbInters = sb.fetchInteractions()
        async let sbDumps  = sb.fetchBrainDumps()

        let (lists, tasks, contacts, interactions, dumps) = await (sbLists, sbTasks, sbConts, sbInters, sbDumps)

        // Build lookup maps for existing SwiftData records
        let localLists   = (try? context.fetch(FetchDescriptor<TodoList>())) ?? []
        let localTasks   = (try? context.fetch(FetchDescriptor<TaskItem>())) ?? []
        let localContacts = (try? context.fetch(FetchDescriptor<Contact>())) ?? []
        let localInters  = (try? context.fetch(FetchDescriptor<Interaction>())) ?? []
        let localDumps   = (try? context.fetch(FetchDescriptor<BrainDump>())) ?? []

        // Safely build lookup maps (tolerates duplicates — overwrites with last one)
        var listBySupaId: [UUID: TodoList] = [:]
        for l in localLists { listBySupaId[l.supabaseId] = l }

        var taskBySupaId: [UUID: TaskItem] = [:]
        for t in localTasks { taskBySupaId[t.supabaseId] = t }

        var contactById: [UUID: Contact] = [:]
        for c in localContacts { contactById[c.id] = c }

        var interById: [UUID: Interaction] = [:]
        for i in localInters { interById[i.id] = i }

        var dumpBySupaId: [UUID: BrainDump] = [:]
        for d in localDumps { dumpBySupaId[d.supabaseId] = d }

        // Merge lists
        for sb in lists {
            if let local = listBySupaId[sb.id] {
                // Update if Supabase version is newer
                if remoteIsNewer(sb.updated_at, than: local.updatedAt) {
                    local.name      = sb.name
                    local.sortOrder = sb.sort_order
                    local.updatedAt = date(sb.updated_at) ?? local.updatedAt
                }
            } else {
                // New list from Supabase (created by shortcuts)
                let minOrder = localLists.map(\.sortOrder).min() ?? 0
                let newList  = TodoList(name: sb.name, sortOrder: minOrder - 1)
                newList.supabaseId = sb.id
                newList.updatedAt  = date(sb.updated_at) ?? .now
                context.insert(newList)
                listBySupaId[sb.id] = newList
            }
        }

        // Merge tasks
        for sb in tasks {
            if let local = taskBySupaId[sb.id] {
                if remoteIsNewer(sb.updated_at, than: local.updatedAt) {
                    local.title       = sb.title
                    local.completedAt = sb.completed_at.flatMap { date($0) }
                    local.sortOrder   = sb.sort_order
                    local.updatedAt   = date(sb.updated_at) ?? local.updatedAt
                }
            } else {
                // New task from Supabase — find parent list
                guard let listSbId = sb.list_id,
                      let parentList = listBySupaId[listSbId] else { continue }

                let minOrder = (parentList.tasks ?? []).map(\.sortOrder).min() ?? 0
                let newTask  = TaskItem(title: sb.title, list: parentList,
                                        completedAt: sb.completed_at.flatMap { date($0) },
                                        sortOrder: minOrder - 1)
                newTask.supabaseId = sb.id
                newTask.updatedAt  = date(sb.updated_at) ?? .now
                context.insert(newTask)
                taskBySupaId[sb.id] = newTask
            }
        }

        // Merge contacts
        for sb in contacts {
            if let local = contactById[sb.id] {
                if remoteIsNewer(sb.updated_at, than: local.updatedAt) {
                    local.name         = sb.name
                    local.company      = sb.company
                    local.jobTitle     = sb.job_title
                    local.emails       = sb.emails
                    local.phones       = sb.phones
                    local.city         = sb.city
                    local.country      = sb.country
                    local.priorityRaw  = sb.priority
                    local.tags         = sb.tags
                    local.notes        = sb.notes
                    local.howWeMet     = sb.how_we_met
                    local.linkedInURL  = sb.linkedin_url
                    local.twitterURL   = sb.twitter_url
                    local.instagramURL = sb.instagram_url
                    local.lastContacted  = sb.last_contacted.flatMap { date($0) }
                    local.nextReconnect  = sb.next_reconnect.flatMap { date($0) }
                    local.birthday       = sb.birthday.flatMap { date($0) }
                    local.updatedAt      = date(sb.updated_at) ?? local.updatedAt
                }
            } else {
                // New contact from Supabase
                let c = Contact(
                    id: sb.id,
                    name: sb.name,
                    city: sb.city,
                    country: sb.country,
                    emails: sb.emails,
                    phones: sb.phones,
                    company: sb.company,
                    jobTitle: sb.job_title,
                    tags: sb.tags,
                    priority: Priority(rawValue: sb.priority) ?? .medium,
                    howWeMet: sb.how_we_met,
                    notes: sb.notes,
                    lastContacted: sb.last_contacted.flatMap { date($0) },
                    nextReconnect: sb.next_reconnect.flatMap { date($0) },
                    birthday: sb.birthday.flatMap { date($0) }
                )
                context.insert(c)
                contactById[sb.id] = c
            }
        }

        // Merge interactions
        for sb in interactions {
            guard interById[sb.id] == nil else { continue }   // already exists
            guard let contactSbId = sb.contact_id,
                  let contact = contactById[contactSbId] else { continue }

            let i = Interaction(
                id: sb.id,
                date: date(sb.date) ?? .now,
                type: InteractionType(rawValue: sb.type) ?? .note,
                notes: sb.notes
            )
            i.contact = contact
            context.insert(i)
        }

        // Merge brain dumps
        for sb in dumps {
            if let local = dumpBySupaId[sb.id] {
                if remoteIsNewer(sb.updated_at, than: local.updatedAt) {
                    local.transcript        = sb.transcript
                    local.processingSummary = sb.processing_summary
                    local.processedAt       = sb.processed_at.flatMap { date($0) }
                    local.updatedAt         = date(sb.updated_at) ?? local.updatedAt
                }
            } else {
                let d = BrainDump(
                    transcript: sb.transcript,
                    processingSummary: sb.processing_summary,
                    processedAt: sb.processed_at.flatMap { date($0) }
                )
                d.supabaseId = sb.id
                d.updatedAt  = date(sb.updated_at) ?? .now
                context.insert(d)
                dumpBySupaId[sb.id] = d
            }
        }

        try? context.save()
    }

    // ── Helpers ───────────────────────────────────────────────────────────────

    private func date(_ iso: String?) -> Date? {
        guard let iso else { return nil }
        return isoParser.date(from: iso)
            ?? ISO8601DateFormatter().date(from: iso)
    }

    private func remoteIsNewer(_ remoteISO: String?, than local: Date) -> Bool {
        guard let d = date(remoteISO) else { return false }
        return d > local
    }
}
