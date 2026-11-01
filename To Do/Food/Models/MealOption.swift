import Foundation
import SwiftData

enum MealSlot: String, CaseIterable, Identifiable, Codable {
    case breakfast, lunch, dinner

    var id: String { rawValue }

    var title: String {
        switch self {
        case .breakfast: "Breakfast"
        case .lunch:     "Lunch"
        case .dinner:    "Dinner"
        }
    }

    var icon: String {
        switch self {
        case .breakfast: "sunrise.fill"
        case .lunch:     "sun.max.fill"
        case .dinner:    "moon.stars.fill"
        }
    }

    /// The slot worth showing first at this time of day.
    static func current(at date: Date = .now) -> MealSlot {
        switch Calendar.current.component(.hour, from: date) {
        case ..<11: .breakfast
        case ..<16: .lunch
        default:    .dinner
        }
    }
}

/// What he did with an option. Swipes write `liked`/`skipped`; "Having this" writes `chosen`.
enum MealDecision: String, Codable {
    case pending, liked, skipped, chosen
}

/// One suggested dish for one meal on one day.
///
/// Stored flat (one row per option) rather than as arrays on a day, so the week's balance
/// and his taste history are simple fetches. Tags come from the planner and are what the
/// balance rules count (paneer days, tofu meals, gluten meals, vegetables).
/// CloudKit rules: every property has a default; no unique constraints.
@Model
final class MealOption {
    /// Start of the day this option is for.
    var date: Date = Date.distantPast
    var slotRaw: String = MealSlot.breakfast.rawValue
    var sortOrder: Int = 0

    var name: String = ""
    var detail: String = ""
    var proteinGrams: Double = 0
    var vegetables: [String] = []
    var proteinSources: [String] = []
    var grains: [String] = []
    var isGlutenMeal: Bool = false
    /// One line on why it was offered today ("Prachi's pick for Thursday", "Adds tofu").
    var reason: String = ""

    var decisionRaw: String = MealDecision.pending.rawValue
    var decidedAt: Date?
    var createdAt: Date = Date.distantPast

    init(date: Date, slot: MealSlot, sortOrder: Int, name: String, detail: String) {
        self.date = Calendar.current.startOfDay(for: date)
        self.slotRaw = slot.rawValue
        self.sortOrder = sortOrder
        self.name = name
        self.detail = detail
        self.createdAt = .now
    }

    var slot: MealSlot {
        get { MealSlot(rawValue: slotRaw) ?? .breakfast }
        set { slotRaw = newValue.rawValue }
    }

    var decision: MealDecision {
        get { MealDecision(rawValue: decisionRaw) ?? .pending }
        set {
            decisionRaw = newValue.rawValue
            decidedAt = newValue == .pending ? nil : .now
        }
    }

    /// Normalised name used to share one photo across days.
    var dishKey: String { DishImage.key(for: name) }
}

/// A generated photo for a dish, made once and reused whenever the dish comes back.
@Model
final class DishImage {
    var dishKey: String = ""
    /// JPEG, downscaled to ~512 px so it stays well under CloudKit's record limits.
    @Attribute(.externalStorage) var imageData: Data?
    var createdAt: Date = Date.distantPast

    init(dishKey: String, imageData: Data?) {
        self.dishKey = dishKey
        self.imageData = imageData
        self.createdAt = .now
    }

    static func key(for name: String) -> String {
        name.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: "-")
    }
}
