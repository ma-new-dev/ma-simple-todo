import SwiftUI
import SwiftData

struct InteractionTimelineView: View {
    @Bindable var contact: Contact
    @Binding var showAddInteraction: Bool

    private var sorted: [Interaction] {
        contact.interactionsList.sorted { $0.date > $1.date }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Timeline")
                    .font(.headline)
                Spacer()
                Button(action: { showAddInteraction = true }) {
                    Label("Log", systemImage: "plus.circle.fill")
                        .font(.subheadline)
                }
            }

            if sorted.isEmpty {
                HStack {
                    Spacer()
                    VStack(spacing: 8) {
                        Image(systemName: "clock")
                            .font(.largeTitle)
                            .foregroundStyle(.quaternary)
                        Text("No interactions logged yet")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 24)
                    Spacer()
                }
            } else {
                VStack(spacing: 0) {
                    ForEach(sorted) { interaction in
                        InteractionRow(interaction: interaction)
                    }
                }
                .background(Color(.secondarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
    }
}

// MARK: - InteractionRow

struct InteractionRow: View {
    @Environment(\.modelContext) private var modelContext
    let interaction: Interaction

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: interaction.type.systemImage)
                .foregroundStyle(Color("AccentColor"))
                .frame(width: 20)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(interaction.type.rawValue)
                        .font(.subheadline)
                        .fontWeight(.medium)
                    Spacer()
                    Text(interaction.date.formatted(date: .abbreviated, time: .omitted))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if !interaction.notes.isEmpty {
                    Text(interaction.notes)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) {
                modelContext.delete(interaction)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
        Divider().padding(.leading, 46)
    }
}

// MARK: - AddInteractionView

struct AddInteractionView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Bindable var contact: Contact

    @State private var type: InteractionType = .meeting
    @State private var date: Date = Date()
    @State private var notes: String = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Type", selection: $type) {
                        ForEach(InteractionType.allCases, id: \.self) { t in
                            Label(t.rawValue, systemImage: t.systemImage).tag(t)
                        }
                    }
                    DatePicker("Date", selection: $date, displayedComponents: [.date])
                }

                Section("Notes") {
                    TextEditor(text: $notes)
                        .frame(minHeight: 80)
                }
            }
            .navigationTitle("Log Interaction")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let interaction = Interaction(date: date, type: type, notes: notes)
                        if contact.interactions == nil { contact.interactions = [] }
                        contact.interactions?.append(interaction)

                        // Update lastContacted if this is most recent
                        if contact.lastContacted == nil || date > contact.lastContacted! {
                            contact.lastContacted = date
                        }
                        if type == .meeting && (contact.lastMetInPerson == nil || date > contact.lastMetInPerson!) {
                            contact.lastMetInPerson = date
                        }
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }
}

// MARK: - ReconnectPickerView

struct ReconnectPickerView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var contact: Contact

    @State private var date: Date
    @State private var clearDate: Bool = false

    init(contact: Contact) {
        self.contact = contact
        _date = State(initialValue: contact.nextReconnect ?? Calendar.current.date(byAdding: .month, value: 1, to: Date()) ?? Date())
    }

    let presets: [(String, DateComponents)] = [
        ("1 Week",   DateComponents(day: 7)),
        ("2 Weeks",  DateComponents(day: 14)),
        ("1 Month",  DateComponents(month: 1)),
        ("3 Months", DateComponents(month: 3)),
        ("6 Months", DateComponents(month: 6)),
    ]

    var body: some View {
        NavigationStack {
            Form {
                Section("Quick Pick") {
                    ForEach(presets, id: \.0) { label, components in
                        Button(action: {
                            if let d = Calendar.current.date(byAdding: components, to: Date()) {
                                date = d
                                clearDate = false
                            }
                        }) {
                            HStack {
                                Text(label)
                                    .foregroundStyle(.primary)
                                Spacer()
                                Text((Calendar.current.date(byAdding: components, to: Date()) ?? Date()).formatted(date: .abbreviated, time: .omitted))
                                    .foregroundStyle(.secondary)
                                    .font(.caption)
                            }
                        }
                    }
                }

                Section("Custom Date") {
                    DatePicker("Date", selection: $date, in: Date()..., displayedComponents: .date)
                        .onChange(of: date) { clearDate = false }
                }

                if contact.nextReconnect != nil {
                    Section {
                        Button("Clear Reconnect Date", role: .destructive) {
                            clearDate = true
                        }
                    }
                }
            }
            .navigationTitle("Set Reconnect")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Set") {
                        contact.nextReconnect = clearDate ? nil : date
                        if !clearDate {
                            NotificationService.shared.scheduleReconnect(for: contact.name, date: date)
                        }
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }
}
