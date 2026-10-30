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
        var id: String { name }
    }

    struct Decision: Codable, Equatable, Identifiable {
        var title: String
        var status: String
        var nextDate: String?
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
