import Foundation
import HealthKit
import SwiftData

/// Reads what the Apple Watch measures that WHOOP doesn't: daily activity, Cardio Fitness
/// (VO2 max), cardio recovery, time in daylight, weight and body fat, sleeping wrist
/// temperature and breathing disturbances, plus workouts with GPS distance, pace, splits,
/// elevation, power and cadence. Read-only.
///
/// HRV, resting HR and sleep are deliberately NOT read from here: WHOOP is the source for
/// those, and Apple's HRV is SDNN where WHOOP's is rMSSD, so mixing them would make the
/// series meaningless.
///
/// A session both devices recorded (a run tracked by WHOOP and the watch) stays one
/// workout: the WHOOP row keeps its strain and gains the watch's distance, pace and splits.
///
/// HealthKit is unavailable when the app runs on the Mac; `isAvailable` is false there
/// and the data arrives through iCloud from the phone instead.
@Observable
@MainActor
final class AppleHealthService {
    static let shared = AppleHealthService()

    private let store = HKHealthStore()
    var lastError: String?

    var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    /// Set once six months have been read, for the trends; later syncs read two weeks.
    private static let backfillKey = "health.backfilled180"

    private var readTypes: Set<HKObjectType> {
        [
            HKQuantityType(.stepCount),
            HKQuantityType(.activeEnergyBurned),
            HKQuantityType(.appleExerciseTime),
            HKQuantityType(.vo2Max),
            HKQuantityType(.heartRateRecoveryOneMinute),
            HKQuantityType(.timeInDaylight),
            HKQuantityType(.bodyMass),
            HKQuantityType(.bodyFatPercentage),
            HKQuantityType(.appleSleepingWristTemperature),
            HKQuantityType(.appleSleepingBreathingDisturbances),
            HKQuantityType(.heartRate),
            HKQuantityType(.distanceWalkingRunning),
            HKQuantityType(.runningPower),
            HKQuantityType(.workoutEffortScore),
            HKQuantityType(.estimatedWorkoutEffortScore),
            HKObjectType.workoutType(),
        ]
    }

    /// Shows the system permission sheet the first time (and again when new types are
    /// added); afterwards it returns at once.
    func requestAccess() async {
        guard isAvailable else { return }
        do {
            try await store.requestAuthorization(toShare: [], read: readTypes)
        } catch {
            lastError = error.localizedDescription
        }
    }

    func sync(into context: ModelContext, days: Int? = nil) async {
        guard isAvailable else { return }
        await requestAccess()

        let backfill = !UserDefaults.standard.bool(forKey: Self.backfillKey)
        let days = days ?? (backfill ? 185 : 14)
        let calendar = Calendar.current
        let end = Date()
        guard let start = calendar.date(byAdding: .day, value: -(days - 1), to: calendar.startOfDay(for: end)) else { return }

        // Daily totals and averages.
        async let steps = daily(.stepCount, .count(), .cumulativeSum, from: start, to: end)
        async let energy = daily(.activeEnergyBurned, .kilocalorie(), .cumulativeSum, from: start, to: end)
        async let exercise = daily(.appleExerciseTime, .minute(), .cumulativeSum, from: start, to: end)
        async let daylight = daily(.timeInDaylight, .minute(), .cumulativeSum, from: start, to: end)
        async let vo2 = daily(.vo2Max, HKUnit(from: "ml/kg*min"), .discreteAverage, from: start, to: end)
        async let recovery = daily(.heartRateRecoveryOneMinute, .count().unitDivided(by: .minute()), .discreteAverage, from: start, to: end)
        async let weight = daily(.bodyMass, .gramUnit(with: .kilo), .mostRecent, from: start, to: end)
        async let fat = daily(.bodyFatPercentage, .percent(), .mostRecent, from: start, to: end)
        async let wrist = daily(.appleSleepingWristTemperature, .degreeCelsius(), .discreteAverage, from: start, to: end)
        async let breathing = daily(.appleSleepingBreathingDisturbances, .count(), .discreteAverage, from: start, to: end)

        let (s, e, x, d, v, r, w, f, t, b) = await (steps, energy, exercise, daylight, vo2, recovery, weight, fat, wrist, breathing)
        for (day, value) in s { metric(for: day, in: context).steps = value }
        for (day, value) in e { metric(for: day, in: context).activeEnergyKcal = value }
        for (day, value) in x { metric(for: day, in: context).exerciseMinutes = value }
        for (day, value) in d { metric(for: day, in: context).daylightMinutes = value }
        for (day, value) in v { metric(for: day, in: context).vo2Max = value }
        for (day, value) in r { metric(for: day, in: context).cardioRecoveryBpm = value }
        for (day, value) in w { metric(for: day, in: context).weightKg = value }
        for (day, value) in f { metric(for: day, in: context).bodyFatPct = value * 100 }
        // HealthKit stores the wrist reading as a deviation from the watch's baseline.
        for (day, value) in t { metric(for: day, in: context).wristTempDeltaC = value }
        for (day, value) in b { metric(for: day, in: context).breathingDisturbances = value }

        await syncWorkouts(from: start, into: context)

        do {
            try context.save()
            if days >= 180 { UserDefaults.standard.set(true, forKey: Self.backfillKey) }
        } catch {
            lastError = error.localizedDescription
        }
    }

