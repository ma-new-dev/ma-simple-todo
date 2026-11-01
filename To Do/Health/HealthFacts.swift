import Foundation

/// The morning brief's substance, worked out in code from WHOOP and Apple Health data:
/// the same comparisons the Health Dashboard artifact makes (latest against the 7- and
/// 30-day averages, the last 30 days against the 30 before, sleep against need, training
/// load, threshold minutes, the week's rhythm). Every number in the brief comes from
/// here. The on-device model only rewords; when it can't run, these lines are shown as
/// they are.
struct HealthFacts: Equatable {
    var headline: String
    var goingWell: [String]
    var watch: [String]
    var workOn: [String]

    /// Recovery zones, as WHOOP colours them.
    static let green = 67.0
    static let red = 33.0
    /// A day counts as a load day at this strain or above.
    static let loadDayStrain = 10.0
    static let sleepTargetHours = 7.5

    init(metrics: [DailyMetric], workouts: [Workout], now: Date = .now, calendar: Calendar = .current) {
        let today = calendar.startOfDay(for: now)
        let days = metrics.sorted { $0.date < $1.date }
        let byDay = Dictionary(days.map { (calendar.startOfDay(for: $0.date), $0) }, uniquingKeysWith: { a, _ in a })

        func window(_ from: Int, _ to: Int) -> [DailyMetric] {
            // Days `from` to `to` ago, `to` exclusive (window(1, 8) is the 7 days before today).
            (from..<to).compactMap { offset in
                calendar.date(byAdding: .day, value: -offset, to: today).flatMap { byDay[$0] }
            }
        }
        func mean(_ values: [Double]) -> Double? {
            values.isEmpty ? nil : values.reduce(0, +) / Double(values.count)
        }
        func avg(_ key: KeyPath<DailyMetric, Double?>, _ from: Int, _ to: Int, minimum: Int = 3) -> Double? {
            let values = window(from, to).compactMap { $0[keyPath: key] }
            return values.count >= minimum ? mean(values) : nil
        }

        // The latest morning with a recovery score, and the one before it.
        let scored = days.filter { $0.recovery != nil }
        let latest = scored.last
        let previous = scored.dropLast().last
        let latestIsToday = latest.map { calendar.isDate($0.date, inSameDayAs: today) } ?? false

        var well: [String] = []
        var watch: [String] = []
        var work: [String] = []

        // MARK: Recovery, HRV, resting HR

        var headlineParts: [String] = []
        if let latest, let recovery = latest.recovery {
            var part = "Recovery \(Self.int(recovery))"
            if let before = previous?.recovery { part += " (from \(Self.int(before)))" }
            headlineParts.append(part)
            if !latestIsToday { watch.append("No WHOOP recovery for today yet; these figures are from \(latest.date.formatted(.dateTime.weekday(.wide))).") }

            if recovery >= Self.green {
                well.append("Recovery \(Self.int(recovery)) is in the green.")
            } else if recovery <= Self.red {
                watch.append("Recovery \(Self.int(recovery)) is in the red.")
            }
            if let before = previous?.recovery, recovery - before >= 15 {
                well.append("Recovery jumped \(Self.int(recovery - before)) points, from \(Self.int(before)) to \(Self.int(recovery)).")
            } else if let before = previous?.recovery, before - recovery >= 15 {
                watch.append("Recovery fell \(Self.int(before - recovery)) points, from \(Self.int(before)) to \(Self.int(recovery)).")
            }
        }
        if let hrv = latest?.hrv {
            headlineParts.append("HRV \(Self.one(hrv)) ms")
            if let base = avg(\.hrv, 1, 31) {
                let change = (hrv - base) / base * 100
                if change >= 5 { well.append("HRV \(Self.one(hrv)) ms is \(Self.int(change))% above its 30-day average of \(Self.one(base)) ms.") }
                if change <= -10 { watch.append("HRV \(Self.one(hrv)) ms is \(Self.int(-change))% below its 30-day average of \(Self.one(base)) ms.") }
            }
        }
        if let rhr = latest?.restingHR {
            headlineParts.append("resting HR \(Self.int(rhr))")
            if let base = avg(\.restingHR, 1, 31) {
                if rhr <= base - 2 { well.append("Resting HR \(Self.int(rhr)) is below its 30-day average of \(Self.one(base)).") }
                if rhr >= base + 3 { watch.append("Resting HR \(Self.int(rhr)) is up on its 30-day average of \(Self.one(base)).") }
            }
        }

        // The last 30 days against the 30 before: the dashboard's month-on-month view.
        for (label, key, unit, higherIsBetter) in [
            ("recovery", \DailyMetric.recovery, "", true),
            ("HRV", \DailyMetric.hrv, " ms", true),
            ("resting HR", \DailyMetric.restingHR, "", false),
        ] as [(String, KeyPath<DailyMetric, Double?>, String, Bool)] {
            guard let recent = avg(key, 0, 30, minimum: 15), let earlier = avg(key, 30, 60, minimum: 15) else { continue }
            let delta = recent - earlier
            let threshold = label == "resting HR" ? 1.0 : (label == "HRV" ? 2.0 : 4.0)
            guard abs(delta) >= threshold else { continue }
            let line = "30-day average \(label) \(Self.one(recent))\(unit), against \(Self.one(earlier))\(unit) the 30 days before."
            if (delta > 0) == higherIsBetter { well.append(line) } else { watch.append(line) }
        }

        // Illness pattern: SpO2 down or skin temperature up against baseline.
        if let temp = latest?.skinTempC, let base = avg(\.skinTempC, 1, 31), temp - base >= 0.5 {
            watch.append("Skin temp \(Self.one(temp)) °C is \(Self.one(temp - base)) above its 30-day baseline; if it persists with low HRV, raise it with Dr. Molly.")
        }
        if let spo2 = latest?.spo2, let base = avg(\.spo2, 1, 31), base - spo2 >= 1.5 {
            watch.append("Blood oxygen \(Self.one(spo2))% is below its 30-day average of \(Self.one(base))%.")
        }

        // MARK: Sleep

        var sleepShort = false
        if let slept = latest?.sleepHours {
            headlineParts.append("\(Self.one(slept)) h sleep")
            if let need = latest?.sleepNeedHours, need > 0 {
                let gap = need - slept
                if gap <= 0 {
                    well.append("Slept \(Self.one(slept)) h, meeting WHOOP's \(Self.one(need)) h need.")
                } else if gap >= 0.5 {
                    sleepShort = true
                    watch.append("Slept \(Self.one(slept)) h against a \(Self.one(need)) h need, \(Self.one(gap)) h short.")
                }
            } else if slept < Self.sleepTargetHours - 0.3 {
                sleepShort = true
                watch.append("Slept \(Self.one(slept)) h, under the \(Self.one(Self.sleepTargetHours)) h target.")
            } else if slept >= Self.sleepTargetHours {
                well.append("Slept \(Self.one(slept)) h, at or above the \(Self.one(Self.sleepTargetHours)) h target.")
            }
            if let debt = latest?.sleepDebtHours, debt * 60 >= 45 {
                sleepShort = true
                watch.append("Sleep debt is \(Self.int(debt * 60)) min.")
            }
        }
        let lastWeek = window(0, 7)
        let shortNights = lastWeek.filter { day in
            guard let slept = day.sleepHours else { return false }
            return slept < (day.sleepNeedHours ?? Self.sleepTargetHours) - 0.25
        }.count
        if lastWeek.count >= 5, shortNights >= 4 {
            sleepShort = true
            watch.append("\(shortNights) of the last \(lastWeek.count) nights came in short of need.")
        }

        // MARK: Apple Watch fitness

        // Cardio Fitness and cardio recovery move slowly, so compare 30-day windows.
        for (label, key, unit, threshold) in [
            ("Cardio Fitness (VO2 max)", \DailyMetric.vo2Max, "", 0.5),
            ("cardio recovery", \DailyMetric.cardioRecoveryBpm, " bpm", 2.0),
        ] as [(String, KeyPath<DailyMetric, Double?>, String, Double)] {
            guard let recent = avg(key, 0, 30, minimum: 2), let earlier = avg(key, 30, 60, minimum: 2),
                  abs(recent - earlier) >= threshold else { continue }
            let line = "30-day average \(label) \(Self.one(recent))\(unit), against \(Self.one(earlier))\(unit) the 30 days before."
            if recent > earlier { well.append(line) } else { watch.append(line) }
        }
        if let daylight = avg(\.daylightMinutes, 1, 8, minimum: 4), daylight < 20 {
            watch.append("Time in daylight averaged \(Self.int(daylight)) min a day this week.")
        }
        if let weight = days.last(where: { $0.weightKg != nil })?.weightKg, weight > 67 || weight < 64.5 {
            watch.append("Weight \(Self.one(weight)) kg, outside the 65 to 66.5 kg range.")
        }

        // MARK: Training load

        let loadRatio: Double? = {
            guard let acute = avg(\.dayStrain, 1, 8, minimum: 5), let chronic = avg(\.dayStrain, 1, 29, minimum: 14), chronic > 0 else { return nil }
            return acute / chronic
        }()
        if let ratio = loadRatio, let acute = avg(\.dayStrain, 1, 8, minimum: 5), let chronic = avg(\.dayStrain, 1, 29, minimum: 14) {
            let detail = "the last 7 days averaged strain \(Self.one(acute)) against \(Self.one(chronic)) over 28"
            if ratio > 1.3 {
                watch.append("Load ratio \(Self.two(ratio)), building fast: \(detail).")
            } else if ratio < 0.8 {
                watch.append("Load ratio \(Self.two(ratio)), well under usual: \(detail).")
            } else {
                well.append("Load ratio \(Self.two(ratio)), steady: \(detail).")
            }
        }

        var loadStreak = 0
        for offset in 1...7 {
            guard let day = calendar.date(byAdding: .day, value: -offset, to: today).flatMap({ byDay[$0] }),
                  let strain = day.dayStrain, strain >= Self.loadDayStrain else { break }
            loadStreak += 1
        }
        let recovery = latest?.recovery
        if loadStreak >= 2, let recovery, recovery < Self.green {
            watch.append("\(loadStreak) load days in a row going into a \(Self.zone(recovery)) recovery of \(Self.int(recovery)).")
        }

        // Threshold work: minutes in WHOOP zones 4 and 5.
        func thresholdMinutes(_ from: Int, _ to: Int) -> Double {
            guard let start = calendar.date(byAdding: .day, value: -to, to: today),
                  let end = calendar.date(byAdding: .day, value: -from + 1, to: today) else { return 0 }
            return workouts
                .filter { $0.date >= start && $0.date < end && $0.zoneMinutes.count >= 6 }
                .reduce(0) { $0 + $1.zoneMinutes[4] + $1.zoneMinutes[5] }
        }
        let hasZones = workouts.contains { $0.zoneMinutes.count >= 6 }
        let threshold30 = thresholdMinutes(0, 30)
        let threshold60 = thresholdMinutes(30, 60)
        if hasZones {
            if threshold30 < 10 {
                watch.append("Only \(Self.one(threshold30)) min at zone 4 or above in 30 days, against \(Self.one(threshold60)) the 30 before.")
            } else if threshold30 >= 20 {
                well.append("\(Self.int(threshold30)) min at zone 4 or above in 30 days.")
            }
        }

        // MARK: The week's rhythm (3 gym, 1 zone-2 run, padel Saturday, cricket Sunday)

        let week = Self.weekInterval(containing: now)
        let thisWeek = workouts.filter { week.contains($0.date) }
        let gym = thisWeek.filter { Self.isGym($0.type) }.count
        let runs = thisWeek.filter { $0.type.lowercased().contains("run") }.count
        let weekday = (calendar.component(.weekday, from: now) + 5) % 7 + 1 // Monday = 1
        if !thisWeek.isEmpty {
            var summary = "This week so far: \(gym) gym, \(runs) run\(runs == 1 ? "" : "s")."
            if let run = thisWeek.filter({ $0.type.lowercased().contains("run") && ($0.distanceKm ?? 0) > 0.5 }).max(by: { $0.date < $1.date }),
               let km = run.distanceKm, let pace = run.paceDisplay {
                summary += " Latest run \(Self.one(km)) km at \(pace)" + (run.avgHR.map { ", average HR \(Self.int($0))." } ?? ".")
            }
            if weekday >= 5, gym < 2 || runs == 0 {
                watch.append(summary + (runs == 0 ? " The zone-2 run is still to do." : " Gym days are behind the plan of three."))
            } else if gym >= 2 || runs >= 1 {
                well.append(summary)
            }
        }

        // MARK: Work on — execution only, inside the clinical team's protocol

        let session: String = {
            switch weekday {
            case 6: return "padel"
            case 7: return "cricket"
            default:
                if runs == 0, weekday >= 3 { return "the zone-2 run" }
                return gym < 3 ? "the gym session" : "an easy day"
            }
        }()
        if let recovery {
            if recovery <= Self.red || (loadStreak >= 3 && recovery < Self.green) {
                work.append("Rest today, or a 30-min easy walk; move \(session) to a greener day.")
            } else if recovery < Self.green {
                work.append("Do \(session) at moderate effort, with no add-ons.")
            } else {
                work.append("Green light for \(session) as planned.")
                if hasZones, threshold30 < 10, session != "an easy day" {
                    work.append("Add 5 to 10 min at zone 4 (142+ bpm) within today's session.")
                }
            }
        }
        if sleepShort {
            work.append("Dinner by 19:30 and lights out by 22:15 tonight to pay down the sleep gap.")
        } else {
            work.append("Lights out by 22:30 to keep sleep on target.")
        }

        headline = headlineParts.isEmpty
            ? "No WHOOP data yet; pull down to sync."
            : headlineParts.joined(separator: ", ") + "."
        goingWell = Array(well.prefix(4))
        self.watch = Array(watch.prefix(4))
        workOn = Array(work.prefix(3))
    }

