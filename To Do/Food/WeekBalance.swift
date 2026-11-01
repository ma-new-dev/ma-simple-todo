import Foundation

/// Counts what he has actually chosen this week (Monday to Sunday) against Prachi's
/// balance rules. Shown on the Food tab and fed to the planner so the rest of the week
/// fills the gaps: fewer paneer days once the cap is near, more vegetables when the week
/// has been narrow, and so on.
struct WeekBalance: Equatable {
    var mealsChosen = 0
    var vegetables: Set<String> = []
    var paneerDays = 0
    var tofuMeals = 0
    var glutenMeals = 0
    var eggDays = 0
    var rajmaMeals = 0
    /// Chosen protein per day, keyed by start of day. Snacks aren't planned here, so the
    /// planner assumes the plan's ~15 g snack on top.
    var proteinByDay: [Date: Double] = [:]
    var dishesThisWeek: [String] = []

    // Prachi's caps and floors (FoodPlan.md, "Balance rules across a week").
    static let paneerDayCap = 3
    static let tofuMealRange = 3...4
    static let glutenMealRange = 2...3
    static let vegetableFloor = 5
    static let dailyProteinTarget = 90.0
    static let assumedSnackProtein = 15.0

    static func weekInterval(containing date: Date) -> DateInterval {
        var calendar = Calendar(identifier: .iso8601)
        calendar.timeZone = .current
        return calendar.dateInterval(of: .weekOfYear, for: date)
            ?? DateInterval(start: Calendar.current.startOfDay(for: date), duration: 7 * 86_400)
    }

    init() {}

    init(chosen options: [MealOption]) {
        var paneerDaySet = Set<Date>()
        var eggDaySet = Set<Date>()
        for option in options where option.decision == .chosen {
            mealsChosen += 1
            dishesThisWeek.append(option.name)
            vegetables.formUnion(option.vegetables.map { $0.lowercased() })
            let sources = Set(option.proteinSources.map { $0.lowercased() })
            if sources.contains("paneer") { paneerDaySet.insert(option.date) }
            if sources.contains("tofu") { tofuMeals += 1 }
            if sources.contains("egg") { eggDaySet.insert(option.date) }
            if sources.contains("rajma") { rajmaMeals += 1 }
            if option.isGlutenMeal { glutenMeals += 1 }
            proteinByDay[option.date, default: 0] += option.proteinGrams
        }
        paneerDays = paneerDaySet.count
        eggDays = eggDaySet.count
    }

    /// Plain-language notes for the planner and the Food tab, most important first.
    var nudges: [String] {
        var notes: [String] = []
        if paneerDays >= Self.paneerDayCap {
            notes.append("Paneer cap reached (\(paneerDays) of \(Self.paneerDayCap) days): no paneer for the rest of the week.")
        }
        if glutenMeals >= Self.glutenMealRange.upperBound {
            notes.append("Gluten meals at the weekly limit (\(glutenMeals)): keep the rest gluten-free.")
        }
        if tofuMeals < Self.tofuMealRange.lowerBound {
            notes.append("Tofu in \(tofuMeals) meals so far; the plan wants \(Self.tofuMealRange.lowerBound)-\(Self.tofuMealRange.upperBound) a week.")
        }
        if vegetables.count < Self.vegetableFloor {
            notes.append("\(vegetables.count) different vegetables so far; aim for at least \(Self.vegetableFloor) this week.")
        }
        if rajmaMeals > 0 {
            notes.append("Rajma already had this week: not again.")
        }
        return notes
    }

    /// Text block for the planner prompt.
    var promptSummary: String {
        var lines = [
            "THIS WEEK SO FAR (meals he chose, Monday onward): \(mealsChosen) meals.",
            "Dishes: " + (dishesThisWeek.isEmpty ? "none yet" : dishesThisWeek.joined(separator: "; ")),
            "Vegetables: " + (vegetables.isEmpty ? "none yet" : vegetables.sorted().joined(separator: ", ")),
            "Paneer days \(paneerDays)/\(Self.paneerDayCap) · tofu meals \(tofuMeals) (target \(Self.tofuMealRange.lowerBound)-\(Self.tofuMealRange.upperBound)) · gluten meals \(glutenMeals) (max \(Self.glutenMealRange.upperBound)) · egg days \(eggDays) · rajma \(rajmaMeals)",
        ]
        if !nudges.isEmpty {
            lines.append("Gaps to fill: " + nudges.joined(separator: " "))
        }
        return lines.joined(separator: "\n")
    }
}
