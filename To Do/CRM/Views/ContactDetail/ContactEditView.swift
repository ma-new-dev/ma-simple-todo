import SwiftUI
import SwiftData
import PhotosUI

enum ContactEditMode {
    case add
    case edit(Contact)
}

struct ContactEditView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let mode: ContactEditMode

    // Fields
    @State private var name: String = ""
    @State private var city: String = ""
    @State private var country: String = ""
    @State private var emails: [String] = [""]
    @State private var phones: [String] = [""]
    @State private var linkedInURL: String = ""
    @State private var twitterURL: String = ""
    @State private var instagramURL: String = ""
    @State private var company: String = ""
    @State private var jobTitle: String = ""
    @State private var tags: [String] = []
    @State private var newTag: String = ""
    @State private var priority: Priority = .medium
    @State private var howWeMet: String = ""
    @State private var notes: String = ""
    @State private var lastContacted: Date = Date()
    @State private var hasLastContacted: Bool = false
    @State private var lastMetInPerson: Date = Date()
    @State private var hasLastMet: Bool = false
    @State private var nextReconnect: Date = Date()
    @State private var hasNextReconnect: Bool = false
    @State private var birthday: Date = Date()
    @State private var hasBirthday: Bool = false
    @State private var photoItem: PhotosPickerItem?
    @State private var photoData: Data?

    // LinkedIn fetch
    @State private var isFetchingLinkedIn = false
    @State private var linkedInError: String?

    private var isEditing: Bool {
        if case .edit = mode { return true }
        return false
    }

    var body: some View {
        NavigationStack {
            Form {
                // Photo + Name
                photoNameSection

                // Professional
                Section("Professional") {
                    TextField("Job Title", text: $jobTitle)
                    TextField("Company", text: $company)
                }

                // Location
                Section("Location") {
                    TextField("City", text: $city)
                    TextField("Country", text: $country)
                }

                // Contact Details
                Section("Email") {
                    ForEach($emails.indices, id: \.self) { i in
                        HStack {
                            TextField("Email \(i + 1)", text: $emails[i])
                                .keyboardType(.emailAddress)
                                .textInputAutocapitalization(.never)
                            if emails.count > 1 {
                                Button(role: .destructive) { emails.remove(at: i) } label: {
                                    Image(systemName: "minus.circle.fill").foregroundStyle(.red)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    Button(action: { emails.append("") }) {
                        Label("Add Email", systemImage: "plus.circle.fill")
                    }
                }

                Section("Phone") {
                    ForEach($phones.indices, id: \.self) { i in
                        HStack {
                            TextField("Phone \(i + 1)", text: $phones[i])
                                .keyboardType(.phonePad)
                            if phones.count > 1 {
                                Button(role: .destructive) { phones.remove(at: i) } label: {
                                    Image(systemName: "minus.circle.fill").foregroundStyle(.red)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    Button(action: { phones.append("") }) {
                        Label("Add Phone", systemImage: "plus.circle.fill")
                    }
                }

                // Social / LinkedIn
                Section("Social") {
                    linkedInRow
                    TextField("Twitter URL", text: $twitterURL)
                        .textInputAutocapitalization(.never)
                    TextField("Instagram URL", text: $instagramURL)
                        .textInputAutocapitalization(.never)
                }

                // CRM
                Section("CRM") {
                    Picker("Priority", selection: $priority) {
                        ForEach(Priority.allCases, id: \.self) { p in
                            Text(p.rawValue).tag(p)
                        }
                    }

                    // Tags
                    if !tags.isEmpty {
                        TagFlowLayout(tags: tags, removable: true) { tag in
                            tags.removeAll { $0 == tag }
                        }
                        .listRowSeparator(.hidden)
                    }
                    HStack {
                        TextField("Add tag (e.g. VC, Founder)", text: $newTag)
                            .submitLabel(.done)
                            .onSubmit { addTag() }
                        Button(action: addTag) {
                            Image(systemName: "plus.circle.fill")
                                .foregroundStyle(Color("AccentColor"))
                        }
                        .buttonStyle(.plain)
                        .disabled(newTag.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }

                // Dates
                Section("Relationship") {
                    TextField("How We Met", text: $howWeMet)

                    Toggle("Last Contacted", isOn: $hasLastContacted)
                    if hasLastContacted {
                        DatePicker("", selection: $lastContacted, displayedComponents: .date)
                            .datePickerStyle(.compact)
                    }

                    Toggle("Last Met In Person", isOn: $hasLastMet)
                    if hasLastMet {
                        DatePicker("", selection: $lastMetInPerson, displayedComponents: .date)
                            .datePickerStyle(.compact)
                    }

                    Toggle("Next Reconnect", isOn: $hasNextReconnect)
                    if hasNextReconnect {
                        DatePicker("", selection: $nextReconnect, displayedComponents: .date)
                            .datePickerStyle(.compact)
                    }

                    Toggle("Birthday", isOn: $hasBirthday)
                    if hasBirthday {
                        DatePicker("", selection: $birthday, displayedComponents: .date)
                            .datePickerStyle(.compact)
                    }
                }

                // Notes
                Section("Notes") {
                    TextEditor(text: $notes)
                        .frame(minHeight: 80)
                }
            }
            .navigationTitle(isEditing ? "Edit Contact" : "New Contact")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .fontWeight(.semibold)
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .onAppear { loadExistingContact() }
        .onChange(of: photoItem) { _, new in
            Task {
                if let data = try? await new?.loadTransferable(type: Data.self) {
                    photoData = data
                }
            }
        }
    }

    // MARK: - Photo + Name Section

    private var photoNameSection: some View {
        Section {
            HStack(spacing: 16) {
                PhotosPicker(selection: $photoItem, matching: .images) {
                    Group {
                        if let data = photoData, let uiImage = UIImage(data: data) {
                            Image(uiImage: uiImage)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 60, height: 60)
                                .clipShape(Circle())
                        } else {
                            ZStack {
                                Circle()
                                    .fill(Color(.systemGray5))
                                    .frame(width: 60, height: 60)
                                Image(systemName: "camera")
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .buttonStyle(.plain)

                TextField("Full Name", text: $name)
                    .font(.headline)
            }
            .padding(.vertical, 4)
        }
    }

    // MARK: - LinkedIn Row

    private var linkedInRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                TextField("LinkedIn URL", text: $linkedInURL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                if !linkedInURL.isEmpty {
                    Button(action: fetchLinkedIn) {
                        if isFetchingLinkedIn {
                            ProgressView().scaleEffect(0.8)
                        } else {
                            Label("Auto-fill", systemImage: "wand.and.stars")
                                .font(.caption)
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(isFetchingLinkedIn)
                }
            }
            if let err = linkedInError {
                Text(err).font(.caption).foregroundStyle(.red)
            }
        }
    }

    // MARK: - Helpers

    private func addTag() {
        let tag = newTag.trimmingCharacters(in: .whitespaces)
        guard !tag.isEmpty, !tags.contains(tag) else { return }
        tags.append(tag)
        newTag = ""
    }

    private func fetchLinkedIn() {
        guard !linkedInURL.isEmpty else { return }
        isFetchingLinkedIn = true
        linkedInError = nil
        Task {
            do {
                let info = try await LinkedInService.shared.fetchBasicInfo(url: linkedInURL)
                await MainActor.run {
                    if !info.name.isEmpty && name.isEmpty { name = info.name }
                    if !info.jobTitle.isEmpty && jobTitle.isEmpty { jobTitle = info.jobTitle }
                    if !info.company.isEmpty && company.isEmpty { company = info.company }
                    if !info.city.isEmpty && city.isEmpty { city = info.city }
                    isFetchingLinkedIn = false
                }
            } catch {
                await MainActor.run {
                    linkedInError = "Could not auto-fill. Please fill in manually."
                    isFetchingLinkedIn = false
                }
            }
        }
    }

    private func loadExistingContact() {
        guard case .edit(let contact) = mode else { return }
        name            = contact.name
        city            = contact.city
        country         = contact.country
        emails          = contact.emails.isEmpty ? [""] : contact.emails
        phones          = contact.phones.isEmpty ? [""] : contact.phones
        linkedInURL     = contact.linkedInURL
        twitterURL      = contact.twitterURL
        instagramURL    = contact.instagramURL
        company         = contact.company
        jobTitle        = contact.jobTitle
        tags            = contact.tags
        priority        = contact.priority
        howWeMet        = contact.howWeMet
        notes           = contact.notes
        photoData       = contact.photoData

        if let d = contact.lastContacted   { lastContacted = d;    hasLastContacted = true }
        if let d = contact.lastMetInPerson { lastMetInPerson = d;  hasLastMet = true }
        if let d = contact.nextReconnect   { nextReconnect = d;    hasNextReconnect = true }
        if let d = contact.birthday        { birthday = d;         hasBirthday = true }
    }

    private func save() {
        let cleanEmails = emails.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        let cleanPhones = phones.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }

        switch mode {
        case .add:
            let contact = Contact(
                name:           name.trimmingCharacters(in: .whitespaces),
                city:           city,
                country:        country,
                emails:         cleanEmails,
                phones:         cleanPhones,
                linkedInURL:    linkedInURL,
                twitterURL:     twitterURL,
                instagramURL:   instagramURL,
                company:        company,
                jobTitle:       jobTitle,
                tags:           tags,
                priority:       priority,
                howWeMet:       howWeMet,
                notes:          notes,
                lastContacted:  hasLastContacted ? lastContacted : nil,
                lastMetInPerson: hasLastMet ? lastMetInPerson : nil,
                nextReconnect:  hasNextReconnect ? nextReconnect : nil,
                birthday:       hasBirthday ? birthday : nil
            )
            contact.photoData = photoData
            modelContext.insert(contact)

        case .edit(let contact):
            contact.name           = name.trimmingCharacters(in: .whitespaces)
            contact.city           = city
            contact.country        = country
            contact.emails         = cleanEmails
            contact.phones         = cleanPhones
            contact.linkedInURL    = linkedInURL
            contact.twitterURL     = twitterURL
            contact.instagramURL   = instagramURL
            contact.company        = company
            contact.jobTitle       = jobTitle
            contact.tags           = tags
            contact.priority       = priority
            contact.howWeMet       = howWeMet
            contact.notes          = notes
            contact.photoData      = photoData
            contact.lastContacted  = hasLastContacted ? lastContacted : nil
            contact.lastMetInPerson = hasLastMet ? lastMetInPerson : nil
            contact.nextReconnect  = hasNextReconnect ? nextReconnect : nil
            contact.birthday       = hasBirthday ? birthday : nil
            contact.updatedAt      = Date()
        }

        // Schedule notification if reconnect date was set
        if hasNextReconnect {
            NotificationService.shared.scheduleReconnect(
                for: name.trimmingCharacters(in: .whitespaces),
                date: nextReconnect
            )
        }

        dismiss()
    }
}