    init(headline: String, goingWell: [String], watch: [String], workOn: [String]) {
        self.headline = headline
        self.goingWell = goingWell
        self.watch = watch
        self.workOn = workOn
    }

    /// Everything as one block, for the on-device model.
    var asPromptText: String {
        """
        HEADLINE FACTS: \(headline)
        GOING WELL:
        \(goingWell.map { "- \($0)" }.joined(separator: "\n"))
        WATCH:
        \(watch.map { "- \($0)" }.joined(separator: "\n"))
        WORK ON:
        \(workOn.map { "- \($0)" }.joined(separator: "\n"))
        """
    }

    // MARK: - Helpers

    static func isGym(_ type: String) -> Bool {
        let t = type.lowercased()
        return ["weight", "strength", "functional", "gym", "powerlifting", "crossfit"].contains { t.contains($0) }
    }

    static func zone(_ recovery: Double) -> String {
        recovery >= green ? "green" : (recovery <= red ? "red" : "yellow")
    }

    static func weekInterval(containing date: Date) -> DateInterval {
        var calendar = Calendar(identifier: .iso8601)
        calendar.timeZone = .current
        return calendar.dateInterval(of: .weekOfYear, for: date) ?? DateInterval(start: date, duration: 7 * 86_400)
    }

    static func int(_ value: Double) -> String { String(Int(value.rounded())) }
    static func one(_ value: Double) -> String { String(format: "%.1f", value) }
    static func two(_ value: Double) -> String { String(format: "%.2f", value) }

    /// Every number written in `text`, for checking the model didn't invent one.
    static func numbers(in text: String) -> Set<String> {
        let pattern = /\d+(?:\.\d+)?/
        return Set(text.matches(of: pattern).map { match in
            let raw = String(match.output)
            // "51.0" and "51" are the same claim.
            if let value = Double(raw), value == value.rounded() { return String(Int(value)) }
            return raw
        })
    }
}
