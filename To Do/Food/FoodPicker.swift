import Foundation

/// One dish from Prachi's plan (or one of his named favourites), tagged so the week's
/// balance rules can be checked in code. Loaded from the bundled FoodCatalog.json.
struct CatalogDish: Codable, Equatable, Identifiable {
    var name: String
    var slot: MealSlot
    /// Where it sits in the 4-week grid, as "week-weekday" with Monday = 1.
    var plan: [String]
    var detail: String
    var protein: Double
    var vegetables: [String]
    var proteins: [String]
    var grains: [String]
    var gluten: Bool
    var favourite: Bool?

    var id: String { name }
    var hasEgg: Bool { proteins.contains("egg") }
    var hasPaneer: Bool { proteins.contains("paneer") }
    var hasTofu: Bool { proteins.contains("tofu") }
    var hasRajma: Bool { proteins.contains("rajma") }

    func isPlanned(week: Int) -> Bool { plan.contains { $0.hasPrefix("\(week)-") } }
    func isPlanned(week: Int, weekday: Int) -> Bool { plan.contains("\(week)-\(weekday)") }
}

enum FoodCatalog {
    private struct File: Decodable { let dishes: [CatalogDish] }

    static let dishes: [CatalogDish] = {
        guard let url = Bundle.main.url(forResource: "FoodCatalog", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let file = try? JSONDecoder().decode(File.self, from: data)
        else { return [] }
        return file.dishes
    }()
}

/// Chooses each meal's candidates from the catalog. Prachi's rules are hard filters;
/// his history and this week's gaps only change the order. Pure, so it is tested
/// directly; the on-device model only chooses among what this returns.
struct FoodPicker {
    /// A past option and what he did with it.
    struct Past: Equatable {
        var name: String
        var date: Date
        var decision: MealDecision
    }

    struct Scored: Equatable {
        var dish: CatalogDish
        var score: Double
        /// The strongest reason it ranked well, shown on the card when the on-device
        /// model is unavailable.
        var reason: String
    }

    var dishes: [CatalogDish]
    var date: Date
    var slot: MealSlot
    var history: [Past]
    var week: WeekBalance
    /// Every dish already shown today for this meal, whatever he did with it.
    var shownToday: Set<String>
    var calendar = Calendar.current

    /// Prachi's 4-week cycle, matched to the calendar so a given week always lands on
    /// the same plan week.
    var planWeek: Int { Self.planWeek(for: date, calendar: calendar) }
    /// Monday = 1 ... Sunday = 7.
    var weekday: Int { Self.weekday(for: date, calendar: calendar) }

    static func planWeek(for date: Date, calendar: Calendar = .current) -> Int {
        (calendar.component(.weekOfYear, from: date) % 4) + 1
    }

    static func weekday(for date: Date, calendar: Calendar = .current) -> Int {
        (calendar.component(.weekday, from: date) + 5) % 7 + 1
    }

    // MARK: - Rules

    func isAllowed(_ dish: CatalogDish) -> Bool {
        guard dish.slot == slot, !shownToday.contains(dish.name) else { return false }
        let today = calendar.startOfDay(for: date)

        // His rule: Tuesday breakfast has no egg.
        if slot == .breakfast, weekday == 2, dish.hasEgg { return false }
        // Prachi's caps for the week.
        if dish.hasPaneer, week.paneerDays >= WeekBalance.paneerDayCap { return false }
        if dish.gluten, week.glutenMeals >= WeekBalance.glutenMealRange.upperBound { return false }
        if dish.hasRajma {
            let rajmaLately = history.filter { $0.decision == .chosen && name($0.name, contains: "rajma") }.count
            if week.rajmaMeals > 0 || rajmaLately >= 2 { return false }
        }

        for past in history where past.name == dish.name {
            let daysAgo = calendar.dateComponents([.day], from: calendar.startOfDay(for: past.date), to: today).day ?? 99
            switch past.decision {
            case .chosen:
                // No lunch or dinner repeat within a week; breakfast just not two days running.
                if slot == .breakfast ? daysAgo <= 1 : daysAgo < 7 { return false }
            case .skipped:
                if daysAgo < 7 { return false }
            case .liked, .pending:
                break
            }
        }
        return true
    }

    // MARK: - Ranking

    func scored() -> [Scored] {
        dishes.filter(isAllowed).map(score).sorted {
            $0.score != $1.score ? $0.score > $1.score : $0.dish.name < $1.dish.name
        }
    }

