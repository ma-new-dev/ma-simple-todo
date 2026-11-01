import SwiftUI
import SwiftData

/// Spreadsheet-style contacts view for regular width (iPad, and the app on the Mac).
///
/// Built for updating many people quickly: priority, last-contacted, reconnect and tags are
/// edited in the cell without opening anything, rows multi-select (⇧/⌘-click) for bulk
/// actions, and double-click opens the full detail page.
struct ContactTableView: View {
    @Environment(\.modelContext) private var modelContext
    let contacts: [Contact]
    let allTags: [String]
    @Binding var openedContact: Contact?

    @State private var selection = Set<Contact.ID>()
    @State private var sortOrder = [KeyPathComparator(\Contact.name)]

    // Prompts
    @State private var tagTargets: [Contact] = []
    @State private var newTagName = ""
    @State private var noteTarget: Contact?
    @State private var pendingDeletion: [Contact] = []

    private var sorted: [Contact] { contacts.sorted(using: sortOrder) }

    private var selectedContacts: [Contact] {
        contacts.filter { selection.contains($0.id) }
    }

    var body: some View {
        Table(sorted, selection: $selection, sortOrder: $sortOrder) {
            TableColumn("Name", value: \.name) { contact in
                HStack(spacing: 10) {
                    ContactAvatarView(contact: contact, size: 28)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(contact.name).fontWeight(.medium)
                        if !contact.jobTitle.isEmpty {
                            Text(contact.jobTitle)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .width(min: 180, ideal: 220)

            TableColumn("Company", value: \.company) { contact in
                Text(contact.company).foregroundStyle(.secondary)
            }
            .width(min: 90, ideal: 140)

            TableColumn("City", value: \.city) { contact in
                Text(contact.city).foregroundStyle(.secondary)
            }
            .width(min: 70, ideal: 100)

            TableColumn("Priority", value: \.priority) { contact in
                priorityCell(contact)
            }
            .width(min: 90, ideal: 100)

            TableColumn("Last contacted", value: \.lastContactedSortKey) { contact in
                lastContactedCell(contact)
            }
            .width(min: 110, ideal: 130)

            TableColumn("Reconnect", value: \.nextReconnectSortKey) { contact in
                reconnectCell(contact)
            }
            .width(min: 110, ideal: 130)

            TableColumn("Tags", value: \.tagsSortKey) { contact in
                tagsCell(contact)
            }
            .width(min: 120, ideal: 200)
        }
        .contextMenu(forSelectionType: Contact.ID.self) { ids in
            let targets = contacts.filter { ids.contains($0.id) }
            if !targets.isEmpty {
                bulkMenuItems(for: targets)
            }
        } primaryAction: { ids in
            // Double-click (or Return) opens the full page for a single row.
            if ids.count == 1, let id = ids.first {
                openedContact = contacts.first { $0.id == id }
            }
        }
        .toolbar {
            if !selection.isEmpty {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        bulkMenuItems(for: selectedContacts)
                    } label: {
                        Label("\(selection.count) selected", systemImage: "checklist.checked")
                            .labelStyle(.titleAndIcon)
                    }
                    .accessibilityIdentifier("bulkActionsMenu")
                }
            }
        }
        .alert("Add Tag", isPresented: Binding(
            get: { !tagTargets.isEmpty },
            set: { if !$0 { tagTargets = [] } }
        )) {
            TextField("Tag", text: $newTagName)
            Button("Add") {
                ContactActions.addTag(newTagName, to: tagTargets, in: modelContext)
                newTagName = ""
                tagTargets = []
            }
            Button("Cancel", role: .cancel) {
                newTagName = ""
                tagTargets = []
            }
        } message: {
            Text(tagTargets.count == 1 ? "For \(tagTargets[0].name)" : "For \(tagTargets.count) contacts")
        }
        .sheet(item: $noteTarget) { contact in
            QuickNoteSheet(contact: contact)
        }
        .confirmationDialog(
            pendingDeletion.count == 1 ? "Delete \(pendingDeletion.first?.name ?? "")?" : "Delete \(pendingDeletion.count) contacts?",
            isPresented: Binding(
                get: { !pendingDeletion.isEmpty },
                set: { if !$0 { pendingDeletion = [] } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                let targets = pendingDeletion
                selection.subtract(targets.map(\.id))
                pendingDeletion = []
                ContactActions.delete(targets, in: modelContext)
            }
            Button("Cancel", role: .cancel) { pendingDeletion = [] }
        }
    }

    // MARK: - Cells

    private func priorityCell(_ contact: Contact) -> some View {
        Menu {
            Picker("Priority", selection: Binding(
                get: { contact.priority },
                set: { ContactActions.setPriority([contact], $0, in: modelContext) }
            )) {
                ForEach(Priority.allCases, id: \.self) { p in
                    Label(p.rawValue, systemImage: p.systemImage).tag(p)
                }
            }
        } label: {
            PriorityBadge(priority: contact.priority)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
    }

    private func lastContactedCell(_ contact: Contact) -> some View {
        Menu {
            Section("Contacted via") {
                ForEach([InteractionType.message, .call, .meeting, .email], id: \.self) { type in
                    Button {
                        ContactActions.markContacted([contact], type: type, in: modelContext)
                    } label: {
                        Label("\(type.rawValue) today", systemImage: type.systemImage)
                    }
                }
            }
            Button("Add note…", systemImage: "note.text") { noteTarget = contact }
            if contact.lastContacted != nil {
                Divider()
                Button("Clear date", role: .destructive) {
                    ContactActions.setLastContacted([contact], to: nil, in: modelContext)
                }
            }
        } label: {
            if let date = contact.lastContacted {
                Text(Self.relative(date))
                    .foregroundStyle((contact.daysSinceLastContact ?? 0) > 90 ? .orange : .primary)
            } else {
                Text("Never").foregroundStyle(.tertiary)
            }
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
    }

    private func reconnectCell(_ contact: Contact) -> some View {
        Menu {
            Section("Reconnect in") {
                ForEach(ContactActions.Snooze.allCases) { snooze in
                    Button(snooze.title) {
                        ContactActions.snooze([contact], snooze, in: modelContext)
                    }
                }
            }
            if contact.nextReconnect != nil {
                Divider()
                Button("Clear", role: .destructive) {
                    ContactActions.setReconnect([contact], to: nil, in: modelContext)
                }
            }
        } label: {
            if let date = contact.nextReconnect {
                Text(date.formatted(.dateTime.day().month(.abbreviated)))
                    .foregroundStyle(contact.isReconnectOverdue ? .red : .orange)
                    .fontWeight(contact.isReconnectOverdue ? .semibold : .regular)
            } else {
                Text("—").foregroundStyle(.tertiary)
            }
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
    }

    private func tagsCell(_ contact: Contact) -> some View {
        Menu {
            ForEach(allTags, id: \.self) { tag in
                Toggle(tag, isOn: Binding(
                    get: { contact.tags.contains(tag) },
                    set: { on in
                        if on {
                            ContactActions.addTag(tag, to: [contact], in: modelContext)
                        } else {
                            ContactActions.removeTag(tag, from: [contact], in: modelContext)
                        }
                    }
                ))
            }
            Divider()
            Button("New tag…", systemImage: "plus") { tagTargets = [contact] }
        } label: {
            if contact.tags.isEmpty {
                Text("Add tag").foregroundStyle(.tertiary)
            } else {
                Text(contact.tags.joined(separator: ", "))
                    .foregroundStyle(Color("AccentColor"))
                    .lineLimit(1)
            }
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
    }

    // MARK: - Bulk menu

    @ViewBuilder
    private func bulkMenuItems(for targets: [Contact]) -> some View {
        Menu("Mark contacted today", systemImage: "checkmark.message") {
            ForEach([InteractionType.message, .call, .meeting, .email], id: \.self) { type in
                Button(type.rawValue, systemImage: type.systemImage) {
                    ContactActions.markContacted(targets, type: type, in: modelContext)
                }
            }
        }
        Menu("Reconnect in", systemImage: "calendar.badge.clock") {
            ForEach(ContactActions.Snooze.allCases) { snooze in
                Button(snooze.title) {
                    ContactActions.snooze(targets, snooze, in: modelContext)
                }
            }
            Divider()
            Button("Clear reconnect", role: .destructive) {
                ContactActions.setReconnect(targets, to: nil, in: modelContext)
            }
        }
        Menu("Priority", systemImage: "flag") {
            ForEach(Priority.allCases, id: \.self) { p in
                Button(p.rawValue, systemImage: p.systemImage) {
                    ContactActions.setPriority(targets, p, in: modelContext)
                }
            }
        }
        Menu("Tags", systemImage: "tag") {
            ForEach(allTags, id: \.self) { tag in
                Button("Add “\(tag)”") { ContactActions.addTag(tag, to: targets, in: modelContext) }
            }
            Button("New tag…", systemImage: "plus") { tagTargets = targets }
            let shared = Set(targets.flatMap(\.tags)).sorted()
            if !shared.isEmpty {
                Divider()
                ForEach(shared, id: \.self) { tag in
                    Button("Remove “\(tag)”", role: .destructive) {
                        ContactActions.removeTag(tag, from: targets, in: modelContext)
                    }
                }
            }
        }
        if targets.count == 1, let only = targets.first {
            Button("Add note…", systemImage: "note.text") { noteTarget = only }
            Button("Open", systemImage: "person.text.rectangle") { openedContact = only }
        }
        Divider()
        Button(targets.count == 1 ? "Delete" : "Delete \(targets.count)", systemImage: "trash", role: .destructive) {
            pendingDeletion = targets
        }
    }

    // MARK: - Formatting

    static func relative(_ date: Date) -> String {
        let days = Calendar.current.dateComponents(
            [.day],
            from: Calendar.current.startOfDay(for: date),
            to: Calendar.current.startOfDay(for: Date())
        ).day ?? 0
        switch days {
        case ..<0: return date.formatted(.dateTime.day().month(.abbreviated))
        case 0:    return "Today"
        case 1:    return "Yesterday"
        case 2..<14: return "\(days) days ago"
        case 14..<60: return "\(days / 7) weeks ago"
        default:   return date.formatted(.dateTime.day().month(.abbreviated).year(.twoDigits))
        }
    }
}

// MARK: - Quick note

/// One field, one button: the fastest way to leave a note on someone's timeline.
struct QuickNoteSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    let contact: Contact

    @State private var note = ""
    @State private var countsAsContact = false
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("What happened, what's next…", text: $note, axis: .vertical)
                        .lineLimit(3...8)
                        .focused($focused)
                }
                Section {
                    Toggle("We were in touch today", isOn: $countsAsContact)
                }
            }
            .navigationTitle(contact.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        if countsAsContact {
                            ContactActions.markContacted([contact], type: .message, note: note, in: modelContext)
                        } else {
                            ContactActions.logNote(note, on: contact, in: modelContext)
                        }
                        dismiss()
                    }
                    .keyboardShortcut(.defaultAction)
                    .disabled(note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !countsAsContact)
                }
            }
            .onAppear { focused = true }
        }
        .presentationDetents([.medium])
    }
}
