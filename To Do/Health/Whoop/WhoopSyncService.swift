import Foundation
import SwiftData

/// Pulls the last few weeks of WHOOP data and folds it into `DailyMetric` / `Workout`.
///
/// Idempotent: re-running overwrites the same day rather than duplicating it.
@Observable
@MainActor
final class WhoopSyncService {
    static let shared = WhoopSyncService()

    var isSyncing = false
    var lastError: String?

    /// Persisted, so staleness survives relaunches — the Today banner needs
    /// "last synced 26 h ago" to be true even on a cold start.
    private static let lastSyncKey = "whoop.lastSyncedAt"
    var lastSyncedAt: Date? {
        get {
            access(keyPath: \.lastSyncedAt)
            let seconds = UserDefaults.standard.double(forKey: Self.lastSyncKey)
            return seconds > 0 ? Date(timeIntervalSince1970: seconds) : nil
        }
        set {
            withMutation(keyPath: \.lastSyncedAt) {
                UserDefaults.standard.set(newValue?.timeIntervalSince1970 ?? 0, forKey: Self.lastSyncKey)
            }
        }
    }

    /// The Today banner's condition: connected, but nothing for over a day.
    var isStale: Bool {
        guard WhoopTokenStore.shared.isConnected else { return false }
        guard let last = lastSyncedAt else { return true }
        return Date().timeIntervalSince(last) > 24 * 3600
    }

    /// Don't re-sync more often than this on foreground.
    private let minInterval: TimeInterval = 4 * 3600

    func syncIfStale(into context: ModelContext) async {
        if let last = lastSyncedAt, Date().timeIntervalSince(last) < minInterval { return }
        await sync(into: context)
    }

    func sync(into context: ModelContext, daysBack: Int = 21) async {
        guard !isSyncing else { return }
        isSyncing = true
        lastError = nil
        defer { isSyncing = false }

        do {
            let token = try await WhoopTokenStore.shared.validAccessToken()
            let start = Calendar.current.date(byAdding: .day, value: -daysBack, to: Date())!

            async let recoveries = WhoopAPI.getPage(.recovery, of: WhoopRecovery.self, start: start, token: token)
            async let sleeps = WhoopAPI.getPage(.sleep, of: WhoopSleep.self, start: start, token: token)
            async let cycles = WhoopAPI.getPage(.cycle, of: WhoopCycle.self, start: start, token: token)
            async let workouts = WhoopAPI.getPage(.workout, of: WhoopWorkout.self, start: start, token: token)

            let (r, s, c, w) = try await (recoveries, sleeps, cycles, workouts)

            apply(recoveries: r.records, into: context)
            apply(sleeps: s.records, into: context)
            apply(cycles: c.records, into: context)
            apply(workouts: w.records, into: context)

            // Body measurement is a single current value, not a series.
            if let body = try? await WhoopAPI.getObject(.bodyMeasurement, of: WhoopBodyMeasurement.self, token: token),
               let weight = body.weightKilogram {
                metric(for: Date(), in: context).bodyMass = weight
            }

            try context.save()
            lastSyncedAt = Date()
        } catch {
            lastError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    // MARK: Folding

    private func apply(recoveries: [WhoopRecovery], into context: ModelContext) {
        for record in recoveries {
            guard let score = record.score else { continue }
            let day = metric(for: record.createdAt, in: context)
            day.recovery = score.recoveryScore
            day.hrv = score.hrvRmssdMilli
            day.restingHR = score.restingHeartRate
            day.spo2 = score.spo2Percentage
            day.skinTempC = score.skinTempCelsius
            day.recoverySource = score.recoveryScore == nil ? "none" : "whoop"
            day.lastSyncedAt = Date()
        }
    }

    private func apply(sleeps: [WhoopSleep], into context: ModelContext) {
        for record in sleeps {
            // Naps shouldn't overwrite the night's numbers.
            if record.nap == true { continue }
            guard let score = record.score else { continue }
            // Attribute a night's sleep to the morning you woke up.
            let day = metric(for: record.end, in: context)
            day.sleepPerformance = score.sleepPerformancePercentage
            day.sleepConsistency = score.sleepConsistencyPercentage
            day.sleepEfficiency = score.sleepEfficiencyPercentage
            day.respiratoryRate = score.respiratoryRate

            if let stages = score.stageSummary {
                day.sleepHours = stages.asleepHours
                day.disturbanceCount = stages.disturbanceCount
                if let asleep = stages.asleepMilli, asleep > 0 {
                    if let deep = stages.totalSlowWaveSleepTimeMilli {
                        day.deepPct = deep / asleep * 100
                    }
                    if let rem = stages.totalRemSleepTimeMilli {
                        day.remPct = rem / asleep * 100
                    }
                }
            }
            day.lastSyncedAt = Date()
        }
    }

    private func apply(cycles: [WhoopCycle], into context: ModelContext) {
        for record in cycles {
            guard let score = record.score else { continue }
            let day = metric(for: record.start, in: context)
            day.dayStrain = score.strain
            day.kilojoules = score.kilojoule
            day.avgHR = score.averageHeartRate
            day.maxHR = score.maxHeartRate
            day.lastSyncedAt = Date()
        }
    }

    private func apply(workouts: [WhoopWorkout], into context: ModelContext) {
        for record in workouts {
            let recordID = record.id
            let existing = try? context.fetch(
                FetchDescriptor<Workout>(
                    predicate: #Predicate { $0.externalID == recordID }
                )
            ).first

            let duration = record.end.timeIntervalSince(record.start) / 60
            let workout = existing ?? Workout(
                date: record.start,
                externalID: record.id,
                type: record.sportName ?? "activity",
                durationMin: duration,
                source: "whoop"
            )

            workout.date = record.start
            workout.type = record.sportName ?? "activity"
            workout.durationMin = duration
            workout.strain = record.score?.strain
            workout.avgHR = record.score?.averageHeartRate
            workout.maxHR = record.score?.maxHeartRate
            if let metres = record.score?.distanceMeter {
                workout.distanceKm = metres / 1000
            }
            workout.zoneMinutes = record.score?.zoneDurations?.minutesAscending ?? []

            if existing == nil { context.insert(workout) }
        }
    }

    /// Fetch-or-create the `DailyMetric` for a given instant's calendar day.
    private func metric(for instant: Date, in context: ModelContext) -> DailyMetric {
        let day = Calendar.current.startOfDay(for: instant)
        let descriptor = FetchDescriptor<DailyMetric>(
            predicate: #Predicate { $0.date == day }
        )
        if let found = try? context.fetch(descriptor).first {
            return found
        }
        let created = DailyMetric(date: day)
        context.insert(created)
        return created
    }
}
