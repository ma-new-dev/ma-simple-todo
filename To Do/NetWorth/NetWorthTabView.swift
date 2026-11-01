import SwiftUI
import Charts

/// The PMS/AIF Portfolio Tracker as a monthly read: where the book stands, how each
/// manager did against the market this month, who is doing well, who is being watched,
/// who is lagging, and the moves to make. The tracker refreshes twice a month, so this
/// is a dated snapshot, not a live number.
struct NetWorthTabView: View {
    @State private var store = NetWorthStore.shared
    /// Masks every amount; for showing the phone to someone. Remembered on this device.
    @AppStorage("netWorth.hideAmounts") private var hideAmounts = false
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var selected: NetWorthSummary.Manager?
    @State private var showSteady = false

    var body: some View {
        NavigationStack {
            ScrollView {
                Group {
                    if let summary = store.summary {
                        content(summary)
                    } else if store.isLoading {
                        ProgressView().frame(maxWidth: .infinity, minHeight: 300)
                    } else {
                        ContentUnavailableView(
                            "No portfolio summary yet",
                            systemImage: "indianrupeesign.circle",
                            description: Text(store.lastError ?? "It appears after the next Portfolio Tracker refresh.")
                        )
                    }
                }
                .padding()
                .frame(maxWidth: 1100)
                .frame(maxWidth: .infinity)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Net Worth")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { hideAmounts.toggle() } label: {
                        Label(hideAmounts ? "Show amounts" : "Hide amounts",
                              systemImage: hideAmounts ? "eye.slash" : "eye")
                    }
                }
            }
            .refreshable { await store.load() }
            .task {
                guard !ProcessInfo.processInfo.arguments.contains("SCREENSHOT_MODE") else { return }
                await store.load()
            }
            .sheet(item: $selected) { manager in
                ManagerDetail(manager: manager, summary: store.summary, money: money)
                    .presentationDetents([.medium, .large])
            }
        }
    }

    private var money: Money { Money(hidden: hideAmounts) }

    // MARK: - Layout

    @ViewBuilder
    private func content(_ s: NetWorthSummary) -> some View {
        if sizeClass == .regular {
            VStack(spacing: 16) {
                hero(s)
                HStack(alignment: .top, spacing: 16) {
                    VStack(spacing: 16) {
                        monthCard(s)
                        scorecard(s)
                    }
                    VStack(spacing: 16) {
                        moves(s)
                        deployment(s)
                        allocation(s)
                        trend(s)
                    }
                    .frame(width: 400)
                }
                footer(s)
            }
        } else {
            VStack(spacing: 16) {
                hero(s)
                monthCard(s)
                scorecard(s)
                moves(s)
                deployment(s)
                allocation(s)
                trend(s)
                footer(s)
            }
        }
    }

    // MARK: - Hero

    private func hero(_ s: NetWorthSummary) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("PMS / AIF portfolio · statements to \(display(s.asOf))")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(money.cr(s.totals.fmvCr))
                .font(.system(size: 38, weight: .bold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            if let change = changeSinceLastRefresh(s) {
                Text(money.signedCr(change) + " since the \(displayShort(s.history.dropLast().last?.date)) refresh")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(change >= 0 ? .green : .red)
            }
            HStack(spacing: 18) {
                figure("Gain", money.signedCr(s.totals.gainCr), s.totals.gainCr >= 0 ? .green : .red,
                       caption: Money.pct(s.totals.lifetimeGainPct, signed: true) + " lifetime")
                figure("Blended IRR", Money.pct(s.totals.blendedIrrPct), .primary,
                       caption: s.totals.blendedIrrInclCashPct.map { Money.pct($0) + " incl. cash" })
                if let vs = s.totals.vsNifty500Cr {
                    figure("vs Nifty 500", money.signedCr(vs), vs >= 0 ? .green : .red, caption: "equity book")
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    private func changeSinceLastRefresh(_ s: NetWorthSummary) -> Double? {
        guard s.history.count >= 2, let last = s.history.last, let previous = s.history.dropLast().last else { return nil }
        return last.fmvCr - previous.fmvCr
    }

    private func figure(_ title: String, _ value: String, _ color: Color, caption: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title.uppercased()).font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
            Text(value).font(.headline).monospacedDigit().foregroundStyle(color)
            if let caption { Text(caption).font(.caption2).foregroundStyle(.secondary) }
        }
    }

    // MARK: - The month

    @ViewBuilder
    private func monthCard(_ s: NetWorthSummary) -> some View {
        let rows = s.managers.filter { $0.monthPct != nil && $0.resolvedVerdict != .cash && !Self.isDebt($0) }
            .sorted { ($0.monthPct ?? 0) > ($1.monthPct ?? 0) }
        if s.monthSummary != nil || !rows.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                SectionTitle(title: s.period ?? "This month", subtitle: "how the month went", icon: "calendar")
                if let text = s.monthSummary {
                    Text(text).font(.subheadline).fixedSize(horizontal: false, vertical: true)
                }
                if !rows.isEmpty {
                    MonthVsMarketChart(rows: rows, benchmark: s.benchmark) { selected = $0 }
                }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .card()
        }
    }

    static func isDebt(_ m: NetWorthSummary.Manager) -> Bool {
        let t = m.type.lowercased()
        return t.contains("debt") || t.contains("multi")
    }

    // MARK: - Scorecard

    @ViewBuilder
    private func scorecard(_ s: NetWorthSummary) -> some View {
        let groups: [(NetWorthSummary.Verdict, Color, String)] = [
            (.strong, .green, "arrow.up.right.circle.fill"),
            (.watch, .orange, "eye.circle.fill"),
            (.lagging, .red, "arrow.down.right.circle.fill"),
        ]
        let rest = s.managers.filter { ![.strong, .watch, .lagging].contains($0.resolvedVerdict) }
        VStack(alignment: .leading, spacing: 14) {
            SectionTitle(title: "Managers", subtitle: "\(s.managers.count) positions", icon: "person.3")
            ForEach(groups, id: \.0) { verdict, color, icon in
                let members = s.managers.filter { $0.resolvedVerdict == verdict }.sorted { $0.fmvCr > $1.fmvCr }
                if !members.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Label("\(verdict.title) · \(members.count)", systemImage: icon)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(color)
                        ForEach(members) { manager in
                            ManagerRow(manager: manager, money: money, benchmark: s.benchmark) { selected = manager }
                        }
                    }
                }
            }
            if !rest.isEmpty {
                DisclosureGroup(isExpanded: $showSteady) {
                    VStack(spacing: 6) {
                        ForEach(rest.sorted { $0.fmvCr > $1.fmvCr }) { manager in
                            ManagerRow(manager: manager, money: money, benchmark: s.benchmark) { selected = manager }
                        }
                    }
                    .padding(.top, 6)
                } label: {
                    Label("Steady, new and parked cash · \(rest.count)", systemImage: "equal.circle.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    // MARK: - Moves

    @ViewBuilder
    private func moves(_ s: NetWorthSummary) -> some View {
        if !s.decisions.isEmpty {
            let urgent = s.decisions.filter { $0.needsDecision == true }.count
            let kinds: [(String, String, String, Color)] = [
                ("add", "Add", "plus.circle.fill", .green),
                ("exit", "Reduce or exit", "minus.circle.fill", .red),
                ("watch", "Watch", "eye.fill", .orange),
                ("fees", "Fees", "indianrupeesign.circle.fill", .purple),
                ("admin", "Admin", "wrench.and.screwdriver.fill", .gray),
            ]
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    SectionTitle(title: "Moves", subtitle: "open decisions", icon: "arrow.left.arrow.right")
                    Spacer()
                    Text(urgent == 0 ? "Nothing urgent" : "\(urgent) need\(urgent == 1 ? "s" : "") a call")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background((urgent == 0 ? Color.green : .red).opacity(0.15))
                        .foregroundStyle(urgent == 0 ? .green : .red)
                        .clipShape(Capsule())
                }
                ForEach(kinds, id: \.0) { kind, title, icon, color in
                    let items = s.decisions.filter { ($0.kind ?? "watch") == kind }
                    if !items.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Label(title, systemImage: icon).font(.caption.weight(.semibold)).foregroundStyle(color)
                            ForEach(items) { decision in
                                HStack(alignment: .firstTextBaseline) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(decision.title).font(.subheadline.weight(.medium))
                                        Text(decision.status).font(.caption).foregroundStyle(.secondary)
                                            .fixedSize(horizontal: false, vertical: true)
                                    }
                                    Spacer(minLength: 8)
                                    if let next = decision.nextDate {
                                        Text(next).font(.caption2.weight(.medium)).foregroundStyle(decision.needsDecision == true ? .red : .secondary)
                                    }
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

    // MARK: - Deployment

    @ViewBuilder
    private func deployment(_ s: NetWorthSummary) -> some View {
        if let plan = s.deployment {
            VStack(alignment: .leading, spacing: 10) {
                SectionTitle(title: "Deployment", subtitle: plan.title, icon: "arrow.down.to.line.circle")
                ProgressView(value: min(plan.doneCr, plan.targetCr), total: plan.targetCr) {
                    Text(hideAmounts ? "\(Int(plan.doneCr / plan.targetCr * 100))% deployed"
                                     : "₹\(Money.short(plan.doneCr)) of ₹\(Money.short(plan.targetCr)) cr deployed")
                        .font(.subheadline.weight(.medium))
                }
                .tint(.green)
                ForEach(plan.items) { item in
                    HStack {
                        Text(item.name).font(.caption).frame(width: 80, alignment: .leading)
                        ProgressView(value: min(item.doneCr, item.plannedCr), total: max(item.plannedCr, 0.01))
                            .tint(item.doneCr >= item.plannedCr ? .green : .blue)
                        Text(hideAmounts ? "" : "\(Money.short(item.doneCr)) / \(Money.short(item.plannedCr))")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .frame(width: 70, alignment: .trailing)
                    }
                }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .card()
        }
    }

    // MARK: - Allocation and trend

    private static let sliceColors: [Color] = [.green, .purple, .blue, .pink, .orange, .teal]

    private func allocation(_ s: NetWorthSummary) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionTitle(title: "Allocation", subtitle: "by value", icon: "chart.bar.fill")
            GeometryReader { geo in
                HStack(spacing: 2) {
                    ForEach(Array(s.allocation.enumerated()), id: \.element.id) { index, slice in
                        Self.sliceColors[index % Self.sliceColors.count]
                            .frame(width: max(2, geo.size.width * slice.pct / 100 - 2))
                    }
                }
            }
            .frame(height: 14)
            .clipShape(RoundedRectangle(cornerRadius: 4))
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), alignment: .leading)], alignment: .leading, spacing: 4) {
                ForEach(Array(s.allocation.enumerated()), id: \.element.id) { index, slice in
                    HStack(spacing: 6) {
                        RoundedRectangle(cornerRadius: 2).fill(Self.sliceColors[index % Self.sliceColors.count]).frame(width: 10, height: 10)
                        Text("\(slice.name) \(String(format: "%.1f", slice.pct))%").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            ForEach(s.segments) { segment in
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(segment.name).font(.subheadline)
                        if let note = segment.note { Text(note).font(.caption2).foregroundStyle(.secondary) }
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 1) {
                        Text(money.cr(segment.fmvCr)).font(.subheadline.weight(.semibold)).monospacedDigit()
                        Text(segment.irrPct.map { "IRR " + Money.pct($0) } ?? "at cost").font(.caption2).foregroundStyle(.secondary)
                    }
                }
                .padding(.top, 4)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    @ViewBuilder
    private func trend(_ s: NetWorthSummary) -> some View {
        if s.history.count >= 2 {
            VStack(alignment: .leading, spacing: 8) {
                SectionTitle(title: "Value at each refresh", subtitle: "\(s.history.count) refreshes", icon: "chart.xyaxis.line")
                Chart(s.history) { point in
                    if let date = NetWorthSummary.date(point.date) {
                        LineMark(x: .value("Date", date), y: .value("Value", point.fmvCr))
                            .interpolationMethod(.monotone)
                        PointMark(x: .value("Date", date), y: .value("Value", point.fmvCr))
                        if let invested = point.netInvestedCr {
                            LineMark(x: .value("Date", date), y: .value("Invested", invested), series: .value("Series", "Invested"))
                                .foregroundStyle(.secondary)
                                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                        }
                    }
                }
                .chartYAxis(hideAmounts ? .hidden : .automatic)
                .chartYScale(domain: .automatic(includesZero: false))
                .frame(height: 140)
                Text("Solid: value · dashed: net invested").font(.caption2).foregroundStyle(.secondary)
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .card()
        }
    }

    private func footer(_ s: NetWorthSummary) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            if let refreshed = NetWorthSummary.date(s.refreshedAt), Date().timeIntervalSince(refreshed) > 20 * 86_400 {
                Label("Last refresh was \(refreshed.formatted(.relative(presentation: .named))); a newer one is due.",
                      systemImage: "clock.badge.exclamationmark")
                    .foregroundStyle(.orange)
            }
            Text("From the Portfolio Tracker refresh of \(display(s.refreshedAt)). Updates twice a month.")
            if let error = store.lastError { Text(error) }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func display(_ date: String) -> String {
        NetWorthSummary.date(date)?.formatted(.dateTime.day().month(.abbreviated).year()) ?? date
    }

    private func displayShort(_ date: String?) -> String {
        guard let date else { return "" }
        return NetWorthSummary.date(date)?.formatted(.dateTime.day().month(.abbreviated)) ?? date
    }
}

// MARK: - Money formatting

/// Amounts in ₹ crore, masked when the eye toggle is on. Percentages are never masked.
struct Money {
    let hidden: Bool

    func cr(_ value: Double) -> String {
        hidden ? "₹ ••••" : "₹\(String(format: "%.2f", value)) cr"
    }

    func signedCr(_ value: Double) -> String {
        hidden ? "••••" : "\(value >= 0 ? "+" : "−")₹\(String(format: "%.2f", abs(value))) cr"
    }

    static func pct(_ value: Double, signed: Bool = false) -> String {
        let sign = value < 0 ? "−" : (signed ? "+" : "")
        return "\(sign)\(String(format: "%.2f", abs(value)))%"
    }

    static func short(_ value: Double) -> String {
        value == value.rounded() ? String(Int(value)) : String(format: "%.1f", value)
    }
}

// MARK: - Pieces

private struct SectionTitle: View {
    let title: String
    let subtitle: String
    let icon: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: icon).foregroundStyle(.tint)
            Text(title).font(.headline)
            Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
        }
    }
}

/// Each manager's month as a bar, against a dashed line for the market.
private struct MonthVsMarketChart: View {
    let rows: [NetWorthSummary.Manager]
    let benchmark: NetWorthSummary.Benchmark?
    let onSelect: (NetWorthSummary.Manager) -> Void

    var body: some View {
        let market = benchmark?.monthPct
        VStack(alignment: .leading, spacing: 6) {
            Chart {
                ForEach(rows) { m in
                    BarMark(x: .value("Month", m.monthPct ?? 0), y: .value("Manager", Self.short(m.name)))
                        .foregroundStyle(color(for: m, market: market))
                        .annotation(position: (m.monthPct ?? 0) < 0 ? .leading : .trailing, spacing: 4) {
                            Text(String(format: "%+.1f%%", m.monthPct ?? 0))
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                }
                if let market {
                    RuleMark(x: .value("Market", market))
                        .foregroundStyle(.secondary)
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                }
            }
            .chartXAxis(.hidden)
            .chartXScale(domain: domain(market: market))
            .frame(height: CGFloat(rows.count) * 26 + 10)
            if let market, let name = benchmark?.name {
                Text("Dashed line: \(name) \(Money.pct(market, signed: true)). Green lost less than the market, red lost more.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func color(for m: NetWorthSummary.Manager, market: Double?) -> Color {
        guard let market, let month = m.monthPct else { return .blue }
        return month >= market ? .green : .red
    }

    private func domain(market: Double?) -> ClosedRange<Double> {
        let values = rows.compactMap(\.monthPct) + [market ?? 0, 0]
        let low = (values.min() ?? -1) * 1.35
        let high = max((values.max() ?? 1) * 1.35, 1)
        return min(low, -1)...high
    }

    static func short(_ name: String) -> String {
        name.replacingOccurrences(of: "Dezerv ", with: "")
            .replacingOccurrences(of: " Capital", with: "")
            .replacingOccurrences(of: " Classic Growth", with: "")
    }
}

private struct ManagerRow: View {
    let manager: NetWorthSummary.Manager
    let money: Money
    let benchmark: NetWorthSummary.Benchmark?
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(manager.name).font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
                        Text(manager.type).font(.caption2).foregroundStyle(.secondary)
                    }
                    if let why = manager.why {
                        Text(why).font(.caption).foregroundStyle(.secondary).lineLimit(3).multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 6)
                VStack(alignment: .trailing, spacing: 4) {
                    if let action = manager.action { ActionChip(action: action) }
                    Text(money.cr(manager.fmvCr)).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                    if let month = manager.monthPct {
                        Text("Month " + String(format: "%+.1f%%", month))
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(benchmark?.monthPct.map { month >= $0 ? Color.green : .red } ?? .secondary)
                    }
                }
            }
            .padding(10)
            .background(Color(.tertiarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
    }
}

struct ActionChip: View {
    let action: String

    var body: some View {
        Text(action)
            .font(.caption2.weight(.bold))
            .textCase(.uppercase)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(color.opacity(0.15))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }

    private var color: Color {
        switch action.lowercased() {
        case "add": .green
        case "exit": .red
        case "reduce": .orange
        case "switch": .purple
        default: .gray
        }
    }
}

private struct ManagerDetail: View {
    let manager: NetWorthSummary.Manager
    let summary: NetWorthSummary?
    let money: Money
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack {
                        Label(manager.resolvedVerdict.title, systemImage: "circle.fill")
                            .foregroundStyle(verdictColor)
                            .font(.subheadline.weight(.semibold))
                        Spacer()
                        if let action = manager.action { ActionChip(action: action) }
                    }
                    if let why = manager.why { Text(why) }
                }
                Section("Numbers") {
                    row("Value", money.cr(manager.fmvCr))
                    row("Gain", money.signedCr(manager.gainCr))
                    if let irr = manager.irrPct { row("IRR since start", Money.pct(irr)) }
                    if let lead = manager.vsNifty500Cr { row("vs Nifty 500 fund", money.signedCr(lead)) }
                    if let month = manager.monthPct {
                        row("This month", Money.pct(month, signed: true) + (summary?.benchmark?.monthPct.map { " vs " + Money.pct($0, signed: true) } ?? ""))
                    }
                    if let year = manager.oneYearPct {
                        row("One year", Money.pct(year, signed: true) + (summary?.benchmark?.oneYearPct.map { " vs " + Money.pct($0, signed: true) } ?? ""))
                    }
                    if let asOf = manager.asOf { row("Valued at", asOf) }
                }
                if let ref = manager.decisionRef, let decision = summary?.decisions.first(where: { $0.title.hasPrefix(ref + " ") }) {
                    Section("Related decision") {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(decision.title).font(.subheadline.weight(.semibold))
                            Text(decision.status).font(.subheadline).foregroundStyle(.secondary)
                            if let next = decision.nextDate { Text("Next: \(next)").font(.caption).foregroundStyle(.secondary) }
                        }
                    }
                }
            }
            .navigationTitle(manager.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }

    private var verdictColor: Color {
        switch manager.resolvedVerdict {
        case .strong: .green
        case .watch: .orange
        case .lagging: .red
        default: .secondary
        }
    }

    private func row(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title).foregroundStyle(.secondary)
            Spacer()
            Text(value).monospacedDigit()
        }
    }
}

extension View {
    /// The grouped-card look shared by the Health, Food and Net Worth tabs.
    func card() -> some View {
        background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}
