import SwiftUI
import Charts

/// What the Apple Watch adds beyond WHOOP: Cardio Fitness, cardio recovery, daylight,
/// weight, and the night's wrist temperature and breathing. Hidden when there's nothing.
struct FitnessCard: View {
    let metrics: [DailyMetric]

    private var calendar: Calendar { .current }

    private func latest(_ key: KeyPath<DailyMetric, Double?>) -> (value: Double, date: Date)? {
        metrics.sorted { $0.date > $1.date }.lazy.compactMap { day in day[keyPath: key].map { ($0, day.date) } }.first
    }

    /// Mean over days `from` to `to` ago (today = 0, `to` exclusive).
    private func mean(_ key: KeyPath<DailyMetric, Double?>, _ from: Int, _ to: Int) -> Double? {
        let today = calendar.startOfDay(for: .now)
        guard let start = calendar.date(byAdding: .day, value: -to, to: today),
              let end = calendar.date(byAdding: .day, value: -from + 1, to: today) else { return nil }
        let values = metrics.filter { $0.date >= start && $0.date < end }.compactMap { $0[keyPath: key] }
        return values.isEmpty ? nil : values.reduce(0, +) / Double(values.count)
    }

    var body: some View {
        let vo2 = latest(\.vo2Max)
        let recovery = mean(\.cardioRecoveryBpm, 0, 30)
        let daylight = mean(\.daylightMinutes, 1, 8)
        let weight = latest(\.weightKg)
        let fat = latest(\.bodyFatPct)
        let wrist = latest(\.wristTempDeltaC)
        let breathing = latest(\.breathingDisturbances)
        if vo2 != nil || recovery != nil || daylight != nil || weight != nil {
            VStack(alignment: .leading, spacing: 14) {
                Label("Fitness", systemImage: "heart.circle").font(.headline)

                if let vo2 {
                    let months = HealthTrends(metrics: metrics).monthly(.vo2Max)
                    HStack(alignment: .bottom) {
                        figure("Cardio Fitness (VO2 max)", String(format: "%.1f", vo2.value),
                               caption: "measured \(vo2.date.formatted(.relative(presentation: .named)))")
                        Spacer()
                        if months.count >= 2 {
                            let floor = (months.map(\.value).min() ?? 0) - 1.5
                            Chart(months) { point in
                                // Bars rise from just under the lowest month, so they stay in the frame.
                                BarMark(x: .value("Month", point.month, unit: .month),
                                        yStart: .value("Base", floor), yEnd: .value("VO2 max", point.value))
                                    .foregroundStyle(Color.mint.opacity(point.isCurrent ? 0.45 : 0.9))
                                    .cornerRadius(2)
                            }
                            .chartXAxis(.hidden)
                            .chartYAxis(.hidden)
                            .chartYScale(domain: floor ... (months.map(\.value).max() ?? 1) + 0.5)
                            .frame(width: 120, height: 44)
                            .clipped()
                        }
                    }
                }

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 130), alignment: .leading)], alignment: .leading, spacing: 12) {
                    if let recovery {
                        let before = mean(\.cardioRecoveryBpm, 30, 60)
                        figure("Cardio recovery", "\(Int(recovery.rounded())) bpm",
                               caption: before.map { "30-day avg, was \(Int($0.rounded()))" } ?? "drop 1 min after a workout, 30-day avg")
                    }
                    if let daylight {
                        figure("Daylight", "\(Int(daylight.rounded())) min", caption: "a day, last 7 days",
                               tint: daylight < 20 ? .orange : .primary)
                    }
                    if let weight {
                        let monthAgo = mean(\.weightKg, 25, 35)
                        figure("Weight", String(format: "%.1f kg", weight.value),
                               caption: monthAgo.map { String(format: "%+.1f kg in a month", weight.value - $0) } ?? "latest")
                    }
                    if let fat { figure("Body fat", String(format: "%.1f%%", fat.value), caption: "latest") }
                }

                if let wrist, calendar.isDateInToday(wrist.date) || calendar.isDateInYesterday(wrist.date) {
                    HStack(spacing: 6) {
                        Image(systemName: "thermometer.medium").foregroundStyle(abs(wrist.value) >= 0.5 ? .orange : .secondary)
                        Text(String(format: "Wrist temperature %+.1f °C against your baseline", wrist.value)
                             + (breathing.map { String(format: " · breathing disturbances %.1f", $0.value) } ?? ""))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Text("From your Apple Watch. WHOOP stays the source for HRV, resting HR and sleep.")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .card()
        }
    }

    private func figure(_ title: String, _ value: String, caption: String, tint: Color = .primary) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title.uppercased()).font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
            Text(value).font(.title3.weight(.bold)).monospacedDigit().foregroundStyle(tint)
            Text(caption).font(.caption2).foregroundStyle(.secondary)
        }
    }
}

/// Runs the Apple Watch recorded with GPS: weekly distance, the latest runs, and splits.
struct RunningCard: View {
    let workouts: [Workout]
    @State private var selected: Workout?

