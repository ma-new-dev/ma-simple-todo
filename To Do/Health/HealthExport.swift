import Foundation
import SwiftData

/// Writes `health-export.json` into Compass's iCloud Documents folder after each sync, so
/// the Health Dashboard artifact can use what only the Apple Watch measures. The artifact
/// already gets WHOOP directly, so this carries the Apple Watch data and the runs: daily
/// Cardio Fitness, cardio recovery, daylight, weight, sleeping wrist temperature and
/// breathing, steps and exercise minutes, and every workout with GPS distance, pace and
/// splits (with WHOOP strain where the session was merged).
///
/// On the Mac a small launch agent copies the file into Google Drive, where the dashboard
/// refresh reads it (docs/health-export.md). Written on the iPhone only: that's where
/// HealthKit is.
enum HealthExport {
    nonisolated static let fileName = "health-export.json"
    static let days = 185

    struct File: Codable, Equatable {
        var generatedAt: String
        var source = "MA Compass (Apple Health on iPhone and Apple Watch Ultra)"
        var notes = "HRV, resting HR, recovery and sleep come from WHOOP and are not repeated here. Distances in km, pace in seconds per km, temperatures as deviation from the watch's baseline in °C."
        var days: [Day]
        var workouts: [Session]
    }

    struct Day: Codable, Equatable {
        var date: String
        var steps: Int?
        var activeEnergyKcal: Int?
        var exerciseMinutes: Int?
        var vo2Max: Double?
        var cardioRecoveryBpm: Double?
        var daylightMinutes: Int?
        var weightKg: Double?
        var bodyFatPct: Double?
        var wristTempDeltaC: Double?
        var breathingDisturbances: Double?
    }

    struct Session: Codable, Equatable {
        var start: String
        var type: String
        var durationMin: Double
        var distanceKm: Double?
        var paceSecPerKm: Double?
        var splitsSecPerKm: [Double]?
        var avgHR: Double?
        var maxHR: Double?
        var elevationGainM: Double?
        var avgPowerW: Double?
        var avgCadenceSpm: Double?
        var effortScore: Double?
        var whoopStrain: Double?
    }

    /// Builds the file from the store. Pure apart from the fetch, so tests feed it rows.
    static func make(metrics: [DailyMetric], workouts: [Workout], now: Date = .now) -> File {
        let dayFormat = Date.ISO8601FormatStyle().year().month().day()
        let round1 = { (v: Double?) in v.map { ($0 * 10).rounded() / 10 } }
        let rows: [Day] = metrics.sorted { $0.date < $1.date }.compactMap { m in
            let day = Day(
                date: m.date.formatted(dayFormat),
                steps: m.steps.map { Int($0.rounded()) },
                activeEnergyKcal: m.activeEnergyKcal.map { Int($0.rounded()) },
                exerciseMinutes: m.exerciseMinutes.map { Int($0.rounded()) },
                vo2Max: round1(m.vo2Max),
                cardioRecoveryBpm: round1(m.cardioRecoveryBpm),
                daylightMinutes: m.daylightMinutes.map { Int($0.rounded()) },
                weightKg: round1(m.weightKg),
                bodyFatPct: round1(m.bodyFatPct),
                wristTempDeltaC: m.wristTempDeltaC.map { ($0 * 100).rounded() / 100 },
                breathingDisturbances: round1(m.breathingDisturbances)
            )
            // Skip days with nothing from the watch.
            let empty = Day(date: day.date)
            return day == empty ? nil : day
        }
        let sessions: [Session] = workouts
            .filter { $0.healthKitID != nil || $0.source == "healthkit" }
            .sorted { $0.date < $1.date }
            .map { w in
                Session(
                    start: w.date.ISO8601Format(),
                    type: w.type,
                    durationMin: (w.durationMin * 10).rounded() / 10,
                    distanceKm: w.distanceKm.map { ($0 * 100).rounded() / 100 },
                    paceSecPerKm: w.avgPaceSecPerKm.map { $0.rounded() },
                    splitsSecPerKm: w.splitsSecPerKm.isEmpty ? nil : w.splitsSecPerKm.map { $0.rounded() },
                    avgHR: w.avgHR.map { $0.rounded() },
                    maxHR: w.maxHR.map { $0.rounded() },
                    elevationGainM: w.elevationGainM.map { $0.rounded() },
                    avgPowerW: w.avgPowerW.map { $0.rounded() },
                    avgCadenceSpm: w.avgCadenceSpm.map { $0.rounded() },
                    effortScore: w.effortScore,
                    whoopStrain: w.source == "whoop" ? round1(w.strain) : nil
                )
            }
        return File(generatedAt: now.ISO8601Format(), days: rows, workouts: sessions)
    }

    /// Fetches the last six months and writes the file into iCloud Documents.
    @MainActor
    static func write(from context: ModelContext) {
        guard AppleHealthService.shared.isAvailable else { return }
        let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: .now) ?? .now
        let metrics = (try? context.fetch(FetchDescriptor<DailyMetric>(predicate: #Predicate { $0.date >= cutoff }))) ?? []
        let workouts = (try? context.fetch(FetchDescriptor<Workout>(predicate: #Predicate { $0.date >= cutoff }))) ?? []
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(make(metrics: metrics, workouts: workouts)) else { return }

        Task.detached(priority: .utility) {
            guard let container = FileManager.default.url(forUbiquityContainerIdentifier: NetWorthStore.containerID) else { return }
            let file = container.appendingPathComponent("Documents/\(HealthExport.fileName)")
            var coordinationError: NSError?
            NSFileCoordinator().coordinate(writingItemAt: file, options: .forReplacing, error: &coordinationError) { url in
                try? data.write(to: url, options: .atomic)
            }
        }
    }
}
