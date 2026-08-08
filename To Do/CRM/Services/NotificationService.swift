import UserNotifications
import Foundation

/// Schedules "time to reconnect" reminders for contacts.
///
/// Reminders are keyed by the contact's stable `id` rather than its name, so renaming a
/// contact re-targets its existing reminder instead of orphaning it, and two contacts who
/// share a name keep separate reminders.
final class NotificationService {
    static let shared = NotificationService()

    /// Why a reminder could not be scheduled, so callers can tell the user.
    enum ScheduleResult {
        case scheduled
        case permissionDenied
        case dateInPast
        case failed
    }

    private let center = UNUserNotificationCenter.current()

    // MARK: - Permission

    /// Asks for alert/badge/sound authorization. Returns whether it was granted.
    @discardableResult
    func requestAuthorization() async -> Bool {
        do {
            return try await center.requestAuthorization(options: [.alert, .badge, .sound])
        } catch {
            return false
        }
    }

    // MARK: - Schedule

    private func identifier(for id: UUID) -> String {
        "reconnect-\(id.uuidString)"
    }

    /// Schedules a 9am reminder on `date`, replacing any existing reminder for this contact.
    /// Requests permission first if the user has not been asked yet.
    @discardableResult
    func scheduleReconnect(id: UUID, name: String, date: Date) async -> ScheduleResult {
        cancelReconnect(id: id)

        guard date > Date() else { return .dateInPast }

        switch await center.notificationSettings().authorizationStatus {
        case .notDetermined:
            guard await requestAuthorization() else { return .permissionDenied }
        case .denied:
            return .permissionDenied
        default:
            break
        }

        let content = UNMutableNotificationContent()
        content.title = "Time to reconnect"
        content.body = "You planned to reach out to \(name) today."
        content.sound = .default

        var components = Calendar.current.dateComponents([.year, .month, .day], from: date)
        components.hour = 9

        let request = UNNotificationRequest(
            identifier: identifier(for: id),
            content: content,
            trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        )

        do {
            try await center.add(request)
            return .scheduled
        } catch {
            return .failed
        }
    }

    // MARK: - Cancel

    func cancelReconnect(id: UUID) {
        center.removePendingNotificationRequests(withIdentifiers: [identifier(for: id)])
    }

    // MARK: - Badge

    func clearBadge() {
        center.setBadgeCount(0) { _ in }
    }
}
