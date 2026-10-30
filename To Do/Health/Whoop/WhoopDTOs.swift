import Foundation

// Wire types for the WHOOP v2 API. Every score block is optional because a record
// can exist with `score_state` of PENDING_SCORE or UNSCORABLE and no score at all.

nonisolated struct WhoopPage<Record: Decodable>: Decodable {
    let records: [Record]
    let nextToken: String?

    enum CodingKeys: String, CodingKey {
        case records
        case nextToken = "next_token"
    }
}

// MARK: - Recovery

nonisolated struct WhoopRecovery: Decodable {
    let createdAt: Date
    let scoreState: String?
    let score: Score?

    struct Score: Decodable {
        let recoveryScore: Double?
        let restingHeartRate: Double?
        let hrvRmssdMilli: Double?
        let spo2Percentage: Double?
        let skinTempCelsius: Double?

        enum CodingKeys: String, CodingKey {
            case recoveryScore = "recovery_score"
            case restingHeartRate = "resting_heart_rate"
            case hrvRmssdMilli = "hrv_rmssd_milli"
            case spo2Percentage = "spo2_percentage"
            case skinTempCelsius = "skin_temp_celsius"
        }
    }

    enum CodingKeys: String, CodingKey {
        case createdAt = "created_at"
        case scoreState = "score_state"
        case score
    }
}

// MARK: - Sleep

nonisolated struct WhoopSleep: Decodable {
    let start: Date
    let end: Date
    let nap: Bool?
    let score: Score?

    struct Score: Decodable {
        let stageSummary: StageSummary?
        let respiratoryRate: Double?
        let sleepPerformancePercentage: Double?
        let sleepConsistencyPercentage: Double?
        let sleepEfficiencyPercentage: Double?

        struct StageSummary: Decodable {
            let totalInBedTimeMilli: Double?
            let totalAwakeTimeMilli: Double?
            let totalLightSleepTimeMilli: Double?
            let totalSlowWaveSleepTimeMilli: Double?
            let totalRemSleepTimeMilli: Double?
            let disturbanceCount: Int?

            enum CodingKeys: String, CodingKey {
                case totalInBedTimeMilli = "total_in_bed_time_milli"
                case totalAwakeTimeMilli = "total_awake_time_milli"
                case totalLightSleepTimeMilli = "total_light_sleep_time_milli"
                case totalSlowWaveSleepTimeMilli = "total_slow_wave_sleep_time_milli"
                case totalRemSleepTimeMilli = "total_rem_sleep_time_milli"
                case disturbanceCount = "disturbance_count"
            }
        }

        enum CodingKeys: String, CodingKey {
            case stageSummary = "stage_summary"
            case respiratoryRate = "respiratory_rate"
            case sleepPerformancePercentage = "sleep_performance_percentage"
            case sleepConsistencyPercentage = "sleep_consistency_percentage"
            case sleepEfficiencyPercentage = "sleep_efficiency_percentage"
        }
    }

    enum CodingKeys: String, CodingKey {
        case start, end, nap, score
    }
}

extension WhoopSleep.Score.StageSummary {
    /// Asleep time in hours — in-bed minus awake, which is what Whoop shows as "hours of sleep".
    var asleepHours: Double? {
        guard let inBed = totalInBedTimeMilli else { return nil }
        let awake = totalAwakeTimeMilli ?? 0
        return (inBed - awake) / 3_600_000
    }

    var asleepMilli: Double? {
        guard let inBed = totalInBedTimeMilli else { return nil }
        return inBed - (totalAwakeTimeMilli ?? 0)
    }
}

// MARK: - Cycle

nonisolated struct WhoopCycle: Decodable {
    let start: Date
    let end: Date?
    let score: Score?

    struct Score: Decodable {
        let strain: Double?
        let kilojoule: Double?
        let averageHeartRate: Double?
        let maxHeartRate: Double?

        enum CodingKeys: String, CodingKey {
            case strain, kilojoule
            case averageHeartRate = "average_heart_rate"
            case maxHeartRate = "max_heart_rate"
        }
    }
}

// MARK: - Workout

nonisolated struct WhoopWorkout: Decodable {
    let id: String
    let start: Date
    let end: Date
    let sportName: String?
    let score: Score?

    struct Score: Decodable {
        let strain: Double?
        let averageHeartRate: Double?
        let maxHeartRate: Double?
        let distanceMeter: Double?
        let zoneDurations: ZoneDurations?

        struct ZoneDurations: Decodable {
            let zoneZeroMilli: Double?
            let zoneOneMilli: Double?
            let zoneTwoMilli: Double?
            let zoneThreeMilli: Double?
            let zoneFourMilli: Double?
            let zoneFiveMilli: Double?

            enum CodingKeys: String, CodingKey {
                case zoneZeroMilli = "zone_zero_milli"
                case zoneOneMilli = "zone_one_milli"
                case zoneTwoMilli = "zone_two_milli"
                case zoneThreeMilli = "zone_three_milli"
                case zoneFourMilli = "zone_four_milli"
                case zoneFiveMilli = "zone_five_milli"
            }

            var minutesAscending: [Double] {
                [zoneZeroMilli, zoneOneMilli, zoneTwoMilli, zoneThreeMilli, zoneFourMilli, zoneFiveMilli]
                    .map { ($0 ?? 0) / 60_000 }
            }
        }

        enum CodingKeys: String, CodingKey {
            case strain
            case averageHeartRate = "average_heart_rate"
            case maxHeartRate = "max_heart_rate"
            case distanceMeter = "distance_meter"
            case zoneDurations = "zone_durations"
        }
    }

    enum CodingKeys: String, CodingKey {
        case id, start, end, score
        case sportName = "sport_name"
    }
}

// MARK: - Body measurement

nonisolated struct WhoopBodyMeasurement: Decodable {
    let heightMeter: Double?
    let weightKilogram: Double?
    let maxHeartRate: Double?

    enum CodingKeys: String, CodingKey {
        case heightMeter = "height_meter"
        case weightKilogram = "weight_kilogram"
        case maxHeartRate = "max_heart_rate"
    }
}

// MARK: - Token response

nonisolated struct WhoopTokenResponse: Decodable {
    let accessToken: String
    let refreshToken: String?
    let expiresIn: Double
    let scope: String?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresIn = "expires_in"
        case scope
    }
}
