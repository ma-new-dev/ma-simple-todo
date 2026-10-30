import Foundation
import SwiftData

/// The three-line morning read on the Health tab, generated once a day from WHOOP and
/// Apple Health data. CloudKit rules: every property has a default.
@Model
final class HealthBrief {
    /// Start of the day the brief is for.
    var date: Date = Date.distantPast
    var headline: String = ""
    var goingWell: [String] = []
    var watch: [String] = []
    var today: [String] = []
    var createdAt: Date = Date.distantPast

    init(date: Date) {
        self.date = Calendar.current.startOfDay(for: date)
        self.createdAt = .now
    }
}
