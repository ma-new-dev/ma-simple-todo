import SwiftUI
import SwiftData
import Charts

/// The morning snapshot: today's recovery, how last night and yesterday compare with the
/// week, and a three-part brief. Deliberately short — the full dashboard stays an artifact.
struct HealthTabView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \DailyMetric.date, order: .reverse) private var metrics: [DailyMetric]
    @Query(sort: \HealthBrief.createdAt, order: .reverse) private var briefs: [HealthBrief]

    @State private var whoop = WhoopSyncService.shared
    @State private var briefService = HealthBriefService.shared
    @State private var showSettings = false

    private var calendar: Calendar { .current }
    private var today: DailyMetric? { metrics.first { calendar.isDateInToday($0.date) } }
    private var yesterday: DailyMetric? { metrics.first { calendar.isDateInYesterday($0.date) } }
    private var lastWeek: [DailyMetric] {
        let cutoff = calendar.date(byAdding: .day, value: -7, to: calendar.startOfDay(for: .now)) ?? .now
        return metrics.filter { $0.date >= cutoff && !calendar.isDateInToday($0.date) }
    }
    private var todaysBrief: HealthBrief? {
        briefs.first { calendar.isDateInToday($0.date) }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if !WhoopTokenStore.shared.isConnected && metrics.isEmpty {
                        notConnected
                    } else {
                        hero
                        tiles
                        briefSection
                        recoveryWeek
                        footer
                    }
                }
                .padding()
                .frame(maxWidth: 760)
                .frame(maxWidth: .infinity)
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
        HStack(alignment: .center, spacing: 20) {
            RecoveryRing(value: today?.recovery)
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
                    Text(RecoveryRing.zone(for: today?.recovery).label)
                        .font(.headline)
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Tiles

    private var tiles: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 12)], spacing: 12) {
            MetricTile(
                title: "HRV", value: today?.hrv, unit: "ms",
                baseline: average(\.hrv), higherIsBetter: true
            )
            MetricTile(
                title: "Resting HR", value: today?.restingHR, unit: "bpm",
                baseline: average(\.restingHR), higherIsBetter: false
            )
            MetricTile(
                title: "Sleep", value: today?.sleepHours, unit: "h", decimals: 1,
                baseline: average(\.sleepHours), higherIsBetter: true,
                caption: today?.sleepPerformance.map { "\(Int($0))% of need" }
            )
            MetricTile(
                title: "Strain yesterday", value: yesterday?.dayStrain, unit: "", decimals: 1,
                baseline: average(\.dayStrain), higherIsBetter: nil
            )
            MetricTile(
                title: "Steps yesterday", value: yesterday?.steps, unit: "",
                baseline: average(\.steps), higherIsBetter: true,
                caption: AppleHealthService.shared.isAvailable ? nil : "Apple Health is iPhone-only"
            )
            MetricTile(
                title: "Exercise yesterday", value: yesterday?.exerciseMinutes, unit: "min",
                baseline: average(\.exerciseMinutes), higherIsBetter: true,
                caption: "Apple Watch"
            )
        }
    }

    private func average(_ keyPath: KeyPath<DailyMetric, Double?>) -> Double? {
        let values = lastWeek.compactMap { $0[keyPath: keyPath] }
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
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
                    Text(reason)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding()
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 16))
        } else if let error = briefService.lastError {
            Label(error, systemImage: "exclamationmark.triangle")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Week

    @ViewBuilder
    private var recoveryWeek: some View {
        let week = metrics
            .filter { $0.recovery != nil }
            .prefix(7)
            .reversed()
        if week.count >= 2 {
            VStack(alignment: .leading, spacing: 8) {
                Text("Recovery, last 7 days").font(.subheadline.weight(.semibold))
                Chart(Array(week), id: \.date) { day in
                    BarMark(
                        x: .value("Day", day.date, unit: .day),
                        y: .value("Recovery", day.recovery ?? 0)
                    )
                    .foregroundStyle(RecoveryRing.zone(for: day.recovery).color)
                    .annotation(position: .top) {
                        Text("\(Int(day.recovery ?? 0))")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .chartYScale(domain: 0...100)
                .chartYAxis(.hidden)
                .chartXAxis {
                    AxisMarks(values: .stride(by: .day)) {
                        AxisValueLabel(format: .dateTime.weekday(.narrow))
                    }
                }
                .frame(height: 120)
            }
            .padding()
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 16))
        }
    }

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

private struct MetricTile: View {
    let title: String
    let value: Double?
    let unit: String
    var decimals = 0
    let baseline: Double?
    /// nil when neither direction is good or bad (strain).
    let higherIsBetter: Bool?
    var caption: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title.uppercased())
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(format(value)).font(.title2.weight(.bold)).monospacedDigit()
                if value != nil, !unit.isEmpty {
                    Text(unit).font(.caption).foregroundStyle(.secondary)
                }
            }
            if let delta {
                Text(delta.text)
                    .font(.caption)
                    .foregroundStyle(delta.color)
            } else if let caption {
                Text(caption).font(.caption).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func format(_ v: Double?) -> String {
        guard let v else { return "–" }
        if unit.isEmpty && decimals == 0 { return v.formatted(.number.precision(.fractionLength(0))) }
        return String(format: "%.\(decimals)f", v)
    }

    private var delta: (text: String, color: Color)? {
        guard let value, let baseline, baseline != 0 else { return nil }
        let diff = value - baseline
        let shown = abs(diff) < 1 && decimals > 0 ? String(format: "%.1f", abs(diff)) : "\(Int(abs(diff).rounded()))"
        let arrow = diff >= 0 ? "▲" : "▼"
        let color: Color
        if let higherIsBetter, abs(diff) / baseline > 0.03 {
            color = (diff > 0) == higherIsBetter ? .green : .orange
        } else {
            color = .secondary
        }
        return ("\(arrow) \(shown) vs 7-day avg", color)
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
