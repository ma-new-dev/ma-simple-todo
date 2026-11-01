import SwiftUI
import SwiftData

/// Works through the people who need attention one card at a time — overdue and due-today
/// reconnects, then neglected high-priority contacts — with one tap (or one key on the Mac)
/// per decision. The queue is fixed when the sheet opens so cards don't jump as he acts.
struct CatchUpView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query private var allContacts: [Contact]

    @State private var queue: [Contact] = []
    @State private var index = 0
    @State private var didLoad = false
    @State private var note = ""
    @State private var handled = 0
    @FocusState private var noteFocused: Bool

    private var current: Contact? { queue.indices.contains(index) ? queue[index] : nil }

    var body: some View {
        NavigationStack {
            Group {
                if let contact = current {
                    card(for: contact)
                } else {
                    finished
                }
            }
            .navigationTitle("Catch Up")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                        .keyboardShortcut(.cancelAction)
                }
                if !queue.isEmpty, current != nil {
                    ToolbarItem(placement: .principal) {
                        Text("\(index + 1) of \(queue.count)")
                            .font(.subheadline.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .onAppear {
            guard !didLoad else { return }
            didLoad = true
            queue = ContactActions.catchUpQueue(from: allContacts)
        }
    }

    // MARK: - Card

    private func card(for contact: Contact) -> some View {
        ScrollView {
            VStack(spacing: 20) {
                header(contact)
                context(contact)

                TextField("Note (optional)", text: $note, axis: .vertical)
                    .lineLimit(1...4)
                    .textFieldStyle(.roundedBorder)
                    .focused($noteFocused)

                actions(contact)
            }
            .padding(24)
            .frame(maxWidth: 560)
            .frame(maxWidth: .infinity)
        }
        .id(contact.id)
    }

    private func header(_ contact: Contact) -> some View {
        VStack(spacing: 8) {
            ContactAvatarView(contact: contact, size: 72)
            Text(contact.name).font(.title2.bold())
            let role = [contact.jobTitle, contact.company].filter { !$0.isEmpty }.joined(separator: " · ")
            if !role.isEmpty {
                Text(role).foregroundStyle(.secondary)
            }
            HStack(spacing: 8) {
                PriorityBadge(priority: contact.priority)
                ForEach(contact.tags.prefix(3), id: \.self) { TagChip(tag: $0) }
            }
        }
    }

    private func context(_ contact: Contact) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if let next = contact.nextReconnect {
                row("calendar.badge.exclamationmark",
                    contact.isReconnectOverdue ? "Reconnect was due \(next.formatted(date: .abbreviated, time: .omitted))" : "Reconnect due today",
                    color: .red)
            } else {
                row("star.circle", "High priority, no reconnect planned", color: .orange)
            }
            row("clock",
                contact.lastContacted.map { "Last contacted \(ContactTableView.relative($0).lowercased())" } ?? "Never contacted",
                color: .secondary)
            if !contact.howWeMet.isEmpty {
                row("person.2", contact.howWeMet, color: .secondary)
            }
            if let last = contact.interactionsList.max(by: { $0.date < $1.date }), !last.notes.isEmpty {
                row(last.type.systemImage, "“\(last.notes)”", color: .secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func row(_ icon: String, _ text: String, color: Color) -> some View {
        Label {
            Text(text).font(.subheadline)
        } icon: {
            Image(systemName: icon).foregroundStyle(color)
        }
    }

    // MARK: - Actions

    private func actions(_ contact: Contact) -> some View {
        VStack(spacing: 12) {
            Text("Reached out today")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 10) {
                contactedButton(contact, .message, key: "m")
                contactedButton(contact, .call, key: "c")
                contactedButton(contact, .meeting, key: "t")
            }

            Text("Not now — remind me in")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 10) {
                snoozeButton(contact, .oneWeek, key: "1")
                snoozeButton(contact, .twoWeeks, key: "2")
                snoozeButton(contact, .oneMonth, key: "3")
            }

            HStack {
                if !note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Button("Save note only") {
                        ContactActions.logNote(note, on: contact, in: modelContext)
                        advance(handledIt: true)
                    }
                }
                Spacer()
                Button("Skip") { advance(handledIt: false) }
                    .keyboardShortcut(.rightArrow, modifiers: [])
            }
            .padding(.top, 4)
        }
    }

    private func contactedButton(_ contact: Contact, _ type: InteractionType, key: KeyEquivalent) -> some View {
        Button {
            ContactActions.markContacted([contact], type: type, note: note, in: modelContext)
            advance(handledIt: true)
        } label: {
            Label(type.rawValue, systemImage: type.systemImage)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .keyboardShortcut(key, modifiers: noteFocused ? .command : [])
    }

    private func snoozeButton(_ contact: Contact, _ snooze: ContactActions.Snooze, key: KeyEquivalent) -> some View {
        Button {
            if !note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                ContactActions.logNote(note, on: contact, in: modelContext)
            }
            ContactActions.snooze([contact], snooze, in: modelContext)
            advance(handledIt: true)
        } label: {
            Text(snooze.title).frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .keyboardShortcut(key, modifiers: noteFocused ? .command : [])
    }

    private func advance(handledIt: Bool) {
        if handledIt { handled += 1 }
        note = ""
        noteFocused = false
        withAnimation(.snappy) { index += 1 }
    }

    // MARK: - Finished

    private var finished: some View {
        ContentUnavailableView {
            Label(queue.isEmpty ? "Nobody to catch up with" : "All caught up",
                  systemImage: "checkmark.seal.fill")
        } description: {
            Text(queue.isEmpty
                 ? "No reconnects are due and every high-priority contact has been reached in the last 60 days."
                 : "You handled \(handled) of \(queue.count).")
        } actions: {
            Button("Done") { dismiss() }
                .buttonStyle(.borderedProminent)
        }
    }
}
