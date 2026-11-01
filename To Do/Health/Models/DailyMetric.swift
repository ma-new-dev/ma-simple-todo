import Foundation
import SwiftData

/// One calendar day of physiology, keyed to the start of the day in the user's timezone.
///
/// Every property has a default or is optional, and there are no unique constraints —
/// both are hard requirements for CloudKit-backed SwiftData. Ported from Baseline.
@Model
final class DailyMetric {
    var date: Date = Date.distantPast

    // MARK: Whoop — the primary source for all physiology

    var recovery: Double?
    /// Whoop reports HRV as rMSSD. HealthKit reports SDNN. They are different
    /// measures — never write a HealthKit value here.
    var hrv: Double?
    var restingHR: Double?
    var spo2: Double?
    var skinTempC: Double?

    var sleepHours: Double?
    var sleepEfficiency: Double?
    var sleepPerformance: Double?
    var sleepConsistency: Double?
    var deepPct: Double?
    var remPct: Double?
    var respiratoryRate: Double?
    var disturbanceCount: Int?
    /// WHOOP's sleep need for the night, all parts included.
    var sleepNeedHours: Double?
    /// The part of that need carried over from earlier short nights.
    var sleepDebtHours: Double?

    var dayStrain: Double?
    var kilojoules: Double?
    var avgHR: Double?
    var maxHR: Double?
    var bodyMass: Double?

    // MARK: Apple Health — only what Whoop lacks (steps, Watch activity)

    var steps: Double?
    var activeEnergyKcal: Double?
    var exerciseMinutes: Double?

    // MARK: Provenance

    /// "whoop" | "none". There is deliberately no computed fallback score.
    var recoverySource: String = "none"
    var lastSyncedAt: Date?

    init(date: Date) {
        self.date = Calendar.current.startOfDay(for: date)
    }
}

extension DailyMetric {
    /// Sleep duration formatted as "7.1 h", or nil when absent.
    var sleepDisplay: String? {
        guard let sleepHours else { return nil }
        return String(format: "%.1f h", sleepHours)
    }

    /// True when the day has enough to render the Today screen.
    var hasPhysiology: Bool {
        recovery != nil || hrv != nil || sleepHours != nil
    }
}
