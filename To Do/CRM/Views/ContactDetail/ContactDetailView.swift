import SwiftUI
import SwiftData

struct ContactDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Bindable var contact: Contact
    @State private var showEdit = false
    @State private var showAddInteraction = false
    @State private var showReconnectPicker = false

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                // Hero header
                headerSection

                Divider()

                VStack(spacing: 20) {
                    // Reconnect banner (if overdue or set)
                    if contact.nextReconnect != nil {
                        reconnectBanner
                    }

                    // Quick action buttons
                    quickActions

                    // Info sections
                    if !contact.tags.isEmpty || !contact.city.isEmpty {
                        infoSection
                    }

                    // Contact details
                    contactDetailsSection

                    // Notes
                    if !contact.notes.isEmpty || !contact.howWeMet.isEmpty {
                        notesSection
                    }

                    // Interaction timeline
                    InteractionTimelineView(contact: contact, showAddInteraction: $showAddInteraction)

                    Spacer(minLength: 32)
                }
                .padding()
            }
        }
        .navigationTitle(contact.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Edit") { showEdit = true }
            }
        }
        .sheet(isPresented: $showEdit) {
            ContactEditView(mode: .edit(contact))
        }
        .sheet(isPresented: $showAddInteraction) {
            AddInteractionView(contact: contact)
        }
        .sheet(isPresented: $showReconnectPicker) {
            ReconnectPickerView(contact: contact)
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(spacing: 12) {
            ContactAvatarView(contact: contact, size: 80)

            VStack(spacing: 4) {
                Text(contact.name)
                    .font(.title2).fontWeight(.bold)

                if !contact.jobTitle.isEmpty || !contact.company.isEmpty {
                    Text([contact.jobTitle, contact.company].filter { !$0.isEmpty }.joined(separator: " · "))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 8) {
                    PriorityBadge(priority: contact.priority)
                    if !contact.city.isEmpty {
                        Label(contact.city, systemImage: "mappin")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .background(Color(.systemGroupedBackground))
    }

    // MARK: - Reconnect Banner

    private var reconnectBanner: some View {
        Button(action: { showReconnectPicker = true }) {
            HStack {
                Image(systemName: contact.isReconnectOverdue ? "exclamationmark.circle.fill" : "calendar.circle.fill")
                    .foregroundStyle(contact.isReconnectOverdue ? .red : .orange)
                VStack(alignment: .leading, spacing: 2) {
                    Text(contact.isReconnectOverdue ? "Reconnect Overdue" : "Next Reconnect")
                        .font(.subheadline).fontWeight(.semibold)
                        .foregroundStyle(contact.isReconnectOverdue ? .red : .primary)
                    if let date = contact.nextReconnect {
                        Text(date.formatted(date: .long, time: .omitted))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(14)
            .background(contact.isReconnectOverdue ? Color.red.opacity(0.08) : Color.orange.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Quick Actions

    private var quickActions: some View {
        HStack(spacing: 12) {
            if let email = contact.primaryEmail {
                QuickActionButton(icon: "envelope.fill", label: "Email", color: .blue) {
                    if let url = URL(string: "mailto:\(email)") { UIApplication.shared.open(url) }
                }
            }
            if let phone = contact.primaryPhone {
                QuickActionButton(icon: "phone.fill", label: "Call", color: .green) {
                    let clean = phone.filter { $0.isNumber || $0 == "+" }
                    if let url = URL(string: "tel:\(clean)") { UIApplication.shared.open(url) }
                }
            }
            if !contact.linkedInURL.isEmpty {
                QuickActionButton(icon: "person.crop.square.filled.and.at.rectangle", label: "LinkedIn", color: .indigo) {
                    if let url = URL(string: contact.linkedInURL) { UIApplication.shared.open(url) }
                }
            }
            QuickActionButton(icon: "calendar.badge.plus", label: "Reconnect", color: .orange) {
                showReconnectPicker = true
            }
        }
    }

    // MARK: - Info Section

    private var infoSection: some View {
        DetailCard(title: "About") {
            VStack(alignment: .leading, spacing: 10) {
                if !contact.tags.isEmpty {
                    LabeledRow(label: "Tags") {
                        TagFlowLayout(tags: contact.tags)
                    }
                }
                if !contact.city.isEmpty {
                    SimpleRow(label: "Location", value: contact.locationDisplay, icon: "mappin.circle")
                }
                if let birthday = contact.birthday {
                    SimpleRow(label: "Birthday", value: birthday.formatted(date: .long, time: .omitted), icon: "gift")
                }
                if !contact.howWeMet.isEmpty {
                    SimpleRow(label: "How We Met", value: contact.howWeMet, icon: "person.2")
                }
            }
        }
    }

    // MARK: - Contact Details Section

    private var contactDetailsSection: some View {
        DetailCard(title: "Contact") {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(contact.emails, id: \.self) { email in
                    SimpleRow(label: "Email", value: email, icon: "envelope", tappable: "mailto:\(email)")
                }
                ForEach(contact.phones, id: \.self) { phone in
                    SimpleRow(label: "Phone", value: phone, icon: "phone", tappable: "tel:\(phone.filter { $0.isNumber || $0 == "+" })")
                }
                if !contact.linkedInURL.isEmpty {
                    SimpleRow(label: "LinkedIn", value: "View Profile", icon: "person.crop.square.filled.and.at.rectangle", tappable: contact.linkedInURL)
                }
                if !contact.twitterURL.isEmpty {
                    SimpleRow(label: "Twitter", value: "@\(contact.twitterURL.components(separatedBy: "/").last ?? "")", icon: "bird", tappable: contact.twitterURL)
                }
            }
        }
    }

    // MARK: - Notes Section

    private var notesSection: some View {
        DetailCard(title: "Notes") {
            VStack(alignment: .leading, spacing: 8) {
                if let days = contact.daysSinceLastContact {
                    HStack {
                        Image(systemName: "clock").foregroundStyle(.secondary)
                        Text("Last contact: \(days) days ago")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                if !contact.notes.isEmpty {
                    Text(contact.notes)
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                }
            }
        }
    }
}

// MARK: - Supporting Views

struct DetailCard<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

struct SimpleRow: View {
    let label: String
    let value: String
    let icon: String
    var tappable: String? = nil

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(.secondary)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 1) {
                Text(label).font(.caption).foregroundStyle(.secondary)
                Text(value).font(.subheadline)
            }
            Spacer()
            if tappable != nil {
                Image(systemName: "arrow.up.right").font(.caption2).foregroundStyle(.secondary)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if let link = tappable, let url = URL(string: link) {
                UIApplication.shared.open(url)
            }
        }
    }
}

struct LabeledRow<Content: View>: View {
    let label: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            content
        }
    }
}

struct QuickActionButton: View {
    let icon: String
    let label: String
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundStyle(color)
                Text(label)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
    }
}
