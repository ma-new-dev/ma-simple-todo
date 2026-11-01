import Foundation
import SwiftData

@Model
final class Workout {
    var date: Date = Date.distantPast
    /// Whoop's workout UUID, or the HealthKit UUID. Used to avoid duplicate inserts.
    var externalID: String = ""
    var type: String = ""
    var durationMin: Double = 0
    var distanceKm: Double?
    var avgHR: Double?
    var maxHR: Double?
    var strain: Double?
    /// Minutes in each of Whoop's five HR zones, ascending. Empty when unknown.
    var zoneMinutes: [Double] = []
    /// "whoop" | "healthkit". A WHOOP session the watch also recorded stays "whoop" and
    /// gains the watch's distance, pace and splits.
    var source: String = ""
    var notes: String = ""

    // MARK: From the Apple Watch, when it recorded the same session (3.0 build 22)

    /// The HealthKit workout merged into this one, so it isn't imported twice.
    var healthKitID: String?
    var elevationGainM: Double?
    var avgPowerW: Double?
    var avgCadenceSpm: Double?
    /// Apple's 1-10 effort rating (the user's own, else the watch's estimate).
    var effortScore: Double?
    /// Seconds per kilometre for each full kilometre, in order.
    var splitsSecPerKm: [Double] = []

    init(date: Date, externalID: String, type: String, durationMin: Double, source: String) {
        self.date = date
        self.externalID = externalID
        self.type = type
        self.durationMin = durationMin
        self.source = source
    }
}

extension Workout {
    /// Average pace in seconds per kilometre, when there is a distance to derive it from.
    ///
    /// This is an average across the whole session, not per-split pace.
    var avgPaceSecPerKm: Double? {
        guard let distanceKm, distanceKm > 0.1 else { return nil }
        return (durationMin * 60) / distanceKm
    }

    var paceDisplay: String? {
        guard let pace = avgPaceSecPerKm else { return nil }
        let minutes = Int(pace) / 60
        let seconds = Int(pace) % 60
        return String(format: "%d:%02d/km", minutes, seconds)
    }
}
