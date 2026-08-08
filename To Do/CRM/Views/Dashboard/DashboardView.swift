import SwiftUI
import SwiftData

struct DashboardView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var contacts: [Contact]
    @StateObject private var vm = ContactsViewModel()
    @State private var showAddContact = false

    private var overdue: [Contact] { vm.overdueReconnects(in: contacts) }
    private var upcoming: [Contact] { vm.upcomingReconnects(in: contacts, days: 7) }
    private var recent: [Contact]   { vm.recentlyContacted(in: contacts, limit: 5) }

    // Navigation is owned by CRMRootView; this view only contributes its title, toolbar
    // and destinations to that stack.
    var body: some View {
        ScrollView {
                VStack(alignment: .leading, spacing: 24) {

                    // Stats are meaningless before any contact exists, and rendering
                    // "0 / 0 / 0" above the empty state made first launch look broken.
                    if !contacts.isEmpty {
                        statsRow
                    }

                    // Overdue reconnects
                    if !overdue.isEmpty {
                        DashboardSection(title: "Overdue Reconnects", icon: "exclamationmark.circle.fill", iconColor: .red) {
                            ForEach(overdue) { contact in
                                NavigationLink(destination: ContactDetailView(contact: contact)) {
                                    ReconnectRow(contact: contact, overdue: true)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    // Upcoming this week
                    if !upcoming.isEmpty {
                        DashboardSection(title: "Reconnect This Week", icon: "calendar.circle.fill", iconColor: .orange) {
                            ForEach(upcoming) { contact in
                                NavigationLink(destination: ContactDetailView(contact: contact)) {
                                    ReconnectRow(contact: contact, overdue: false)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    // Recently contacted
                    if !recent.isEmpty {
                        DashboardSection(title: "Recently Contacted", icon: "clock.circle.fill", iconColor: .blue) {
                            ForEach(recent) { contact in
                                NavigationLink(destination: ContactDetailView(contact: contact)) {
                                    RecentContactRow(contact: contact)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    // Empty state
                    if contacts.isEmpty {
                        emptyState
                    }
                }
                .padding()
        }
        .navigationTitle("Dashboard")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(action: { showAddContact = true }) {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Add contact")
            }
        }
        .sheet(isPresented: $showAddContact) {
            ContactEditView(mode: .add)
        }
    }

    // MARK: - Stats Row

    private var statsRow: some View {
        HStack(spacing: 12) {
            StatCard(value: contacts.count,                title: "Total",   color: .blue)
            StatCard(value: contacts.filter { $0.priority == .high }.count,   title: "High Priority", color: .red)
            StatCard(value: overdue.count,                 title: "Overdue", color: .orange)
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "person.crop.circle.badge.plus")
                .font(.system(size: 60))
                .foregroundStyle(.secondary)
                .symbolRenderingMode(.hierarchical)
            Text("Add your first contact")
                .font(.headline)
                .foregroundStyle(.secondary)
            Button("Add Contact") { showAddContact = true }
                .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }
}

// MARK: - Supporting Views

private struct DashboardSection<Content: View>: View {
    let title: String
    let icon: String
    let iconColor: Color
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .foregroundStyle(iconColor)
                Text(title)
                    .font(.headline)
            }
            VStack(spacing: 0) {
                content
            }
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }
}

private struct StatCard: View {
    let value: Int
    let title: String
    let color: Color

    var body: some View {
        VStack(spacing: 4) {
            Text("\(value)")
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundStyle(color)
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

private struct ReconnectRow: View {
    let contact: Contact
    let overdue: Bool

    var body: some View {
        HStack(spacing: 12) {
            ContactAvatarView(contact: contact, size: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text(contact.name)
                    .font(.subheadline).fontWeight(.semibold)
                if let next = contact.nextReconnect {
                    Text(overdue ? "Was due \(next.formatted(.relative(presentation: .named)))" : "Due \(next.formatted(date: .abbreviated, time: .omitted))")
                        .font(.caption)
                        .foregroundStyle(overdue ? .red : .orange)
                }
            }
            Spacer()
            PriorityBadge(priority: contact.priority, compact: true)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        Divider().padding(.leading, 66)
    }
}

private struct RecentContactRow: View {
    let contact: Contact

    var body: some View {
        HStack(spacing: 12) {
            ContactAvatarView(contact: contact, size: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text(contact.name)
                    .font(.subheadline).fontWeight(.semibold)
                if let date = contact.lastContacted {
                    Text(date.formatted(.relative(presentation: .named)))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            if !contact.city.isEmpty {
                Label(contact.city, systemImage: "mappin")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        Divider().padding(.leading, 66)
    }
}

#Preview {
    DashboardView()
        .modelContainer(for: Contact.self, inMemory: true)
}
