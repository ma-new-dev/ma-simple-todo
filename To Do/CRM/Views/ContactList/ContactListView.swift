import SwiftUI
import SwiftData

struct ContactListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Contact.name) private var contacts: [Contact]
    @StateObject private var vm = ContactsViewModel()
    @State private var showAddContact = false
    @State private var showFilters = false
    @State private var viewMode: ViewMode = .list
    @State private var contactToDelete: Contact?
    @State private var showImport = false

    enum ViewMode: String, CaseIterable {
        case list  = "List"
        case city  = "By City"
    }

    var filtered: [Contact] { vm.filtered(contacts) }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Active filters strip
                if vm.selectedPriority != nil || vm.selectedTag != nil || vm.selectedCity != nil {
                    activeFiltersBar
                }

                Group {
                    switch viewMode {
                    case .list: listContent
                    case .city: byCityContent
                    }
                }
            }
            .searchable(text: $vm.searchText, prompt: "Search contacts…")
            .navigationTitle("Contacts")
            .toolbar { toolbarContent }
            .sheet(isPresented: $showAddContact) { ContactEditView(mode: .add) }
            .sheet(isPresented: $showFilters) { FilterView(vm: vm, contacts: contacts) }
            .sheet(isPresented: $showImport) { ImportContactsView() }
            .confirmationDialog("Delete \(contactToDelete?.name ?? "")?", isPresented: Binding(
                get: { contactToDelete != nil },
                set: { if !$0 { contactToDelete = nil } }
            ), titleVisibility: .visible) {
                Button("Delete", role: .destructive) {
                    if let c = contactToDelete { deleteContact(c) }
                }
            }
        }
    }

    // MARK: - List Content

    private var listContent: some View {
        List {
            if filtered.isEmpty {
                ContentUnavailableView(
                    "No contacts found",
                    systemImage: "person.slash",
                    description: Text(vm.searchText.isEmpty ? "Add your first contact" : "Try a different search")
                )
                .listRowSeparator(.hidden)
            } else {
                ForEach(filtered) { contact in
                    NavigationLink(destination: ContactDetailView(contact: contact)) {
                        ContactRowView(contact: contact)
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(role: .destructive) { contactToDelete = contact } label: {
                            Label("Delete", systemImage: "trash")
                        }
                        NavigationLink(destination: ContactEditView(mode: .edit(contact))) {
                            Label("Edit", systemImage: "pencil")
                        }
                        .tint(.blue)
                    }
                }
            }
        }
        .listStyle(.plain)
    }

    // MARK: - By City Content

    private var byCityContent: some View {
        List {
            ForEach(vm.groupedByCity(contacts), id: \.city) { group in
                Section {
                    ForEach(group.contacts) { contact in
                        NavigationLink(destination: ContactDetailView(contact: contact)) {
                            ContactRowView(contact: contact, showCity: false)
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) { contactToDelete = contact } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                } header: {
                    HStack {
                        Image(systemName: "mappin.circle.fill")
                            .foregroundStyle(.red)
                        Text(group.city)
                            .fontWeight(.semibold)
                        Spacer()
                        Text("\(group.contacts.count)")
                            .foregroundStyle(.secondary)
                            .font(.caption)
                    }
                }
            }
        }
    }

    // MARK: - Active Filters Bar

    private var activeFiltersBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                if let p = vm.selectedPriority {
                    FilterPill(label: p.rawValue, color: .orange) { vm.selectedPriority = nil }
                }
                if let t = vm.selectedTag {
                    FilterPill(label: t, color: Color("AccentColor")) { vm.selectedTag = nil }
                }
                if let c = vm.selectedCity {
                    FilterPill(label: c, color: .red) { vm.selectedCity = nil }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
        .background(Color(.secondarySystemBackground))
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Button(action: { showAddContact = true }) {
                Image(systemName: "plus")
            }
        }
        ToolbarItem(placement: .topBarLeading) {
            Menu {
                Picker("View", selection: $viewMode) {
                    ForEach(ViewMode.allCases, id: \.self) { mode in
                        Label(mode.rawValue, systemImage: mode == .list ? "list.bullet" : "mappin.and.ellipse")
                            .tag(mode)
                    }
                }
                Divider()
                Picker("Sort", selection: $vm.sortOrder) {
                    ForEach(ContactsViewModel.SortOrder.allCases, id: \.self) { order in
                        Text(order.rawValue).tag(order)
                    }
                }
                Divider()
                Button(action: { showFilters = true }) {
                    Label("Filters", systemImage: "line.3.horizontal.decrease.circle")
                }
                Button(action: { showImport = true }) {
                    Label("Import Contacts", systemImage: "square.and.arrow.down")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
        }
    }

    // MARK: - Delete

    private func deleteContact(_ contact: Contact) {
        modelContext.delete(contact)
    }
}

// MARK: - FilterPill

private struct FilterPill: View {
    let label: String
    let color: Color
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            Text(label).font(.caption).fontWeight(.medium)
            Button(action: onRemove) {
                Image(systemName: "xmark").font(.system(size: 9, weight: .bold))
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(color.opacity(0.15))
        .foregroundStyle(color)
        .clipShape(Capsule())
    }
}

#Preview {
    ContactListView()
        .modelContainer(for: Contact.self, inMemory: true)
}