    /// The top `count`, spread across proteins and grains so four cards aren't one dish
    /// four ways.
    func pick(_ count: Int) -> [Scored] {
        var pool = scored()
        var picked: [Scored] = []
        while picked.count < count, !pool.isEmpty {
            let adjusted = pool.enumerated().map { index, candidate -> (Int, Double) in
                var value = candidate.score
                for chosen in picked {
                    if candidate.dish.proteins.first == chosen.dish.proteins.first { value -= 3 }
                    if !candidate.dish.grains.isEmpty, candidate.dish.grains.first == chosen.dish.grains.first { value -= 1.5 }
                }
                return (index, value)
            }
            guard let best = adjusted.max(by: { $0.1 < $1.1 }) else { break }
            picked.append(pool.remove(at: best.0))
        }
        return picked
    }

    private func score(_ dish: CatalogDish) -> Scored {
        var total = 0.0
        var reasons: [(Double, String)] = []
        func add(_ points: Double, _ reason: String) {
            total += points
            reasons.append((points, reason))
        }

        if dish.isPlanned(week: planWeek, weekday: weekday) {
            add(5, "Prachi's pick for \(weekdayName) this week")
        } else if dish.isPlanned(week: planWeek) {
            add(3, "From Prachi's Week \(planWeek) plan")
        } else if dish.favourite == true {
            add(2, "One of your favourites")
        }

        let mine = history.filter { $0.name == dish.name }
        let chosen = mine.filter { $0.decision == .chosen }.count
        let liked = mine.filter { $0.decision == .liked }.count
        let skipped = mine.filter { $0.decision == .skipped }.count
        if chosen > 0 { add(min(Double(chosen) * 2, 4), "You've had this \(chosen == 1 ? "once" : "\(chosen) times") lately") }
        if liked > 0 { add(min(Double(liked), 2), "You liked this before") }
        if skipped > 0 { total -= Double(skipped) * 2 }

        let newVeg = dish.vegetables.filter { !week.vegetables.contains($0) }
        if week.vegetables.count < WeekBalance.vegetableFloor, let first = newVeg.first {
            add(2, "Adds \(first), new this week")
        }
        if dish.hasTofu, week.tofuMeals < WeekBalance.tofuMealRange.lowerBound {
            add(2, "Tofu: \(week.tofuMeals) of \(WeekBalance.tofuMealRange.lowerBound)-\(WeekBalance.tofuMealRange.upperBound) meals so far")
        }
        let target: Double = slot == .lunch ? 30 : 25
        if dish.protein >= target { add(1, "\(Int(dish.protein)) g protein") }

        // A stable nudge so equal scores don't show the same order every day.
        total += Double(Self.stableHash("\(dish.name)|\(calendar.startOfDay(for: date).timeIntervalSince1970)") % 100) / 100

        let reason = reasons.max { $0.0 < $1.0 }?.1 ?? "Fits Prachi's rules for today"
        return Scored(dish: dish, score: total, reason: reason)
    }

    private var weekdayName: String {
        ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"][weekday - 1]
    }

    private func name(_ name: String, contains word: String) -> Bool {
        name.lowercased().contains(word)
    }

    /// djb2; Swift's `hashValue` changes every launch.
    static func stableHash(_ string: String) -> UInt64 {
        string.utf8.reduce(5381) { ($0 &<< 5) &+ $0 &+ UInt64($1) }
    }
}

/// Lines read straight from Prachi's plan text (FoodPlan.md) that the catalog doesn't
/// model: the day's 3:45 snack and the after-exercise guidance.
enum PlanText {
    /// The snack line for a plan week (1-4) and weekday (Monday = 1), e.g. "150 g Greek
    /// yogurt + 1 kiwi + 1 tbsp pumpkin seeds".
    static func snack(in plan: String, week: Int, weekday: Int) -> String? {
        let day = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"][max(1, min(7, weekday)) - 1]
        guard let weekStart = plan.range(of: "## Week \(week)\n") else { return nil }
        let rest = plan[weekStart.upperBound...]
        let weekText = rest.range(of: "\n## Week ").map { rest[..<$0.lowerBound] } ?? rest
        guard let snackStart = weekText.range(of: "### Snack\n") else { return nil }
        for line in weekText[snackStart.upperBound...].split(separator: "\n") {
            if line.hasPrefix("###") { break }
            if line.hasPrefix("- \(day): ") { return String(line.dropFirst(day.count + 4)) }
        }
        return nil
    }

    /// The "After exercise" paragraph, without its heading.
    static func afterExercise(in plan: String) -> String? {
        guard let start = plan.range(of: "## After exercise\n") else { return nil }
        let rest = plan[start.upperBound...]
        let text = rest.range(of: "\n## ").map { rest[..<$0.lowerBound] } ?? rest
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
