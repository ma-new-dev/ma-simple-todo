import SwiftUI
import SwiftData
import PhotosUI
import ImageIO
import UniformTypeIdentifiers

enum ContactEditMode {
    case add
    case edit(Contact)
}

/// A single text entry in a repeatable field (email, phone).
///
/// Rows carry a stable identity so `ForEach` keeps tracking the right row when one is
/// removed. Identifying by array index instead traps with "Index out of range", because
/// SwiftUI re-evaluates a stale row body against the shrunken array.
private struct EditableValue: Identifiable {
    let id = UUID()
    var text: String

    // The target builds with -default-isolation=MainActor, which would make this init
    // MainActor-isolated and warn when passed to a nonisolated `map`. It touches nothing
    // shared, so opt it out.
    nonisolated init(_ text: String = "") {
        self.text = text
    }
}

struct ContactEditView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let mode: ContactEditMode

    // Fields
    @State private var name: String = ""
    @State private var city: String = ""
    @State private var country: String = ""
    @State private var emails: [EditableValue] = [EditableValue()]
    @State private var phones: [EditableValue] = [EditableValue()]
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

    @State private var hasLoadedContact = false
    @State private var isSaving = false
    @State private var photoError: String?
    @State private var saveError: String?
    @State private var showReminderPermissionNotice = false

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
                    ForEach($emails) { $entry in
                        HStack {
                            TextField("Email", text: $entry.text)
                                .keyboardType(.emailAddress)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                            if emails.count > 1 {
                                removeButton(label: "Remove email") {
                                    emails.removeAll { $0.id == entry.id }
                                }
                            }
                        }
                    }
                    Button(action: { emails.append(EditableValue()) }) {
                        Label("Add Email", systemImage: "plus.circle.fill")
                    }
                }

                Section("Phone") {
                    ForEach($phones) { $entry in
                        HStack {
                            TextField("Phone", text: $entry.text)
                                .keyboardType(.phonePad)
                            if phones.count > 1 {
                                removeButton(label: "Remove phone") {
                                    phones.removeAll { $0.id == entry.id }
                                }
                            }
                        }
                    }
                    Button(action: { phones.append(EditableValue()) }) {
                        Label("Add Phone", systemImage: "plus.circle.fill")
                    }
                }

                // Social
                Section("Social") {
                    TextField("LinkedIn URL", text: $linkedInURL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    TextField("Twitter URL", text: $twitterURL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    TextField("Instagram URL", text: $instagramURL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
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
                        .accessibilityLabel("Add tag")
                        .disabled(newTag.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }

                // Dates
                Section("Relationship") {
                    TextField("How We Met", text: $howWeMet)

                    Toggle("Last Contacted", isOn: $hasLastContacted)
                    if hasLastContacted {
                        DatePicker("Last contacted date", selection: $lastContacted, displayedComponents: .date)
                            .datePickerStyle(.compact)
                            .labelsHidden()
                    }

                    Toggle("Last Met In Person", isOn: $hasLastMet)
                    if hasLastMet {
                        DatePicker("Last met in person date", selection: $lastMetInPerson, displayedComponents: .date)
                            .datePickerStyle(.compact)
                            .labelsHidden()
                    }

                    Toggle("Next Reconnect", isOn: $hasNextReconnect)
                    if hasNextReconnect {
                        DatePicker("Next reconnect date", selection: $nextReconnect, displayedComponents: .date)
                            .datePickerStyle(.compact)
                            .labelsHidden()
                    }

                    Toggle("Birthday", isOn: $hasBirthday)
                    if hasBirthday {
                        DatePicker("Birthday date", selection: $birthday, displayedComponents: .date)
                            .datePickerStyle(.compact)
                            .labelsHidden()
                    }
                }

                // Notes
                Section("Notes") {
                    TextEditor(text: $notes)
                        .frame(minHeight: 80)
                        .accessibilityLabel("Notes")
                }
            }
            .navigationTitle(isEditing ? "Edit Contact" : "New Contact")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { Task { await save() } }
                        .fontWeight(.semibold)
                        .disabled(isSaving || name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .alert("Couldn't Save Contact", isPresented: Binding(
                get: { saveError != nil },
                set: { if !$0 { saveError = nil } }
            )) {
                Button("OK", role: .cancel) { saveError = nil }
            } message: {
                Text(saveError ?? "")
            }
            .alert("Reminders Are Off", isPresented: $showReminderPermissionNotice) {
                Button("OK", role: .cancel) { dismiss() }
            } message: {
                Text("The contact was saved, but reconnect reminders need notification permission. You can turn it on in Settings › Notifications.")
            }
        }
        .task {
            // `onAppear` re-fires when the PhotosPicker is dismissed, which would wipe
            // in-progress edits. Load exactly once instead.
            guard !hasLoadedContact else { return }
            hasLoadedContact = true
            loadExistingContact()
        }
        .onChange(of: photoItem) { _, newItem in
            Task { await loadPhoto(from: newItem) }
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
                .accessibilityLabel("Contact photo")

                TextField("Full Name", text: $name)
                    .font(.headline)
            }
            .padding(.vertical, 4)
        } footer: {
            if let photoError {
                Text(photoError).foregroundStyle(.red)
            }
        }
    }

    // MARK: - Helpers

    private func removeButton(label: String, action: @escaping () -> Void) -> some View {
        Button(role: .destructive, action: action) {
            Image(systemName: "minus.circle.fill").foregroundStyle(.red)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private func addTag() {
        let tag = newTag.trimmingCharacters(in: .whitespaces)
        guard !tag.isEmpty, !tags.contains(tag) else { return }
        tags.append(tag)
        newTag = ""
    }

    /// Loads a picked image and shrinks it before it ever reaches the store.
    ///
    /// Contact photos live inline in a CloudKit-backed store, and CloudKit silently drops
    /// records over ~1 MB. A full-resolution iPhone photo is 3-12 MB, so storing one would
    /// stop that contact syncing with no visible error. Downsampling keeps avatars well
    /// under the limit.
    private func loadPhoto(from item: PhotosPickerItem?) async {
        guard let item else { return }
        photoError = nil

        guard let data = try? await item.loadTransferable(type: Data.self) else {
            photoError = "Couldn't load that image. Please try another."
            return
        }

        guard let downsampled = Self.downsampledAvatar(from: data) else {
            photoError = "Couldn't process that image. Please try another."
            return
        }

        photoData = downsampled
    }

    /// Produces a small JPEG suitable for an avatar (typically 30-60 KB).
    private static func downsampledAvatar(from data: Data, maxPixelSize: CGFloat = 512) -> Data? {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
        ]

        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
        else { return nil }

        return UIImage(cgImage: thumbnail).jpegData(compressionQuality: 0.8)
    }

    private func loadExistingContact() {
        guard case .edit(let contact) = mode else { return }
        name            = contact.name
        city            = contact.city
        country         = contact.country
        emails          = contact.emails.isEmpty ? [EditableValue()] : contact.emails.map(EditableValue.init)
        phones          = contact.phones.isEmpty ? [EditableValue()] : contact.phones.map(EditableValue.init)
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

    private func save() async {
        guard !isSaving else { return }
        isSaving = true
        defer { isSaving = false }

        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        let cleanEmails = emails.map { $0.text.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        let cleanPhones = phones.map { $0.text.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }

        let contact: Contact

        switch mode {
        case .add:
            let newContact = Contact(
                name:           trimmedName,
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
            newContact.photoData = photoData
            modelContext.insert(newContact)
            contact = newContact

        case .edit(let existing):
            existing.name            = trimmedName
            existing.city            = city
            existing.country         = country
            existing.emails          = cleanEmails
            existing.phones          = cleanPhones
            existing.linkedInURL     = linkedInURL
            existing.twitterURL      = twitterURL
            existing.instagramURL    = instagramURL
            existing.company         = company
            existing.jobTitle        = jobTitle
            existing.tags            = tags
            existing.priority        = priority
            existing.howWeMet        = howWeMet
            existing.notes           = notes
            existing.photoData       = photoData
            existing.lastContacted   = hasLastContacted ? lastContacted : nil
            existing.lastMetInPerson = hasLastMet ? lastMetInPerson : nil
            existing.nextReconnect   = hasNextReconnect ? nextReconnect : nil
            existing.birthday        = hasBirthday ? birthday : nil
            existing.updatedAt       = Date()
            contact = existing
        }

        // Persist explicitly rather than relying on autosave, so the edit survives the app
        // being backgrounded or killed straight after saving.
        do {
            try modelContext.save()
        } catch {
            saveError = error.localizedDescription
            return
        }

        let contactID = contact.id

        if hasNextReconnect {
            let result = await NotificationService.shared.scheduleReconnect(
                id: contactID,
                name: trimmedName,
                date: nextReconnect
            )
            if result == .permissionDenied {
                showReminderPermissionNotice = true
                return
            }
        } else {
            NotificationService.shared.cancelReconnect(id: contactID)
        }

        dismiss()
    }
}
