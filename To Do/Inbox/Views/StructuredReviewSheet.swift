import SwiftUI
import SwiftData

struct StructuredReviewSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    let transcript: String
    let parsed: ParsedDump
    var onDone: () -> Void

    @Query(sort: \TodoList.sortOrder) private var lists: [TodoList]
    @Query(sort: \Contact.name)        private var contacts: [Contact]

    // Per-item state
    @State private var taskRows: [TaskRow] = []
    @State private var contactNoteRows: [ContactNoteRow] = []
    @State private var noteRows: [NoteRow] = []

    // For "create new list" / "create new contact" inline
    @State private var listOptionByID: [UUID: String] = [:]   // task row id → list name (incl. "+ New list")
    @State private var contactOptionByID: [UUID: String] = [:]

    var body: some View {
        NavigationStack {
            Form {
                if !taskRows.isEmpty {
                    tasksSection
                }
                if !contactNoteRows.isEmpty {
                    contactsSection
                }
                if !noteRows.isEmpty {
                    notesSection
                }
                if taskRows.isEmpty && contactNoteRows.isEmpty && noteRows.isEmpty {
                    Section {
                        Text("Nothing actionable was detected. The full transcript will still be saved to your Inbox.")
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Original transcript") {
                    Text(transcript)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Review")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        // Even if cancelled, save the brain dump as unprocessed
                        saveDumpOnly()
                        dismiss()
                        onDone()
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save All") {
                        saveAll()
                        dismiss()
                        onDone()
                    }
                    .fontWeight(.semibold)
                }
            }
            .onAppear { loadRows() }
        }
    }

    // MARK: - Sections

    private var tasksSection: some View {
        Section("Tasks") {
            ForEach($taskRows) { $row in
                taskRowView(row: $row)
            }
        }
    }

    @ViewBuilder
    private func taskRowView(row: Binding<TaskRow>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Toggle("", isOn: row.include)
                    .labelsHidden()

                TextField("Task title", text: row.title)
                    .textFieldStyle(.plain)
                    .disabled(!row.include.wrappedValue)
            }

            HStack {
                Text("List:")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Picker("", selection: row.listName) {
                    ForEach(listOptions, id: \.self) { name in
                        Text(name).tag(name)
                    }
                    Text("+ New list").tag("__NEW__")
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .disabled(!row.include.wrappedValue)

                if row.listName.wrappedValue == "__NEW__" {
                    TextField("New list name", text: row.newListName)
                        .textFieldStyle(.roundedBorder)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private var contactsSection: some View {
        Section("Contact notes") {
            ForEach($contactNoteRows) { $row in
                contactRowView(row: $row)
            }
        }
    }

    @ViewBuilder
    private func contactRowView(row: Binding<ContactNoteRow>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Toggle("", isOn: row.include)
                    .labelsHidden()

                Picker("", selection: row.contactName) {
                    ForEach(contactOptions, id: \.self) { name in
                        Text(name).tag(name)
                    }
                    Text("+ New contact").tag("__NEW__")
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .disabled(!row.include.wrappedValue)

                if row.contactName.wrappedValue == "__NEW__" {
                    TextField("New name", text: row.newContactName)
                        .textFieldStyle(.roundedBorder)
                }
            }

            TextField("Note", text: row.note, axis: .vertical)
                .lineLimit(1...4)
                .textFieldStyle(.plain)
                .disabled(!row.include.wrappedValue)
        }
        .padding(.vertical, 4)
    }

    private var notesSection: some View {
        Section("Other notes") {
            ForEach($noteRows) { $row in
                noteRowView(row: $row)
            }
        }
    }

    @ViewBuilder
    private func noteRowView(row: Binding<NoteRow>) -> some View {
        HStack(alignment: .top) {
            Toggle("", isOn: row.include)
                .labelsHidden()
            TextField("Note", text: row.content, axis: .vertical)
                .lineLimit(1...4)
                .disabled(!row.include.wrappedValue)
        }
    }

    // MARK: - Setup & options

    private var listOptions: [String] {
        lists.map(\.name)
    }

    private var contactOptions: [String] {
        contacts.map(\.name)
    }

    private func loadRows() {
        // Tasks
        taskRows = parsed.tasks.map { p in
            let chosen: String
            if let suggested = p.list_name,
               let match = lists.first(where: { $0.name.localizedCaseInsensitiveCompare(suggested) == .orderedSame }) {
                chosen = match.name
            } else {
                chosen = lists.first?.name ?? "__NEW__"
            }
            return TaskRow(title: p.title, listName: chosen, newListName: p.list_name ?? "")
        }

        // Contact notes
        contactNoteRows = parsed.contact_notes.map { p in
            let exact = contacts.first { $0.name.localizedCaseInsensitiveCompare(p.contact_name) == .orderedSame }
            let chosen: String
            if let exact { chosen = exact.name }
            else { chosen = "__NEW__" }
            return ContactNoteRow(contactName: chosen, newContactName: p.contact_name, note: p.note)
        }

        // Notes
        noteRows = parsed.notes.map { p in
            NoteRow(content: p.content)
        }
    }

    // MARK: - Save

    private func saveAll() {
        // 1) Materialize tasks
        for row in taskRows where row.include {
            let trimmedTitle = row.title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedTitle.isEmpty else { continue }

            // Find or create list
            let listName = (row.listName == "__NEW__"
                            ? row.newListName.trimmingCharacters(in: .whitespacesAndNewlines)
                            : row.listName)
            guard !listName.isEmpty else { continue }

            let list: TodoList
            if let existing = lists.first(where: { $0.name.localizedCaseInsensitiveCompare(listName) == .orderedSame }) {
                list = existing
            } else {
                let newOrder = (lists.map(\.sortOrder).min() ?? 1) - 1
                let newList  = TodoList(name: listName, sortOrder: newOrder)
                modelContext.insert(newList)
                list = newList
                Task { await SupabaseService.shared.push(list: list) }
            }

            let nextOrder = ((list.tasks ?? []).map(\.sortOrder).min() ?? 1) - 1
            let task = TaskItem(title: trimmedTitle, list: list, sortOrder: nextOrder)
            modelContext.insert(task)
            Task { await SupabaseService.shared.push(task: task) }
        }

        // 2) Materialize contact notes (as Interactions)
        for row in contactNoteRows where row.include {
            let trimmedNote = row.note.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedNote.isEmpty else { continue }

            let contactName = (row.contactName == "__NEW__"
                               ? row.newContactName.trimmingCharacters(in: .whitespacesAndNewlines)
                               : row.contactName)
            guard !contactName.isEmpty else { continue }

            let contact: Contact
            if let existing = contacts.first(where: { $0.name.localizedCaseInsensitiveCompare(contactName) == .orderedSame }) {
                contact = existing
            } else {
                contact = Contact(name: contactName)
                modelContext.insert(contact)
                Task { await SupabaseService.shared.push(contact: contact) }
            }

            let interaction = Interaction(date: .now, type: .note, notes: trimmedNote)
            interaction.contact = contact
            modelContext.insert(interaction)
            contact.lastContacted = .now
            contact.updatedAt = .now
            Task { await SupabaseService.shared.push(interaction: interaction) }
            Task { await SupabaseService.shared.push(contact: contact) }
        }

        // 3) Save the brain dump itself with summary
        let savedTaskCount = taskRows.filter { $0.include }.count
        let savedContactCount = contactNoteRows.filter { $0.include }.count
        let savedNoteCount = noteRows.filter { $0.include }.count
        let summary = formatSummary(tasks: savedTaskCount, contacts: savedContactCount, notes: savedNoteCount)

        let dump = BrainDump(
            transcript: combinedTranscript(),
            processingSummary: summary,
            processedAt: .now
        )
        modelContext.insert(dump)
        Task { await SupabaseService.shared.push(brainDump: dump) }

        try? modelContext.save()
    }

    private func saveDumpOnly() {
        let dump = BrainDump(
            transcript: transcript,
            processingSummary: "Saved without processing",
            processedAt: nil
        )
        modelContext.insert(dump)
        try? modelContext.save()
        Task { await SupabaseService.shared.push(brainDump: dump) }
    }

    // Combine transcript with floating notes (so they aren't lost if the user doesn't include them as notes)
    private func combinedTranscript() -> String {
        var parts = [transcript]
        for row in noteRows where row.include {
            let trimmed = row.content.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                parts.append("• \(trimmed)")
            }
        }
        return parts.joined(separator: "\n")
    }

    private func formatSummary(tasks: Int, contacts: Int, notes: Int) -> String {
        var bits: [String] = []
        if tasks > 0    { bits.append("\(tasks) task\(tasks == 1 ? "" : "s")") }
        if contacts > 0 { bits.append("\(contacts) contact note\(contacts == 1 ? "" : "s")") }
        if notes > 0    { bits.append("\(notes) note\(notes == 1 ? "" : "s")") }
        return bits.isEmpty ? "Saved" : "→ " + bits.joined(separator: ", ")
    }
}

// MARK: - Row models

struct TaskRow: Identifiable {
    let id = UUID()
    var include: Bool = true
    var title: String
    var listName: String         // existing list name or "__NEW__"
    var newListName: String      // used if listName == "__NEW__"
}

struct ContactNoteRow: Identifiable {
    let id = UUID()
    var include: Bool = true
    var contactName: String      // existing contact name or "__NEW__"
    var newContactName: String   // used if contactName == "__NEW__"
    var note: String
}

struct NoteRow: Identifiable {
    let id = UUID()
    var include: Bool = true
    var content: String
}
