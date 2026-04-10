import UserNotifications
import Foundation

final class NotificationService {
    static let shared = NotificationService()

    // MARK: - Permission

    func requestAuthorization() async {
        do {
            let granted = try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .badge, .sound])
            print("Notification permission: \(granted)")
        } catch {
            print("Notification auth error: \(error)")
        }
    }

    // MARK: - Schedule Reconnect

    func scheduleReconnect(for name: String, date: Date) {
        let center = UNUserNotificationCenter.current()
        let id = "reconnect-\(name.lowercased().replacingOccurrences(of: " ", with: "-"))"

        // Remove existing notification for this contact
        center.removePendingNotificationRequests(withIdentifiers: [id])

        guard date > Date() else { return }

        let content = UNMutableNotificationContent()
        content.title = "Time to reconnect"
        content.body  = "You planned to reach out to \(name) today."
        content.sound = .default
        content.badge = 1

        var comps = Calendar.current.dateComponents([.year, .month, .day], from: date)
        comps.hour = 9  // 9 AM on the reconnect day

        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
        let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)

        center.add(request) { error in
            if let error { print("Notification schedule error: \(error)") }
        }
    }

    // MARK: - Cancel

    func cancelReconnect(for name: String) {
        let id = "reconnect-\(name.lowercased().replacingOccurrences(of: " ", with: "-"))"
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [id])
    }

    // MARK: - Update badge

    func clearBadge() {
        UNUserNotificationCenter.current().setBadgeCount(0) { _ in }
    }
}
