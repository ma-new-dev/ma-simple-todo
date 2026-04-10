import Contacts
import SwiftData

struct ImportedContact {
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

    /// Returns count of newly imported contacts (skips duplicates by email)
    func importIntoStore(context: ModelContext) async throws -> Int {
        let imported = try await fetchAll()

        // Fetch existing emails to avoid duplicates
        let existing = try context.fetch(FetchDescriptor<Contact>())
        let existingEmails = Set(existing.flatMap { $0.emails })

        var count = 0
        for imp in imported {
            // Skip if we already have a contact with any of these emails
            let isDuplicate = imp.emails.contains(where: { existingEmails.contains($0) })
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
            count += 1
        }
        return count
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
