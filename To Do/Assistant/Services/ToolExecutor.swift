import Foundation
import SwiftData

// MARK: - Tool Executor
// Executes Claude tool calls directly against the SwiftData model context.

@MainActor
final class ToolExecutor {

    private let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    func execute(name: String, input: [String: Any]) -> String {
        switch name {
        // --- Lists & Tasks ---
        case "list_lists":       return listLists()
        case "add_list":         return addList(input)
        case "add_task":         return addTask(input)
        case "list_tasks":       return listTasks(input)
        case "complete_task":    return completeTask(input)
        case "delete_task":      return deleteTask(input)
        // --- Contacts ---
        case "add_contact":      return addContact(input)
        case "list_contacts":    return listContacts(input)
        case "update_contact":   return updateContact(input)
        case "log_interaction":  return logInteraction(input)
        default:                 return "Unknown tool: \(name)"
        }
    }

    // MARK: - List / Task tools

    private func listLists() -> String {
        let lists = fetchLists()
        guard !lists.isEmpty else { return "No lists yet." }
        return lists.map { l in
            let count = (l.tasks ?? []).filter { !$0.isCompleted }.count
            return "• \(l.name) — \(count) active task\(count == 1 ? "" : "s")"
        }.joined(separator: "\n")
    }

    private func addList(_ input: [String: Any]) -> String {
        let name = (input["name"] as? String ?? "").trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return "Error: list name is required." }
        let lists = fetchLists()
        let minOrder = lists.map(\.sortOrder).min() ?? 1
        let list = TodoList(name: name, sortOrder: minOrder - 1)
        context.insert(list)
        save()
        return "Created list '\(name)'."
    }

    private func addTask(_ input: [String: Any]) -> String {
        let listName  = input["list_name"] as? String ?? ""
        let title     = (input["title"] as? String ?? "").trimmingCharacters(in: .whitespaces)
        guard !title.isEmpty else { return "Error: task title is required." }
        guard let list = findList(listName) else {
            return "List '\(listName)' not found. Available: \(fetchLists().map(\.name).joined(separator: ", "))"
        }
        let tasks    = list.tasks ?? []
        let minOrder = tasks.map(\.sortOrder).min() ?? 1
        let task     = TaskItem(title: title, list: list, sortOrder: minOrder - 1)
        context.insert(task)
        save()
        return "Added '\(title)' to '\(list.name)'."
    }

    private func listTasks(_ input: [String: Any]) -> String {
        let listName = input["list_name"] as? String

        if let listName, !listName.isEmpty {
            guard let list = findList(listName) else {
                return "List '\(listName)' not found."
            }
            let active = activeTasks(in: list)
            return active.isEmpty
                ? "No active tasks in '\(list.name)'."
                : active.map { "• \($0.title)" }.joined(separator: "\n")
        } else {
            let lists = fetchLists()
            var result = ""
            for list in lists {
                let active = activeTasks(in: list)
                guard !active.isEmpty else { continue }
                result += "\n\(list.name):\n"
                result += active.map { "  • \($0.title)" }.joined(separator: "\n")
            }
            return result.isEmpty ? "No active tasks." : result.trimmingCharacters(in: .newlines)
        }
    }

    private func completeTask(_ input: [String: Any]) -> String {
        let taskTitle = input["task_title"] as? String ?? ""
        let listName  = input["list_name"]  as? String

        guard let task = findTask(title: taskTitle, listName: listName, onlyActive: true) else {
            return "Active task matching '\(taskTitle)' not found."
        }
        task.completedAt = .now
        save()
        return "Marked '\(task.title)' as complete ✓"
    }

    private func deleteTask(_ input: [String: Any]) -> String {
        let taskTitle = input["task_title"] as? String ?? ""
        let listName  = input["list_name"]  as? String

        guard let task = findTask(title: taskTitle, listName: listName, onlyActive: false) else {
            return "Task matching '\(taskTitle)' not found."
        }
        let title = task.title
        context.delete(task)
        save()
        return "Deleted '\(title)'."
    }

    // MARK: - Contact tools

    private func addContact(_ input: [String: Any]) -> String {
        let name = (input["name"] as? String ?? "").trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return "Error: contact name is required." }

        let priorityStr = input["priority"] as? String ?? "Medium"
        let priority    = Priority(rawValue: priorityStr) ?? .medium

        var emails: [String] = []
        if let email = input["email"] as? String, !email.isEmpty { emails = [email] }

        var phones: [String] = []
        if let phone = input["phone"] as? String, !phone.isEmpty { phones = [phone] }

        let tags = (input["tags"] as? String ?? "")
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        let contact = Contact(
            name:         name,
            city:         input["city"]      as? String ?? "",
            country:      input["country"]   as? String ?? "",
            emails:       emails,
            phones:       phones,
            company:      input["company"]   as? String ?? "",
            jobTitle:     input["job_title"] as? String ?? "",
            tags:         tags,
            priority:     priority,
            howWeMet:     input["how_we_met"] as? String ?? "",
            notes:        input["notes"]     as? String ?? "",
            nextReconnect: parseDate(input["next_reconnect"] as? String)
        )
        context.insert(contact)
        save()
        return "Added contact '\(name)'."
    }

    private func listContacts(_ input: [String: Any]) -> String {
        var descriptor = FetchDescriptor<Contact>(sortBy: [SortDescriptor(\.name)])
        guard let contacts = try? context.fetch(descriptor), !contacts.isEmpty else {
            return "No contacts yet."
        }

        var filtered = contacts

        if let priorityStr = input["priority"] as? String,
           let p = Priority(rawValue: priorityStr) {
            filtered = filtered.filter { $0.priority == p }
        }
        if let search = input["search"] as? String, !search.isEmpty {
            filtered = filtered.filter {
                $0.name.localizedCaseInsensitiveContains(search) ||
                $0.company.localizedCaseInsensitiveContains(search)
            }
        }

        guard !filtered.isEmpty else { return "No contacts match that filter." }

        return filtered.map { c in
            var line = c.name
            if !c.company.isEmpty   { line += " (\(c.company))" }
            if !c.jobTitle.isEmpty  { line += " — \(c.jobTitle)" }
            line += " [\(c.priority.rawValue)]"
            if let r = c.nextReconnect { line += ", reconnect: \(shortDate(r))" }
            return "• " + line
        }.joined(separator: "\n")
    }

    private func updateContact(_ input: [String: Any]) -> String {
        let name = input["name"] as? String ?? ""
        guard let contact = findContact(name) else {
            return "Contact '\(name)' not found."
        }

        if let v = input["new_name"]   as? String, !v.isEmpty { contact.name     = v }
        if let v = input["company"]    as? String              { contact.company  = v }
        if let v = input["job_title"]  as? String              { contact.jobTitle = v }
        if let v = input["city"]       as? String              { contact.city     = v }
        if let v = input["country"]    as? String              { contact.country  = v }
        if let v = input["notes"]      as? String              { contact.notes    = v }

        if let email = input["email"] as? String, !email.isEmpty {
            contact.emails = [email]
        }
        if let phone = input["phone"] as? String, !phone.isEmpty {
            contact.phones = [phone]
        }
        if let pStr = input["priority"] as? String,
           let p = Priority(rawValue: pStr) {
            contact.priority = p
        }
        if let dateStr = input["next_reconnect"] as? String {
            contact.nextReconnect = parseDate(dateStr)
        }

        contact.updatedAt = .now
        save()
        return "Updated '\(contact.name)'."
    }

    private func logInteraction(_ input: [String: Any]) -> String {
        let contactName = input["contact_name"] as? String ?? ""
        guard let contact = findContact(contactName) else {
            return "Contact '\(contactName)' not found."
        }

        let typeStr = input["type"] as? String ?? "Note"
        let type    = InteractionType(rawValue: typeStr) ?? .note
        let notes   = input["notes"] as? String ?? ""
        let date    = parseDate(input["date"] as? String) ?? Date()

        let interaction = Interaction(date: date, type: type, notes: notes)
        interaction.contact = contact
        context.insert(interaction)

        contact.lastContacted = date
        contact.updatedAt     = .now
        save()
        return "Logged \(type.rawValue.lowercased()) with \(contact.name)."
    }

    // MARK: - Private helpers

    private func fetchLists() -> [TodoList] {
        let d = FetchDescriptor<TodoList>(sortBy: [SortDescriptor(\.sortOrder)])
        return (try? context.fetch(d)) ?? []
    }

    private func findList(_ name: String) -> TodoList? {
        fetchLists().first {
            $0.name.localizedCaseInsensitiveContains(name) ||
            name.localizedCaseInsensitiveContains($0.name)
        }
    }

    private func activeTasks(in list: TodoList) -> [TaskItem] {
        (list.tasks ?? [])
            .filter { !$0.isCompleted }
            .sorted { $0.sortOrder < $1.sortOrder }
    }

    private func findTask(title: String, listName: String?, onlyActive: Bool) -> TaskItem? {
        let d = FetchDescriptor<TaskItem>()
        let all = (try? context.fetch(d)) ?? []
        return all.first { task in
            task.title.localizedCaseInsensitiveContains(title) &&
            (!onlyActive || !task.isCompleted) &&
            (listName == nil || (task.list?.name.localizedCaseInsensitiveContains(listName!) ?? false))
        }
    }

    private func findContact(_ name: String) -> Contact? {
        let d = FetchDescriptor<Contact>()
        return ((try? context.fetch(d)) ?? []).first {
            $0.name.localizedCaseInsensitiveContains(name)
        }
    }

    private func parseDate(_ string: String?) -> Date? {
        guard let string, !string.isEmpty else { return nil }
        let formatters = [
            "MMMM d, yyyy", "MMM d, yyyy", "MM/dd/yyyy", "yyyy-MM-dd", "d MMM yyyy"
        ].map { fmt -> DateFormatter in
            let f = DateFormatter(); f.dateFormat = fmt; return f
        }
        for f in formatters {
            if let d = f.date(from: string) { return d }
        }
        return nil
    }

    private func shortDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateStyle = .medium
        return f.string(from: date)
    }

    private func save() {
        try? context.save()
    }
}
