import Foundation
import HealthKit
import SwiftData

/// Reads the few things Apple Health (and now the Apple Watch) adds on top of WHOOP:
/// steps, active energy and exercise minutes. Read-only.
///
/// HRV and sleep are deliberately NOT read from here: WHOOP reports HRV as rMSSD and
/// HealthKit as SDNN, so mixing them would make the series meaningless.
///
/// HealthKit is unavailable when the app runs on the Mac; `isAvailable` is false there
/// and the Health tab shows WHOOP data alone.
@Observable
@MainActor
final class AppleHealthService {
    static let shared = AppleHealthService()

    private let store = HKHealthStore()
    var lastError: String?

    var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    private var readTypes: Set<HKObjectType> {
        [
            HKQuantityType(.stepCount),
            HKQuantityType(.activeEnergyBurned),
            HKQuantityType(.appleExerciseTime),
        ]
    }

    /// Shows the system permission sheet the first time; afterwards it returns at once.
    func requestAccess() async {
        guard isAvailable else { return }
        do {
            try await store.requestAuthorization(toShare: [], read: readTypes)
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// Writes the last `days` days of daily totals onto the matching `DailyMetric` rows.
    func sync(into context: ModelContext, days: Int = 8) async {
        guard isAvailable else { return }
        await requestAccess()

        let calendar = Calendar.current
        let end = Date()
        guard let start = calendar.date(byAdding: .day, value: -(days - 1), to: calendar.startOfDay(for: end)) else { return }

        async let steps = dailySums(.stepCount, unit: .count(), from: start, to: end)
        async let energy = dailySums(.activeEnergyBurned, unit: .kilocalorie(), from: start, to: end)
        async let exercise = dailySums(.appleExerciseTime, unit: .minute(), from: start, to: end)
        let (s, e, x) = await (steps, energy, exercise)

        for (day, value) in s { metric(for: day, in: context).steps = value }
        for (day, value) in e { metric(for: day, in: context).activeEnergyKcal = value }
        for (day, value) in x { metric(for: day, in: context).exerciseMinutes = value }
        try? context.save()
    }

    // MARK: - Queries

    private func dailySums(
        _ id: HKQuantityTypeIdentifier,
        unit: HKUnit,
        from start: Date,
        to end: Date
    ) async -> [Date: Double] {
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end)
        let descriptor = HKStatisticsCollectionQueryDescriptor(
            predicate: HKSamplePredicate.quantitySample(type: HKQuantityType(id), predicate: predicate),
            options: .cumulativeSum,
            anchorDate: Calendar.current.startOfDay(for: start),
            intervalComponents: DateComponents(day: 1)
        )
        do {
            let collection = try await descriptor.result(for: store)
            var result: [Date: Double] = [:]
            collection.enumerateStatistics(from: start, to: end) { stats, _ in
                if let sum = stats.sumQuantity() {
                    result[stats.startDate] = sum.doubleValue(for: unit)
                }
            }
            return result
        } catch {
            lastError = error.localizedDescription
            return [:]
        }
    }

    private func metric(for date: Date, in context: ModelContext) -> DailyMetric {
        let day = Calendar.current.startOfDay(for: date)
        let descriptor = FetchDescriptor<DailyMetric>(predicate: #Predicate { $0.date == day })
        if let existing = try? context.fetch(descriptor).first { return existing }
        let created = DailyMetric(date: day)
        context.insert(created)
        return created
    }
}