    // MARK: - Daily statistics

    private func daily(
        _ id: HKQuantityTypeIdentifier,
        _ unit: HKUnit,
        _ option: HKStatisticsOptions,
        from start: Date,
        to end: Date
    ) async -> [Date: Double] {
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end)
        let descriptor = HKStatisticsCollectionQueryDescriptor(
            predicate: HKSamplePredicate.quantitySample(type: HKQuantityType(id), predicate: predicate),
            options: option,
            anchorDate: Calendar.current.startOfDay(for: start),
            intervalComponents: DateComponents(day: 1)
        )
        do {
            let collection = try await descriptor.result(for: store)
            var result: [Date: Double] = [:]
            collection.enumerateStatistics(from: start, to: end) { stats, _ in
                let quantity: HKQuantity? = switch option {
                case .cumulativeSum: stats.sumQuantity()
                case .mostRecent: stats.mostRecentQuantity()
                default: stats.averageQuantity()
                }
                if let quantity { result[stats.startDate] = quantity.doubleValue(for: unit) }
            }
            return result
        } catch {
            // A type he hasn't granted, or that this watch doesn't record, just stays empty.
            return [:]
        }
    }

    // MARK: - Workouts

    private func syncWorkouts(from start: Date, into context: ModelContext) async {
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.workout(HKQuery.predicateForSamples(withStart: start, end: .now))],
            sortDescriptors: [SortDescriptor(\.startDate)]
        )
        guard let workouts = try? await descriptor.result(for: store) else { return }
        let cutoff = start
        let existing = (try? context.fetch(FetchDescriptor<Workout>(predicate: #Predicate { $0.date >= cutoff }))) ?? []

        for hk in workouts where hk.duration >= 10 * 60 {
            let id = hk.uuid.uuidString
            // Already merged or imported on an earlier sync: refresh in place.
            let target = existing.first { $0.healthKitID == id || ($0.source == "healthkit" && $0.externalID == id) }
                ?? Self.matchingWhoopWorkout(start: hk.startDate, end: hk.endDate, in: existing)
                ?? {
                    let created = Workout(date: hk.startDate, externalID: id, type: Self.typeName(hk.workoutActivityType),
                                          durationMin: hk.duration / 60, source: "healthkit")
                    context.insert(created)
                    return created
                }()

            target.healthKitID = id
            if target.source == "healthkit" {
                target.avgHR = average(.heartRate, .count().unitDivided(by: .minute()), in: hk)
                target.maxHR = hk.statistics(for: HKQuantityType(.heartRate))?.maximumQuantity()?.doubleValue(for: .count().unitDivided(by: .minute()))
            }
            if let meters = hk.statistics(for: HKQuantityType(.distanceWalkingRunning))?.sumQuantity()?.doubleValue(for: .meter()), meters > 200 {
                target.distanceKm = meters / 1000
                target.splitsSecPerKm = await splits(for: hk)
            }
            if let elevation = hk.metadata?[HKMetadataKeyElevationAscended] as? HKQuantity {
                target.elevationGainM = elevation.doubleValue(for: .meter())
            }
            target.avgPowerW = average(.runningPower, .watt(), in: hk)
            if let steps = await stepCount(during: hk), hk.duration > 0, Self.isOnFoot(hk.workoutActivityType) {
                target.avgCadenceSpm = steps / (hk.duration / 60)
            }
            target.effortScore = await effort(for: hk)
        }
    }

    /// A WHOOP session that overlaps the watch's and started within 15 minutes of it.
    static func matchingWhoopWorkout(start: Date, end: Date, in workouts: [Workout]) -> Workout? {
        workouts
            .filter { $0.source == "whoop" && abs($0.date.timeIntervalSince(start)) < 15 * 60 }
            .filter { $0.date < end && $0.date.addingTimeInterval($0.durationMin * 60) > start }
            .min { abs($0.date.timeIntervalSince(start)) < abs($1.date.timeIntervalSince(start)) }
    }

    private func average(_ id: HKQuantityTypeIdentifier, _ unit: HKUnit, in workout: HKWorkout) -> Double? {
        workout.statistics(for: HKQuantityType(id))?.averageQuantity()?.doubleValue(for: unit)
    }

    private func stepCount(during workout: HKWorkout) async -> Double? {
        let predicate = HKQuery.predicateForSamples(withStart: workout.startDate, end: workout.endDate)
        let descriptor = HKStatisticsQueryDescriptor(
            predicate: .quantitySample(type: HKQuantityType(.stepCount), predicate: predicate),
            options: .cumulativeSum
        )
        return try? await descriptor.result(for: store)?.sumQuantity()?.doubleValue(for: .count())
    }

    /// His own rating if he gave one, else the watch's estimate.
    private func effort(for workout: HKWorkout) async -> Double? {
        let window = HKQuery.predicateForSamples(withStart: workout.startDate, end: workout.endDate.addingTimeInterval(3600))
        for id in [HKQuantityTypeIdentifier.workoutEffortScore, .estimatedWorkoutEffortScore] {
            let descriptor = HKSampleQueryDescriptor(
                predicates: [.quantitySample(type: HKQuantityType(id), predicate: window)],
                sortDescriptors: [SortDescriptor(\.startDate, order: .reverse)],
                limit: 1
            )
            if let sample = try? await descriptor.result(for: store).first {
                return sample.quantity.doubleValue(for: .appleEffortScore())
            }
        }
        return nil
    }

    /// Per-kilometre times from the distance samples the watch recorded during the session.
    private func splits(for workout: HKWorkout) async -> [Double] {
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.quantitySample(type: HKQuantityType(.distanceWalkingRunning),
                                         predicate: HKQuery.predicateForObjects(from: workout))],
            sortDescriptors: [SortDescriptor(\.startDate)]
        )
        guard let samples = try? await descriptor.result(for: store) else { return [] }
        return Self.splits(from: samples.map {
            (start: $0.startDate, end: $0.endDate, meters: $0.quantity.doubleValue(for: .meter()))
        })
    }

    /// Seconds for each full kilometre, interpolating inside the sample that crosses each
    /// kilometre mark. Pure, so it's tested directly.
    static func splits(from samples: [(start: Date, end: Date, meters: Double)]) -> [Double] {
        guard let first = samples.first else { return [] }
        var result: [Double] = []
        var covered = 0.0
        var lastMark = first.start
        for sample in samples where sample.meters > 0 {
            var remaining = sample.meters
            var cursor = sample.start
            let secondsPerMeter = sample.end.timeIntervalSince(sample.start) / sample.meters
            while covered + remaining >= 1000 {
                let need = 1000 - covered
                let markTime = cursor.addingTimeInterval(need * secondsPerMeter)
                result.append(markTime.timeIntervalSince(lastMark))
                lastMark = markTime
                cursor = markTime
                remaining -= need
                covered = 0
            }
            covered += remaining
        }
        return result
    }

    static func isOnFoot(_ type: HKWorkoutActivityType) -> Bool {
        [.running, .walking, .hiking].contains(type)
    }

    static func typeName(_ type: HKWorkoutActivityType) -> String {
        switch type {
        case .running: "running"
        case .walking: "walking"
        case .hiking: "hiking"
        case .cycling: "cycling"
        case .swimming: "swimming"
        case .traditionalStrengthTraining: "weightlifting"
        case .functionalStrengthTraining: "functional fitness"
        case .highIntensityIntervalTraining: "hiit"
        case .cricket: "cricket"
        case .tennis, .racquetball, .squash, .pickleball, .badminton, .paddleSports: "racquet sport"
        case .yoga: "yoga"
        case .coreTraining: "core training"
        case .mixedCardio: "cardio"
        default: "activity"
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
