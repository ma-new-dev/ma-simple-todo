import Foundation
import SwiftUI

/// The metrics the Health tab trends, with how to read and judge each.
enum HealthMetric: String, CaseIterable, Identifiable {
    case recovery, hrv, restingHR, sleep, strain

    var id: String { rawValue }

    var title: String {
        switch self {
        case .recovery:  "Recovery"
        case .hrv:       "HRV"
        case .restingHR: "Resting HR"
        case .sleep:     "Sleep"
        case .strain:    "Strain"
        }
    }

    var shortTitle: String {
        switch self {
        case .restingHR: "RHR"
        default: title
        }
    }

    var unit: String {
        switch self {
        case .recovery:  "%"
        case .hrv:       "ms"
        case .restingHR: "bpm"
        case .sleep:     "h"
        case .strain:    ""
        }
    }

    var decimals: Int {
        switch self {
        case .sleep, .strain, .hrv: 1
        default: 0
        }
    }

    /// nil when neither direction is better (strain).
    var higherIsBetter: Bool? {
        switch self {
        case .restingHR: false
        case .strain: nil
        default: true
        }
    }

    var color: Color {
        switch self {
        case .recovery:  .green
        case .hrv:       .cyan
        case .restingHR: .pink
        case .sleep:     .indigo
        case .strain:    .orange
        }
    }

    func value(_ day: DailyMetric) -> Double? {
        switch self {
        case .recovery:  day.recovery
        case .hrv:       day.hrv
        case .restingHR: day.restingHR
        case .sleep:     day.sleepHours
        case .strain:    day.dayStrain
        }
    }

    /// Today's strain is a cycle still accruing, so "latest" strain is yesterday's.
    var latestSkipsToday: Bool { self == .strain }

    func format(_ value: Double?) -> String {
        guard let value else { return "–" }
        return String(format: "%.\(decimals)f", value)
    }
}

/// Averages and series for the trend charts and the key-metrics table. Pure, so tests
/// can feed it made-up days.
struct HealthTrends {
    struct MonthPoint: Identifiable, Equatable {
        var month: Date
        var value: Double
        var days: Int
        var isCurrent: Bool
        var id: Date { month }
    }

    struct DayPoint: Identifiable, Equatable {
        var date: Date
        var value: Double
        var id: Date { date }
    }

    let metrics: [DailyMetric]
    var now: Date = .now
    var calendar: Calendar = .current

    private var today: Date { calendar.startOfDay(for: now) }

    /// The value for the latest day that has one (yesterday's for strain).
    func latest(_ metric: HealthMetric) -> Double? {
        metrics
            .filter { !(metric.latestSkipsToday && calendar.isDate($0.date, inSameDayAs: today)) }
            .sorted { $0.date > $1.date }
            .lazy.compactMap { metric.value($0) }.first
    }

    /// Mean over the `days` before today (today excluded, as the dashboard does).
    func average(_ metric: HealthMetric, days: Int) -> Double? {
        guard let start = calendar.date(byAdding: .day, value: -days, to: today) else { return nil }
        let values = metrics.filter { $0.date >= start && $0.date < today }.compactMap { metric.value($0) }
        return values.isEmpty ? nil : values.reduce(0, +) / Double(values.count)
    }

    /// One point per calendar month for the last `months` months, oldest first. The
    /// current month is included and marked, since it is still filling in.
    func monthly(_ metric: HealthMetric, months: Int = 6) -> [MonthPoint] {
        guard let thisMonth = calendar.dateInterval(of: .month, for: now)?.start else { return [] }
        return (0..<months).reversed().compactMap { back in
            guard let start = calendar.date(byAdding: .month, value: -back, to: thisMonth),
                  let end = calendar.date(byAdding: .month, value: 1, to: start) else { return nil }
            let values = metrics.filter { $0.date >= start && $0.date < end }.compactMap { metric.value($0) }
            guard !values.isEmpty else { return nil }
            return MonthPoint(month: start, value: values.reduce(0, +) / Double(values.count),
                              days: values.count, isCurrent: back == 0)
        }
    }

    /// Daily values for the last `days` days, oldest first.
    func daily(_ metric: HealthMetric, days: Int = 30) -> [DayPoint] {
        guard let start = calendar.date(byAdding: .day, value: -(days - 1), to: today) else { return [] }
        return metrics
            .filter { $0.date >= start }
            .filter { !(metric.latestSkipsToday && calendar.isDate($0.date, inSameDayAs: today)) }
            .compactMap { day in metric.value(day).map { DayPoint(date: calendar.startOfDay(for: day.date), value: $0) } }
            .sorted { $0.date < $1.date }
    }

    /// One sentence on the six-month picture: the last full month against the one before,
    /// and whether it is the best or worst of the run.
    func monthlyInsight(_ metric: HealthMetric) -> String? {
        let full = monthly(metric).filter { !$0.isCurrent && $0.days >= 10 }
        guard full.count >= 2, let last = full.last else { return nil }
        let previous = full[full.count - 2]
        let name = last.month.formatted(.dateTime.month(.wide))
        let previousName = previous.month.formatted(.dateTime.month(.wide))
        var sentence = "\(name) averaged \(metric.format(last.value))\(metric.unit == "%" ? "" : " " + metric.unit)"
            .trimmingCharacters(in: .whitespaces)
        sentence += " against \(metric.format(previous.value)) in \(previousName)"
        if let better = metric.higherIsBetter, full.count >= 3 {
            let values = full.map(\.value)
            let best = better ? values.max() : values.min()
            let worst = better ? values.min() : values.max()
            if last.value == best { sentence += ", the best of the last \(full.count) months" }
            else if last.value == worst { sentence += ", the weakest of the last \(full.count) months" }
        }
        return sentence + "."
    }

    // MARK: - Training

    /// Total strain per ISO week for the last `weeks` weeks, oldest first.
    func weeklyStrain(weeks: Int = 10) -> [DayPoint] {
        var iso = Calendar(identifier: .iso8601)
        iso.timeZone = calendar.timeZone
        guard let thisWeek = iso.dateInterval(of: .weekOfYear, for: now)?.start else { return [] }
        return (0..<weeks).reversed().compactMap { back in
            guard let start = iso.date(byAdding: .weekOfYear, value: -back, to: thisWeek),
                  let end = iso.date(byAdding: .weekOfYear, value: 1, to: start) else { return nil }
            let total = metrics.filter { $0.date >= start && $0.date < end }.compactMap(\.dayStrain).reduce(0, +)
            return DayPoint(date: start, value: total)
        }
    }

    /// Acute (7-day) over chronic (28-day) average daily strain, before today.
    var loadRatio: Double? {
        guard let acute = average(.strain, days: 7), let chronic = average(.strain, days: 28), chronic > 0 else { return nil }
        return acute / chronic
    }
}
