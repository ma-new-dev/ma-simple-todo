import SwiftUI
import SwiftData
import Charts

/// The morning read, modelled on the Health Dashboard artifact: today's recovery and the
/// brief first, then six-month trends, the key metrics against their 7-day, 30-day and
/// six-month averages, last night's sleep against need, training load, and what the Apple
/// Watch adds (Cardio Fitness, cardio recovery, daylight, weight, GPS runs).
struct HealthTabView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Query(sort: \DailyMetric.date, order: .reverse) private var metrics: [DailyMetric]
    @Query(sort: \HealthBrief.createdAt, order: .reverse) private var briefs: [HealthBrief]
    @Query(sort: \Workout.date, order: .reverse) private var workouts: [Workout]

    @State private var whoop = WhoopSyncService.shared
    @State private var briefService = HealthBriefService.shared
    @State private var showSettings = false
    @State private var trendMetric: HealthMetric = .recovery
    @State private var trendRange: TrendRange = .sixMonths

    enum TrendRange: String, CaseIterable, Identifiable {
        case thirtyDays = "30 days", sixMonths = "6 months"
        var id: String { rawValue }
    }

    private var calendar: Calendar { .current }
    private var today: DailyMetric? { metrics.first { calendar.isDateInToday($0.date) } }
    private var yesterday: DailyMetric? { metrics.first { calendar.isDateInYesterday($0.date) } }
    /// Today's row, or the latest with a recovery score when WHOOP hasn't posted today's yet.
    private var latestNight: DailyMetric? { today?.recovery != nil ? today : metrics.first { $0.recovery != nil } }
    private var todaysBrief: HealthBrief? { briefs.first { calendar.isDateInToday($0.date) } }
    private var trends: HealthTrends { HealthTrends(metrics: metrics) }

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
            ScrollView {
                Group {
                    if !WhoopTokenStore.shared.isConnected && metrics.isEmpty {
                        notConnected
                    } else if sizeClass == .regular {
                        VStack(spacing: 16) {
                            HStack(alignment: .top, spacing: 16) {
                                VStack(spacing: 16) { hero; briefSection }
                                VStack(spacing: 16) { trendCard; keyMetrics }
                            }
                            HStack(alignment: .top, spacing: 16) {
                                sleepCard
                                trainingCard
                            }
                            HStack(alignment: .top, spacing: 16) {
                                FitnessCard(metrics: metrics)
                                RunningCard(workouts: workouts)
                            }
                            .id("fitness")
                            footer
                        }
                    } else {
                        VStack(spacing: 16) {
                            hero
                            briefSection
                            trendCard
                            keyMetrics
                            sleepCard
                            trainingCard
                            FitnessCard(metrics: metrics).id("fitness")
                            RunningCard(workouts: workouts)
                            footer
                        }
                    }
                }
                .padding()
                .frame(maxWidth: 1100)
                .frame(maxWidth: .infinity)
            }
            .onAppear {
                // Screenshot mode only: jump to the Apple Watch cards further down.
                if ProcessInfo.processInfo.arguments.contains("health_fitness") {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { proxy.scrollTo("fitness", anchor: .top) }
                }
            }
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Health")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { showSettings = true } label: {
                        Label("Settings", systemImage: "gearshape")
                    }
                }
            }
            .refreshable { await refresh(forceBrief: true) }
            .task { await refresh(forceBrief: false) }
            .sheet(isPresented: $showSettings) { SettingsView() }
        }
    }

    // MARK: - Refresh

    private func refresh(forceBrief: Bool) async {
        // Screenshot mode renders injected sample data; no network or permission prompts.
        guard !ProcessInfo.processInfo.arguments.contains("SCREENSHOT_MODE") else { return }
        if forceBrief {
            await whoop.sync(into: modelContext)
        } else {
            await whoop.syncIfStale(into: modelContext)
        }
        await AppleHealthService.shared.sync(into: modelContext)

        let hasData = today?.hasPhysiology == true || yesterday?.hasPhysiology == true
        // Free and on-device, so rewrite it whenever fresher WHOOP data has arrived.
        let briefIsStale = todaysBrief.map { brief in
            whoop.lastSyncedAt.map { brief.createdAt < $0 } ?? false
        } ?? true
        if hasData, forceBrief || briefIsStale {
            await briefService.generate(in: modelContext)
        }
    }

    // MARK: - Hero

    private var hero: some View {
        HStack(alignment: .center, spacing: 18) {
            RecoveryRing(value: latestNight?.recovery)
            VStack(alignment: .leading, spacing: 6) {
                Text(Date.now.formatted(.dateTime.weekday(.wide).day().month(.wide)))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let brief = todaysBrief {
                    Text(brief.headline)
                        .font(.headline)
                        .fixedSize(horizontal: false, vertical: true)
                } else if briefService.isGenerating {
                    Label("Writing this morning's brief…", systemImage: "sparkles")
                        .foregroundStyle(.secondary)
                } else if today?.recovery == nil {
                    Text("No recovery score yet today. WHOOP posts it after you wake.")
                        .foregroundStyle(.secondary)
                } else {
                    Text(RecoveryRing.zone(for: today?.recovery).label).font(.headline)
                }
                HStack(spacing: 14) {
                    quick("HRV", HealthMetric.hrv.format(latestNight?.hrv), "ms")
                    quick("RHR", HealthMetric.restingHR.format(latestNight?.restingHR), "bpm")
                    quick("Sleep", HealthMetric.sleep.format(latestNight?.sleepHours), "h")
                }
                .padding(.top, 2)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    private func quick(_ title: String, _ value: String, _ unit: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title).font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value).font(.subheadline.weight(.bold)).monospacedDigit()
                Text(unit).font(.caption2).foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Brief

    @ViewBuilder
    private var briefSection: some View {
        if let brief = todaysBrief {
            VStack(alignment: .leading, spacing: 14) {
                BriefColumn(title: "Going well", icon: "arrow.up.circle.fill", color: .green, items: brief.goingWell)
                BriefColumn(title: "Watch", icon: "exclamationmark.circle.fill", color: .orange, items: brief.watch)
                BriefColumn(title: "Work on", icon: "checklist", color: .blue, items: brief.today)
                if briefService.usedFallback, let reason = OnDeviceModel.unavailableReason {
                    Text(reason).font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .card()
        } else if let error = briefService.lastError {
            Label(error, systemImage: "exclamationmark.triangle")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Trends

    private var trendCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                CardTitle(title: "Trends", icon: "chart.xyaxis.line")
                Spacer()
                Picker("Range", selection: $trendRange) {
                    ForEach(TrendRange.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .frame(width: 180)
            }
            Picker("Metric", selection: $trendMetric) {
                ForEach(HealthMetric.allCases) { Text($0.shortTitle).tag($0) }
            }
            .pickerStyle(.segmented)

            switch trendRange {
            case .sixMonths: monthlyChart
            case .thirtyDays: dailyChart
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    @ViewBuilder
    private var monthlyChart: some View {
        let points = trends.monthly(trendMetric)
        if points.count >= 2 {
            let domain = monthlyDomain(points)
            Chart(points) { point in
                // Bars rise from the bottom of the visible range, not from zero, so they
                // stay inside the chart and month-to-month change is visible.
                BarMark(x: .value("Month", point.month, unit: .month),
                        yStart: .value("Base", domain.lowerBound),
                        yEnd: .value(trendMetric.title, point.value))
                    .foregroundStyle(trendMetric.color.opacity(point.isCurrent ? 0.45 : 0.9))
                    .cornerRadius(4)
                    .annotation(position: .top) {
                        Text(trendMetric.format(point.value)).font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                    }
            }
            .chartYAxis(.hidden)
            .chartYScale(domain: domain)
            .chartXAxis {
                AxisMarks(values: .stride(by: .month)) { _ in
                    AxisValueLabel(format: .dateTime.month(.abbreviated), centered: true)
                }
            }
            .frame(height: 170)
            if let insight = trends.monthlyInsight(trendMetric) {
                Text(insight).font(.subheadline).fixedSize(horizontal: false, vertical: true)
            }
            Text("Monthly averages; the lighter bar is this month so far.")
                .font(.caption2).foregroundStyle(.secondary)
        } else {
            Text("Six-month trends appear after the first full WHOOP sync. Pull down to sync.")
                .font(.subheadline).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, minHeight: 120)
        }
    }

    /// Bars start near the data, not at zero, so month-to-month change is visible.
    private func monthlyDomain(_ points: [HealthTrends.MonthPoint]) -> ClosedRange<Double> {
        let values = points.map(\.value)
        let low = values.min() ?? 0, high = values.max() ?? 1
        let pad = max((high - low) * 0.6, high * 0.05)
        return max(0, low - pad)...(high + pad * 0.6)
    }

    @ViewBuilder
    private var dailyChart: some View {
        let points = trends.daily(trendMetric)
        let average = trends.average(trendMetric, days: 30)
        if points.count >= 2 {
            Chart {
                ForEach(points) { point in
                    if trendMetric == .recovery {
                        BarMark(x: .value("Day", point.date, unit: .day), y: .value("Recovery", point.value))
                            .foregroundStyle(RecoveryRing.zone(for: point.value).color)
                    } else {
                        LineMark(x: .value("Day", point.date, unit: .day), y: .value(trendMetric.title, point.value))
                            .foregroundStyle(trendMetric.color)
                            .interpolationMethod(.monotone)
                        PointMark(x: .value("Day", point.date, unit: .day), y: .value(trendMetric.title, point.value))
                            .foregroundStyle(trendMetric.color)
                            .symbolSize(14)
                    }
                }
                if let average {
                    RuleMark(y: .value("30-day average", average))
                        .foregroundStyle(.secondary)
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                        .annotation(position: .top, alignment: .leading) {
                            Text("30-day avg \(trendMetric.format(average))").font(.caption2).foregroundStyle(.secondary)
                        }
                }
            }
            .chartYScale(domain: dailyDomain(points.map(\.value) + [average].compactMap { $0 }))
            .chartXAxis {
                AxisMarks(values: .stride(by: .day, count: 7)) { _ in
                    AxisValueLabel(format: .dateTime.day().month(.abbreviated))
                }
            }
            .frame(height: 170)
        } else {
            Text("Not enough days yet.").font(.subheadline).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, minHeight: 120)
        }
    }

    /// Recovery on its fixed 0-100 scale; everything else fitted to the month's range.
    private func dailyDomain(_ values: [Double]) -> ClosedRange<Double> {
        if trendMetric == .recovery { return 0...100 }
        let low = values.min() ?? 0, high = values.max() ?? 1
        let pad = max((high - low) * 0.15, 0.5)
        return max(0, low - pad)...(high + pad)
    }

    // MARK: - Key metrics

    private var keyMetrics: some View {
        VStack(alignment: .leading, spacing: 10) {
            CardTitle(title: "Key metrics", icon: "tablecells")
            Grid(alignment: .trailing, horizontalSpacing: 10, verticalSpacing: 8) {
                GridRow {
                    Text("").gridColumnAlignment(.leading)
                    ForEach(["Latest", "7d", "30d", "6 mo"], id: \.self) {
                        Text($0).font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                    }
                }
                Divider().gridCellUnsizedAxes(.horizontal)
                ForEach(HealthMetric.allCases) { metric in
                    let latest = trends.latest(metric)
                    let week = trends.average(metric, days: 7)
                    GridRow {
                        Button {
                            trendMetric = metric
                        } label: {
                            HStack(spacing: 6) {
                                Circle().fill(metric.color).frame(width: 7, height: 7)
                                Text(metric.title).font(.subheadline)
                            }
                        }
                        .buttonStyle(.plain)
                        .gridColumnAlignment(.leading)
                        Text(metric.format(latest))
                            .font(.subheadline.weight(.bold).monospacedDigit())
                            .foregroundStyle(tone(metric, latest, against: trends.average(metric, days: 30)))
                        Text(metric.format(week)).font(.subheadline.monospacedDigit())
                        Text(metric.format(trends.average(metric, days: 30))).font(.subheadline.monospacedDigit())
                        Text(metric.format(trends.average(metric, days: 182))).font(.subheadline.monospacedDigit()).foregroundStyle(.secondary)
                    }
                }
            }
            Text("Latest is coloured against the 30-day average. Tap a metric to chart it.")
                .font(.caption2).foregroundStyle(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    private func tone(_ metric: HealthMetric, _ value: Double?, against baseline: Double?) -> Color {
        guard let value, let baseline, baseline != 0, let better = metric.higherIsBetter else { return .primary }
        let change = (value - baseline) / baseline
        guard abs(change) > 0.04 else { return .primary }
        return (change > 0) == better ? .green : .orange
    }

    // MARK: - Sleep

    @ViewBuilder
    private var sleepCard: some View {
        if let night = latestNight, let slept = night.sleepHours {
            VStack(alignment: .leading, spacing: 12) {
                CardTitle(title: "Last night", icon: "bed.double.fill")
                let need = night.sleepNeedHours
                let scale = max(slept, need ?? slept, 1)
                VStack(alignment: .leading, spacing: 6) {
                    bar("Slept", slept, scale: scale, color: .indigo)
                    if let need { bar("WHOOP need", need, scale: scale, color: Color(.systemGray3)) }
                }
                HStack(spacing: 18) {
                    if let need {
                        let gap = slept - need
                        stat(gap >= 0 ? "Over need" : "Short", String(format: "%.1f h", abs(gap)), gap >= 0 ? .green : .orange)
                    }
                    if let debt = night.sleepDebtHours { stat("Sleep debt", "\(Int((debt * 60).rounded())) min", debt * 60 >= 45 ? .orange : .primary) }
                    if let perf = night.sleepPerformance { stat("Performance", "\(Int(perf))%", .primary) }
                    if let consistency = night.sleepConsistency { stat("Consistency", "\(Int(consistency))%", .primary) }
                }
                if let deep = night.deepPct, let rem = night.remPct {
                    let light = max(0, 100 - deep - rem)
                    GeometryReader { geo in
                        HStack(spacing: 2) {
                            stage("Light", light, geo.size.width, .teal)
                            stage("Deep", deep, geo.size.width, .blue)
                            stage("REM", rem, geo.size.width, .purple)
                        }
                    }
                    .frame(height: 24)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                if let week = trends.average(.sleep, days: 7) {
                    Text("7-night average \(String(format: "%.1f", week)) h" + (need.map { String(format: " against a %.1f h need last night.", $0) } ?? "."))
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .card()
        }
    }

    private func bar(_ title: String, _ hours: Double, scale: Double, color: Color) -> some View {
        HStack(spacing: 8) {
            Text(title).font(.caption).foregroundStyle(.secondary).frame(width: 86, alignment: .leading)
            GeometryReader { geo in
                RoundedRectangle(cornerRadius: 4).fill(color).frame(width: geo.size.width * hours / scale)
            }
            .frame(height: 12)
            Text(String(format: "%.1f h", hours)).font(.caption.monospacedDigit()).frame(width: 46, alignment: .trailing)
        }
    }

    private func stage(_ name: String, _ pct: Double, _ width: CGFloat, _ color: Color) -> some View {
        ZStack {
            color
            Text("\(name) \(Int(pct.rounded()))%").font(.caption2.weight(.bold)).foregroundStyle(.white).lineLimit(1).minimumScaleFactor(0.6)
        }
        .frame(width: max(0, width * pct / 100 - 2))
    }

    private func stat(_ title: String, _ value: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title.uppercased()).font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
            Text(value).font(.subheadline.weight(.bold)).monospacedDigit().foregroundStyle(color)
        }
    }

    // MARK: - Training

    @ViewBuilder
    private var trainingCard: some View {
        let weeks = trends.weeklyStrain()
        let recent = workouts.filter { $0.date >= (calendar.date(byAdding: .day, value: -7, to: .now) ?? .now) }
        if weeks.contains(where: { $0.value > 0 }) || !recent.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                CardTitle(title: "Training", icon: "figure.run")
                HStack(spacing: 18) {
                    if let ratio = trends.loadRatio {
                        stat("Load ratio", String(format: "%.2f", ratio), ratio > 1.3 || ratio < 0.8 ? .orange : .green)
                    }
                    stat("Zone 4+ · 7d", "\(Int(thresholdMinutes(days: 7).rounded())) min", .primary)
                    stat("Zone 4+ · 30d", "\(Int(thresholdMinutes(days: 30).rounded())) min", thresholdMinutes(days: 30) < 10 ? .orange : .primary)
                    if let steps = yesterday?.steps { stat("Steps yday", steps.formatted(.number.precision(.fractionLength(0))), .primary) }
                }
                if weeks.contains(where: { $0.value > 0 }) {
                    Chart(weeks) { week in
                        BarMark(x: .value("Week", week.date, unit: .weekOfYear), y: .value("Strain", week.value))
                            .foregroundStyle(week.date == weeks.last?.date ? Color.orange : Color.orange.opacity(0.45))
                            .cornerRadius(3)
                    }
                    .chartYAxis(.hidden)
                    .chartXAxis {
                        AxisMarks(values: .stride(by: .weekOfYear, count: 2)) { _ in
                            AxisValueLabel(format: .dateTime.day().month(.abbreviated))
                        }
                    }
                    .frame(height: 90)
                    Text("Total strain per week, last 10 weeks; this week so far in bold.")
                        .font(.caption2).foregroundStyle(.secondary)
                }
                if !recent.isEmpty {
                    VStack(spacing: 6) {
                        ForEach(recent.prefix(6)) { workout in
                            HStack {
                                Text(workout.date.formatted(.dateTime.weekday(.abbreviated))).font(.caption).foregroundStyle(.secondary).frame(width: 34, alignment: .leading)
                                Text(workout.type.capitalized).font(.subheadline)
                                Spacer()
                                Text("\(Int(workout.durationMin)) min").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                                if let strain = workout.strain {
                                    Text(String(format: "%.1f", strain)).font(.caption.weight(.semibold).monospacedDigit())
                                        .frame(width: 34, alignment: .trailing)
                                }
                            }
                        }
                    }
                }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .card()
        }
    }

    private func thresholdMinutes(days: Int) -> Double {
        let start = calendar.date(byAdding: .day, value: -days, to: .now) ?? .now
        return workouts.filter { $0.date >= start && $0.zoneMinutes.count >= 6 }
            .reduce(0) { $0 + $1.zoneMinutes[4] + $1.zoneMinutes[5] }
    }

    // MARK: - Footer and empty state

    private var footer: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let error = whoop.lastError {
                Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
            }
            if let last = whoop.lastSyncedAt {
                Text("WHOOP synced \(last.formatted(.relative(presentation: .named))). Pull to refresh.")
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var notConnected: some View {
        ContentUnavailableView {
            Label("Connect WHOOP", systemImage: "heart.text.square")
        } description: {
            Text("Recovery, HRV, sleep and strain come from WHOOP; steps and exercise from Apple Health and your Apple Watch.")
        } actions: {
            Button("Open Settings") { showSettings = true }
                .buttonStyle(.borderedProminent)
        }
    }
}

// MARK: - Pieces

private struct CardTitle: View {
    let title: String
    let icon: String

    var body: some View {
        Label(title, systemImage: icon)
            .font(.headline)
            .labelStyle(.titleAndIcon)
    }
}

struct RecoveryRing: View {
    let value: Double?

    struct Zone {
        let color: Color
        let label: String
    }

    /// WHOOP's own bands: green 67+, yellow 34-66, red 33 and below.
    static func zone(for value: Double?) -> Zone {
        guard let value else { return Zone(color: .gray, label: "No recovery yet") }
        switch value {
        case 67...:   return Zone(color: .green, label: "Green recovery: room to push")
        case 34..<67: return Zone(color: .yellow, label: "Yellow recovery: train, but not hard")
        default:      return Zone(color: .red, label: "Red recovery: keep today easy")
        }
    }

    var body: some View {
        let zone = Self.zone(for: value)
        ZStack {
            Circle().stroke(Color(.tertiarySystemFill), lineWidth: 10)
            Circle()
                .trim(from: 0, to: (value ?? 0) / 100)
                .stroke(zone.color, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                .rotationEffect(.degrees(-90))
            VStack(spacing: 0) {
                Text(value.map { "\(Int($0))" } ?? "–")
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .foregroundStyle(zone.color)
                Text("RECOVERY")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 96, height: 96)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(value.map { "Recovery \(Int($0)) percent" } ?? "No recovery yet")
    }
}

private struct BriefColumn: View {
    let title: String
    let icon: String
    let color: Color
    let items: [String]

    var body: some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Label(title, systemImage: icon)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(color)
                ForEach(items, id: \.self) { item in
                    Text("• \(item)")
                        .font(.subheadline)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}