    private var runs: [Workout] {
        workouts.filter { ($0.distanceKm ?? 0) > 0.5 && $0.type.lowercased().contains("run") }
            .sorted { $0.date > $1.date }
    }

    private struct WeekKm: Identifiable {
        var week: Date
        var km: Double
        var id: Date { week }
    }

    private var weekly: [WeekKm] {
        var iso = Calendar(identifier: .iso8601)
        iso.timeZone = .current
        guard let thisWeek = iso.dateInterval(of: .weekOfYear, for: .now)?.start else { return [] }
        return (0..<10).reversed().compactMap { back in
            guard let start = iso.date(byAdding: .weekOfYear, value: -back, to: thisWeek),
                  let end = iso.date(byAdding: .weekOfYear, value: 1, to: start) else { return nil }
            return WeekKm(week: start, km: runs.filter { $0.date >= start && $0.date < end }.compactMap(\.distanceKm).reduce(0, +))
        }
    }

    var body: some View {
        if !runs.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Label("Running", systemImage: "figure.run.circle").font(.headline)
                let weeks = weekly
                Chart(weeks) { week in
                    BarMark(x: .value("Week", week.week, unit: .weekOfYear), y: .value("km", week.km))
                        .foregroundStyle(week.week == weeks.last?.week ? Color.teal : Color.teal.opacity(0.45))
                        .cornerRadius(3)
                        .annotation(position: .top) {
                            if week.km > 0 { Text(String(format: "%.0f", week.km)).font(.caption2).foregroundStyle(.secondary) }
                        }
                }
                .chartYAxis(.hidden)
                .chartXAxis {
                    AxisMarks(values: .stride(by: .weekOfYear, count: 2)) { _ in
                        AxisValueLabel(format: .dateTime.day().month(.abbreviated))
                    }
                }
                .frame(height: 90)
                Text("Kilometres per week, last 10 weeks").font(.caption2).foregroundStyle(.secondary)

                ForEach(runs.prefix(5)) { run in
                    Button { selected = run } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(run.date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)))
                                    .font(.subheadline.weight(.medium))
                                Text([run.avgHR.map { "HR \(Int($0))" }, run.elevationGainM.map { "↑\(Int($0)) m" }]
                                        .compactMap { $0 }.joined(separator: " · "))
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 1) {
                                Text(String(format: "%.2f km", run.distanceKm ?? 0)).font(.subheadline.weight(.semibold).monospacedDigit())
                                Text(run.paceDisplay ?? "").font(.caption.monospacedDigit()).foregroundStyle(.teal)
                            }
                            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .card()
            .sheet(item: $selected) { run in
                RunDetail(run: run).presentationDetents([.medium, .large])
            }
        }
    }
}

private struct RunDetail: View {
    let run: Workout
    @Environment(\.dismiss) private var dismiss

    private struct Split: Identifiable {
        var km: Int
        var seconds: Double
        var id: Int { km }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    row("Distance", String(format: "%.2f km", run.distanceKm ?? 0))
                    row("Time", Duration.seconds(run.durationMin * 60).formatted(.time(pattern: .hourMinuteSecond)))
                    if let pace = run.paceDisplay { row("Average pace", pace) }
                    if let hr = run.avgHR { row("Average heart rate", "\(Int(hr)) bpm") }
                    if let elevation = run.elevationGainM { row("Elevation gain", "\(Int(elevation)) m") }
                    if let power = run.avgPowerW { row("Running power", "\(Int(power)) W") }
                    if let cadence = run.avgCadenceSpm { row("Cadence", "\(Int(cadence)) spm") }
                    if let effort = run.effortScore { row("Effort", String(format: "%.0f / 10", effort)) }
                    if let strain = run.strain { row("WHOOP strain", String(format: "%.1f", strain)) }
                }
                if !run.splitsSecPerKm.isEmpty {
                    Section("Splits") {
                        let splits = run.splitsSecPerKm.enumerated().map { Split(km: $0.offset + 1, seconds: $0.element) }
                        let fastest = splits.map(\.seconds).min() ?? 0
                        Chart(splits) { split in
                            BarMark(x: .value("Pace", split.seconds), y: .value("km", "\(split.km)"))
                                .foregroundStyle(split.seconds == fastest ? Color.teal : Color.teal.opacity(0.5))
                                .annotation(position: .trailing) {
                                    Text(Self.pace(split.seconds)).font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                                }
                        }
                        .chartXAxis(.hidden)
                        .chartXScale(domain: (fastest * 0.85)...((splits.map(\.seconds).max() ?? 1) * 1.08))
                        .frame(height: CGFloat(splits.count) * 24 + 10)
                    }
                }
            }
            .navigationTitle("\(run.type.capitalized), \(run.date.formatted(.dateTime.weekday(.wide).day().month()))")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }

    static func pace(_ seconds: Double) -> String {
        String(format: "%d:%02d/km", Int(seconds) / 60, Int(seconds) % 60)
    }

    private func row(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title).foregroundStyle(.secondary)
            Spacer()
            Text(value).monospacedDigit()
        }
    }
}
