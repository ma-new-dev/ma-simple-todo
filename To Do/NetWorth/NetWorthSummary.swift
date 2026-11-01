import Foundation

/// The shape of `networth.json`, written into Compass's iCloud Documents folder by a
/// scheduled task on the Mac after each Portfolio Tracker refresh (twice a month).
/// Amounts are in ₹ crore, percentages are plain numbers (10.73 means 10.73%).
/// See docs/networth.md for the producer side and an example file.
nonisolated struct NetWorthSummary: Codable, Equatable {
    /// Statement date most positions are valued at, "yyyy-MM-dd".
    var asOf: String
    /// When the tracker refresh that produced this file ran, "yyyy-MM-dd".
    var refreshedAt: String
    var totals: Totals
    var allocation: [Slice]
    var segments: [Segment]
    var managers: [Manager]
    var decisions: [Decision]
    /// One point per refresh, oldest first, so the tab can draw the trend.
    var history: [Point]

    // Monthly read (optional; files written before 3.0 (21) don't have these).
    /// The statement month the scorecard describes, e.g. "September 2026".
    var period: String?
    /// Two or three sentences: how the month went against the market and what changed.
    var monthSummary: String?
    /// The equity benchmark managers are judged against for the month and year.
    var benchmark: Benchmark?
    /// Progress on a planned deployment of new money, if one is running.
    var deployment: Deployment?

    struct Benchmark: Codable, Equatable {
        var name: String
        var monthPct: Double?
        var oneYearPct: Double?
    }

    struct Deployment: Codable, Equatable {
        var title: String
        var targetCr: Double
        var items: [Item]

        struct Item: Codable, Equatable, Identifiable {
            var name: String
            var plannedCr: Double
            var doneCr: Double
            var id: String { name }
        }

        /// What has gone in so far; a manager can take more than planned (SageOne did).
        var doneCr: Double { items.reduce(0) { $0 + $1.doneCr } }
    }

    struct Totals: Codable, Equatable {
        var netInvestedCr: Double
        var fmvCr: Double
        var gainCr: Double
        var lifetimeGainPct: Double
        /// Headline blend on the invested book (excludes parked cash and at-cost holdings).
        var blendedIrrPct: Double
        var blendedIrrInclCashPct: Double?
        /// Equity book ahead (+) or behind (−) the same flows in the Nifty 500 fund.
        var vsNifty500Cr: Double?
    }

    struct Slice: Codable, Equatable, Identifiable {
        var name: String
        var pct: Double
        var id: String { name }
    }

    struct Segment: Codable, Equatable, Identifiable {
        var name: String
        var netInvestedCr: Double
        var fmvCr: Double
        var irrPct: Double?
        var note: String?
        var id: String { name }
    }

    struct Manager: Codable, Equatable, Identifiable {
        var name: String
        var type: String
        var fmvCr: Double
        var gainCr: Double
        var irrPct: Double?
        var vsNifty500Cr: Double?
        var asOf: String?
        /// Return for the statement month, to set against `benchmark.monthPct`.
        var monthPct: Double?
        var oneYearPct: Double?
        /// "strong" | "steady" | "watch" | "lagging" | "new" | "cash"
        var verdict: String?
        /// One line on why it has that verdict, with the numbers.
        var why: String?
        /// "Add" | "Hold" | "Reduce" | "Exit" | "Switch"
        var action: String?
        /// The tracker decision it relates to, e.g. "#5".
        var decisionRef: String?
        var id: String { name }

        var resolvedVerdict: Verdict {
            if let verdict, let known = Verdict(rawValue: verdict) { return known }
            // Older files: judge by the lead over the index fund where there is one.
            if let lead = vsNifty500Cr { return lead >= 0 ? .strong : .lagging }
            return .steady
        }
    }

    enum Verdict: String, CaseIterable {
        case strong, watch, lagging, steady, new, cash

        var title: String {
            switch self {
            case .strong:  "Doing well"
            case .watch:   "Watching"
            case .lagging: "Lagging"
            case .steady:  "Steady"
            case .new:     "Too early to judge"
            case .cash:    "Parked cash"
            }
        }
    }

    struct Decision: Codable, Equatable, Identifiable {
        var title: String
        var status: String
        var nextDate: String?
        /// "add" | "exit" | "fees" | "watch" | "admin"
        var kind: String?
        /// True when the tracker says this needs his call now (fired or due within 30 days).
        var needsDecision: Bool?
        var id: String { title }
    }

    struct Point: Codable, Equatable, Identifiable {
        var date: String
        var fmvCr: Double
        var netInvestedCr: Double?
        var id: String { date }
    }

    static func date(_ string: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: string)
    }
}
