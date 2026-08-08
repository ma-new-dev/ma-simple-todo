import Contacts
import SwiftData

/// Built on a background thread during import and handed back to the main actor, so it
/// must be neither MainActor-isolated (which -default-isolation=MainActor would otherwise
/// make it) nor non-Sendable.
nonisolated struct ImportedContact: Sendable {
    var name: String
    var emails: [String]
    var phones: [String]
    var company: String
    var jobTitle: String
    var city: String
    var country: String
    var birthday: Date?
    var photoData: Data?
}

@MainActor
final class AppleContactsService {
    static let shared = AppleContactsService()

    private let store = CNContactStore()

    // MARK: - Authorization

    func requestAccess() async throws {
        let status = CNContactStore.authorizationStatus(for: .contacts)
        switch status {
        case .authorized, .limited:
            return
        case .notDetermined:
            let granted = try await store.requestAccess(for: .contacts)
            if !granted { throw ContactsError.accessDenied }
        default:
            throw ContactsError.accessDenied
        }
    }

    // MARK: - Fetch All

    func fetchAll() async throws -> [ImportedContact] {
        try await requestAccess()

        // enumerateContacts is synchronous and decodes every contact plus its thumbnail.
        // Running it on the main actor froze the UI — the "Importing…" spinner could not
        // even animate — and a large address book risked a watchdog termination. Hop to a
        // background task; CNContactStore is safe to use off the main thread.
        return try await Task.detached(priority: .userInitiated) {
            try Self.enumerateAllContacts()
        }.value
    }

    /// Reads the address book. Must not be called on the main thread.
    private nonisolated static func enumerateAllContacts() throws -> [ImportedContact] {
        let keys: [CNKeyDescriptor] = [
            CNContactGivenNameKey as CNKeyDescriptor,
            CNContactFamilyNameKey as CNKeyDescriptor,
            CNContactEmailAddressesKey as CNKeyDescriptor,
            CNContactPhoneNumbersKey as CNKeyDescriptor,
            CNContactOrganizationNameKey as CNKeyDescriptor,
            CNContactJobTitleKey as CNKeyDescriptor,
            CNContactPostalAddressesKey as CNKeyDescriptor,
            CNContactBirthdayKey as CNKeyDescriptor,
            CNContactThumbnailImageDataKey as CNKeyDescriptor,
        ]

        // A store created on this thread, so nothing is shared across the actor boundary.
        let store = CNContactStore()
        let request = CNContactFetchRequest(keysToFetch: keys)
        var results: [ImportedContact] = []

        try store.enumerateContacts(with: request) { cn, _ in
            let given  = cn.givenName
            let family = cn.familyName
            let fullName = [given, family].filter { !$0.isEmpty }.joined(separator: " ")
            guard !fullName.isEmpty else { return }

            let emails = cn.emailAddresses.map { $0.value as String }
            let phones = cn.phoneNumbers.map { $0.value.stringValue }

            var city = ""; var country = ""
            if let addr = cn.postalAddresses.first?.value {
                city    = addr.city
                country = addr.country
            }

            var birthday: Date?
            if let bday = cn.birthday {
                birthday = Calendar.current.date(from: bday)
            }

            results.append(ImportedContact(
                name:      fullName,
                emails:    emails,
                phones:    phones,
                company:   cn.organizationName,
                jobTitle:  cn.jobTitle,
                city:      city,
                country:   country,
                birthday:  birthday,
                photoData: cn.thumbnailImageData
            ))
        }
        return results
    }

    // MARK: - Import into SwiftData

    /// Returns count of newly imported contacts (skips ones already in the store).
    func importIntoStore(context: ModelContext) async throws -> Int {
        let imported = try await fetchAll()

        let existing = try context.fetch(FetchDescriptor<Contact>())

        // Matching is case-insensitive, and the sets grow as we insert, so two Apple
        // contacts sharing an address don't both come through in a single run.
        var seenEmails = Set(existing.flatMap { $0.emails.map(Self.normalizedEmail) })
        // A contact with no email was previously never considered a duplicate, so every
        // phone-only contact was re-imported in full on each run. Fall back to phone, then
        // to name, so those converge too.
        var seenPhones = Set(existing.flatMap { $0.phones.map(Self.normalizedPhone) })
        var seenNames = Set(existing.map { Self.normalizedName($0.name) })

        var count = 0
        for imp in imported {
            let emails = imp.emails.map(Self.normalizedEmail)
            let phones = imp.phones.map(Self.normalizedPhone)
            let name = Self.normalizedName(imp.name)

            let isDuplicate: Bool
            if !emails.isEmpty {
                isDuplicate = emails.contains(where: seenEmails.contains)
            } else if !phones.isEmpty {
                isDuplicate = phones.contains(where: seenPhones.contains)
            } else {
                isDuplicate = !name.isEmpty && seenNames.contains(name)
            }
            guard !isDuplicate else { continue }

            let contact = Contact(
                name:      imp.name,
                city:      imp.city,
                country:   imp.country,
                emails:    imp.emails,
                phones:    imp.phones,
                company:   imp.company,
                jobTitle:  imp.jobTitle,
                birthday:  imp.birthday
            )
            contact.photoData = imp.photoData
            context.insert(contact)

            seenEmails.formUnion(emails)
            seenPhones.formUnion(phones)
            if !name.isEmpty { seenNames.insert(name) }
            count += 1
        }

        // Persist explicitly: relying on autosave meant an import was lost outright if the
        // app was backgrounded or killed before the next autosave tick.
        if count > 0 {
            try context.save()
        }
        return count
    }

    private static func normalizedEmail(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private static func normalizedPhone(_ value: String) -> String {
        String(value.filter(\.isNumber).suffix(10))
    }

    private static func normalizedName(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}

// MARK: - Errors

enum ContactsError: LocalizedError {
    case accessDenied

    var errorDescription: String? {
        switch self {
        case .accessDenied:
            return "Contacts access was denied. Please enable it in Settings > Privacy > Contacts."
        }
    }
}
