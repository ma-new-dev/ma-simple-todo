import SwiftUI
import Charts

/// A one-screen summary of the PMS/AIF Portfolio Tracker. The tracker refreshes twice a
/// month, so this is a snapshot with an "as of" date, not a live number.
struct NetWorthTabView: View {
    @State private var store = NetWorthStore.shared
    /// Masks every amount; for showing the phone to someone. Remembered on this device.
    @AppStorage("netWorth.hideAmounts") private var hideAmounts = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
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
                .frame(maxWidth: 760)
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
        }
    }

    // MARK: - Content

    @ViewBuilder
    private func content(_ s: NetWorthSummary) -> some View {
        hero(s)
        allocationBar(s.allocation)
        if s.history.count >= 2 { trend(s.history) }
        segments(s.segments)
        managers(s.managers)
        if !s.decisions.isEmpty { decisions(s.decisions) }
        footer(s)
    }

    private func hero(_ s: NetWorthSummary) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("PMS / AIF portfolio · as of \(display(date: s.asOf))")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(cr(s.totals.fmvCr))
                .font(.system(size: 40, weight: .bold, design: .rounded))
                .monospacedDigit()
            HStack(spacing: 16) {
                figure("Gain", signedCr(s.totals.gainCr), color: s.totals.gainCr >= 0 ? .green : .red)
                figure("Lifetime", pct(s.totals.lifetimeGainPct, signed: true), color: .primary)
                figure("Blended IRR", pct(s.totals.blendedIrrPct), color: .primary)
            }
            HStack(spacing: 16) {
                figure("Net invested", cr(s.totals.netInvestedCr), color: .secondary)
                if let vs = s.totals.vsNifty500Cr {
                    figure("Equity vs Nifty 500", signedCr(vs), color: vs >= 0 ? .green : .red)
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private func figure(_ title: String, _ value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title.uppercased()).font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
            Text(value).font(.headline).monospacedDigit().foregroundStyle(color)
        }
    }

    private static let sliceColors: [Color] = [.green, .purple, .blue, .pink, .orange, .teal]

    private func allocationBar(_ slices: [NetWorthSummary.Slice]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            GeometryReader { geo in
                HStack(spacing: 2) {
                    ForEach(Array(slices.enumerated()), id: \.element.id) { index, slice in
                        Self.sliceColors[index % Self.sliceColors.count]
                            .frame(width: max(2, geo.size.width * slice.pct / 100 - 2))
                    }
                }
            }
            .frame(height: 14)
            .clipShape(RoundedRectangle(cornerRadius: 4))
            FlowingLegend(items: slices.enumerated().map { index, slice in
                (Self.sliceColors[index % Self.sliceColors.count], "\(slice.name) \(String(format: "%.1f", slice.pct))%")
            })
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private func trend(_ points: [NetWorthSummary.Point]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Value at each refresh").font(.subheadline.weight(.semibold))
            Chart(points) { point in
                if let date = NetWorthSummary.date(point.date) {
                    LineMark(x: .value("Date", date), y: .value("FMV", point.fmvCr))
                        .interpolationMethod(.monotone)
                    PointMark(x: .value("Date", date), y: .value("FMV", point.fmvCr))
                }
            }
            .chartYAxis(hideAmounts ? .hidden : .automatic)
            .chartYScale(domain: .automatic(includesZero: false))
            .frame(height: 140)
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private func segments(_ segments: [NetWorthSummary.Segment]) -> some View {
        card("By segment") {
            ForEach(segments) { segment in
                row(
                    title: segment.name,
                    subtitle: segment.note,
                    value: cr(segment.fmvCr),
                    trailing: segment.irrPct.map { "IRR \(pct($0))" } ?? "—"
                )
            }
        }
    }

    private func managers(_ managers: [NetWorthSummary.Manager]) -> some View {
        card("By manager") {
            ForEach(managers.sorted { $0.fmvCr > $1.fmvCr }) { m in
                row(
                    title: m.name,
                    subtitle: [m.type, m.vsNifty500Cr.map { "vs Nifty 500 \(signedCr($0))" }]
                        .compactMap { $0 }.joined(separator: " · "),
                    value: cr(m.fmvCr),
                    trailing: m.irrPct.map { "IRR \(pct($0))" } ?? "—",
                    trailingColor: (m.irrPct ?? 0) < 0 ? .red : .secondary
                )
            }
        }
    }

    private func decisions(_ decisions: [NetWorthSummary.Decision]) -> some View {
        card("Open decisions") {
            ForEach(decisions) { d in
                VStack(alignment: .leading, spacing: 2) {
                    Text(d.title).font(.subheadline.weight(.medium))
                    Text([d.status, d.nextDate.map { "next \($0)" }].compactMap { $0 }.joined(separator: " · "))
                        .font(.caption)
                        .foregroundStyle(d.status.lowercased().contains("due") ? .orange : .secondary)
                }
                .padding(.vertical, 4)
            }
        }
    }

    private func footer(_ s: NetWorthSummary) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            if let refreshed = NetWorthSummary.date(s.refreshedAt),
               Date().timeIntervalSince(refreshed) > 20 * 86_400 {
                Label("Last refresh was \(refreshed.formatted(.relative(presentation: .named))); a newer one is due.",
                      systemImage: "clock.badge.exclamationmark")
                    .foregroundStyle(.orange)
            }
            Text("From the Portfolio Tracker refresh of \(display(date: s.refreshedAt)). Updates twice a month.")
            if let error = store.lastError {
                Text(error)
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    // MARK: - Building blocks

    private func card<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.subheadline.weight(.semibold))
            content()
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private func row(title: String, subtitle: String?, value: String, trailing: String, trailingColor: Color = .secondary) -> some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline)
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle).font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(value).font(.subheadline.weight(.semibold)).monospacedDigit()
                Text(trailing).font(.caption).foregroundStyle(trailingColor)
            }
        }
        .padding(.vertical, 3)
    }

    // MARK: - Formatting

    private func cr(_ value: Double) -> String {
        hideAmounts ? "₹ ••••" : "₹\(String(format: "%.2f", value)) cr"
    }

    private func signedCr(_ value: Double) -> String {
        hideAmounts ? "••••" : "\(value >= 0 ? "+" : "−")₹\(String(format: "%.2f", abs(value))) cr"
    }

    private func pct(_ value: Double, signed: Bool = false) -> String {
        let sign = signed && value >= 0 ? "+" : ""
        return "\(sign)\(String(format: "%.2f", value))%"
    }

    private func display(date: String) -> String {
        NetWorthSummary.date(date)?.formatted(.dateTime.day().month(.abbreviated).year()) ?? date
    }
}

private struct FlowingLegend: View {
    let items: [(Color, String)]

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), alignment: .leading)], alignment: .leading, spacing: 4) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                HStack(spacing: 6) {
                    RoundedRectangle(cornerRadius: 2).fill(item.0).frame(width: 10, height: 10)
                    Text(item.1).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }
}
