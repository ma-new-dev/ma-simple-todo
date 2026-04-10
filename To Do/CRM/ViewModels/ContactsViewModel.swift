import SwiftUI
import SwiftData
import Combine

@MainActor
final class ContactsViewModel: ObservableObject {
    @Published var searchText: String = ""
    @Published var selectedPriority: Priority? = nil
    @Published var selectedTag: String? = nil
    @Published var selectedCity: String? = nil
    @Published var sortOrder: SortOrder = .nameAsc

    enum SortOrder: String, CaseIterable {
        case nameAsc        = "Name (A–Z)"
        case nameDesc       = "Name (Z–A)"
        case priorityDesc   = "Priority (High first)"
        case reconnectSoon  = "Reconnect Soon"
        case recentlyAdded  = "Recently Added"
    }

    // MARK: - Filtering & Sorting

    func filtered(_ contacts: [Contact]) -> [Contact] {
        var result = contacts

        // Search
        if !searchText.isEmpty {
            let q = searchText.lowercased()
            result = result.filter {
                $0.name.lowercased().contains(q)        ||
                $0.company.lowercased().contains(q)     ||
                $0.jobTitle.lowercased().contains(q)    ||
                $0.city.lowercased().contains(q)        ||
                $0.tags.contains(where: { $0.lowercased().contains(q) })
            }
        }

        // Priority filter
        if let p = selectedPriority {
            result = result.filter { $0.priority == p }
        }

        // Tag filter
        if let t = selectedTag {
            result = result.filter { $0.tags.contains(t) }
        }

        // City filter
        if let c = selectedCity {
            result = result.filter { $0.city == c }
        }

        // Sort
        switch sortOrder {
        case .nameAsc:
            result.sort { $0.name < $1.name }
        case .nameDesc:
            result.sort { $0.name > $1.name }
        case .priorityDesc:
            result.sort { $0.priority < $1.priority }
        case .reconnectSoon:
            result.sort {
                guard let a = $0.nextReconnect else { return false }
                guard let b = $1.nextReconnect else { return true }
                return a < b
            }
        case .recentlyAdded:
            result.sort { $0.createdAt > $1.createdAt }
        }

        return result
    }

    func groupedByCity(_ contacts: [Contact]) -> [(city: String, contacts: [Contact])] {
        let filtered = filtered(contacts)
        var dict: [String: [Contact]] = [:]
        for c in filtered {
            let key = c.city.isEmpty ? "Unknown City" : c.city
            dict[key, default: []].append(c)
        }
        return dict.sorted { $0.key < $1.key }.map { (city: $0.key, contacts: $0.value) }
    }

    // MARK: - All tags across contacts

    func allTags(in contacts: [Contact]) -> [String] {
        Array(Set(contacts.flatMap { $0.tags })).sorted()
    }

    func allCities(in contacts: [Contact]) -> [String] {
        Array(Set(contacts.compactMap { $0.city.isEmpty ? nil : $0.city })).sorted()
    }

    // MARK: - Dashboard stats

    func overdueReconnects(in contacts: [Contact]) -> [Contact] {
        contacts.filter { $0.isReconnectOverdue }
            .sorted { ($0.nextReconnect ?? .distantFuture) < ($1.nextReconnect ?? .distantFuture) }
    }

    func upcomingReconnects(in contacts: [Contact], days: Int = 7) -> [Contact] {
        let now = Date()
        let future = Calendar.current.date(byAdding: .day, value: days, to: now) ?? now
        return contacts.filter {
            guard let next = $0.nextReconnect else { return false }
            return next >= now && next <= future
        }
        .sorted { ($0.nextReconnect ?? .distantFuture) < ($1.nextReconnect ?? .distantFuture) }
    }

    func recentlyContacted(in contacts: [Contact], limit: Int = 5) -> [Contact] {
        contacts.compactMap { c in c.lastContacted != nil ? c : nil }
            .sorted { ($0.lastContacted ?? .distantPast) > ($1.lastContacted ?? .distantPast) }
            .prefix(limit)
            .map { $0 }
    }
}
