import Foundation
import SwiftData

/// Plans each day's breakfast, lunch and dinner options from Prachi's plan, and learns
/// from what he swipes and picks.
///
/// Learning is deliberately simple and visible: the planner sees which dishes he liked,
/// skipped and actually chose over the last four weeks, plus this week's balance against
/// Prachi's caps, and is told to lean toward the former and fill the latter's gaps.
@Observable
@MainActor
final class FoodPlanService {
    static let shared = FoodPlanService()

    static let optionsPerSlot = 4

    var isGenerating = false
    var lastError: String?

    // MARK: - Lookup

    func options(for date: Date, in context: ModelContext) -> [MealOption] {
        let day = Calendar.current.startOfDay(for: date)
        let descriptor = FetchDescriptor<MealOption>(
            predicate: #Predicate { $0.date == day },
            sortBy: [SortDescriptor(\.sortOrder)]
        )
        return (try? context.fetch(descriptor)) ?? []
    }

    func weekBalance(for date: Date, in context: ModelContext) -> WeekBalance {
        let week = WeekBalance.weekInterval(containing: date)
        let start = week.start
        let end = week.end
        let chosen = MealDecision.chosen.rawValue
        let descriptor = FetchDescriptor<MealOption>(
            predicate: #Predicate { $0.date >= start && $0.date < end && $0.decisionRaw == chosen }
        )
        return WeekBalance(chosen: (try? context.fetch(descriptor)) ?? [])
    }

    // MARK: - Decisions

    func decide(_ option: MealOption, _ decision: MealDecision, in context: ModelContext) {
        if decision == .chosen {
            // One choice per meal: a previous pick in the same slot falls back to liked.
            for other in options(for: option.date, in: context)
            where other.slot == option.slot && other.decision == .chosen && other !== option {
                other.decision = .liked
            }
        }
        option.decision = decision
        try? context.save()
    }

    // MARK: - Generation

    /// Generates the day's options if none exist yet.
    func ensurePlan(for date: Date, in context: ModelContext) async {
        guard options(for: date, in: context).isEmpty else { return }
        await generate(for: date, slots: MealSlot.allCases, in: context)
    }

    /// Replaces the undecided options for `slots` with fresh ones. Options he already
    /// liked or chose are kept, so a refresh never loses a pick.
    func generate(for date: Date, slots: [MealSlot], in context: ModelContext) async {
        guard !isGenerating else { return }
        isGenerating = true
        lastError = nil
        defer { isGenerating = false }

        do {
            let result = try await ClaudeClient.structured(
                PlanResult.self,
                system: Self.systemPrompt,
                user: buildContext(for: date, slots: slots, in: context),
                schema: PlanResult.schema(slots: slots),
                effort: "medium"
            )

            let existing = options(for: date, in: context)
            for slot in slots {
                for stale in existing where stale.slot == slot && (stale.decision == .pending || stale.decision == .skipped) {
                    context.delete(stale)
                }
                let kept = existing.filter { $0.slot == slot && ($0.decision == .liked || $0.decision == .chosen) }
                let base = slotBase(slot)
                for (index, dish) in result.dishes(for: slot).prefix(Self.optionsPerSlot).enumerated() {
                    let option = MealOption(
                        date: date, slot: slot, sortOrder: base + kept.count + index,
                        name: dish.name, detail: dish.detail
                    )
                    option.proteinGrams = dish.proteinG
                    option.vegetables = dish.vegetables
                    option.proteinSources = dish.proteinSources
                    option.grains = dish.grains
                    option.isGlutenMeal = dish.isGlutenMeal
                    context.insert(option)
                }
            }
            try context.save()
        } catch {
            lastError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func slotBase(_ slot: MealSlot) -> Int {
        (MealSlot.allCases.firstIndex(of: slot) ?? 0) * 100
    }

    // MARK: - Context

    private func buildContext(for date: Date, slots: [MealSlot], in context: ModelContext) -> String {
        let calendar = Calendar.current
        var lines: [String] = []
        lines.append("PLANNING FOR: \(date.formatted(.dateTime.weekday(.wide).day().month(.wide))).")
        lines.append("Meals to plan: " + slots.map(\.title).joined(separator: ", ") + ".")
        if calendar.component(.weekday, from: date) == 3 {
            lines.append("It is Tuesday: no-egg day.")
        }
        let planWeek = (calendar.component(.weekOfYear, from: date) % 4) + 1
        lines.append("This week's Prachi week to lean on (for its 4 core vegetables): Week \(planWeek). Other weeks' dishes are fine too.")

        // Taste history: last 28 days of decisions.
        let cutoff = calendar.date(byAdding: .day, value: -28, to: calendar.startOfDay(for: date)) ?? date
        let today = calendar.startOfDay(for: date)
        let pending = MealDecision.pending.rawValue
        let history = (try? context.fetch(FetchDescriptor<MealOption>(
            predicate: #Predicate { $0.date >= cutoff && $0.date < today && $0.decisionRaw != pending },
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        ))) ?? []

        let chosen = history.filter { $0.decision == .chosen }.map(\.name)
        let liked = history.filter { $0.decision == .liked }.map(\.name)
        let skipped = history.filter { $0.decision == .skipped }.map(\.name)
        lines.append("\nHIS TASTE, last 4 weeks:")
        lines.append("Chose and ate: " + (chosen.isEmpty ? "nothing recorded yet" : Self.counted(chosen)))
        lines.append("Swiped right (liked): " + (liked.isEmpty ? "nothing yet" : Self.counted(liked)))
        lines.append("Swiped left (skipped): " + (skipped.isEmpty ? "nothing yet" : Self.counted(skipped)))

        let yesterday = calendar.date(byAdding: .day, value: -1, to: today) ?? today
        let yesterdayChosen = history.filter { $0.date == yesterday && $0.decision == .chosen }.map(\.name)
        if !yesterdayChosen.isEmpty {
            lines.append("Yesterday he ate: " + yesterdayChosen.joined(separator: "; ") + ". Don't repeat these today.")
        }

        // Already decided today (kept through a refresh).
        let keptToday = options(for: date, in: context).filter { $0.decision == .chosen || $0.decision == .liked }
        if !keptToday.isEmpty {
            lines.append("Already on today's shortlist (don't duplicate): " + keptToday.map(\.name).joined(separator: "; "))
        }

        lines.append("\n" + weekBalance(for: date, in: context).promptSummary)
        lines.append("\nPRACHI'S PLAN AND HIS PREFERENCES:\n" + Self.foodPlan)
        lines.append("""

        Give exactly \(Self.optionsPerSlot) options for each meal requested. Make the options \
        genuinely different from each other (different protein, grain or cuisine), not one \
        dish with a garnish swapped. Lean toward what he chose or liked, avoid what he \
        skipped, and use this week's gaps to decide what to offer. Prefer Prachi's dishes; \
        new dishes are welcome when they obey every rule and add variety he has asked for.
        """)
        return lines.joined(separator: "\n")
    }

    /// "Moong chilla ×3; Lemon rice" — repeats collapsed so frequency is visible.
    static func counted(_ names: [String]) -> String {
        var order: [String] = []
        var counts: [String: Int] = [:]
        for name in names {
            if counts[name] == nil { order.append(name) }
            counts[name, default: 0] += 1
        }
        return order.map { counts[$0, default: 1] > 1 ? "\($0) ×\(counts[$0, default: 1])" : $0 }
            .joined(separator: "; ")
    }

    /// The bundled plan. Replace FoodPlan.md when Prachi sends a new one.
    static let foodPlan: String = {
        guard let url = Bundle.main.url(forResource: "FoodPlan", withExtension: "md"),
              let text = try? String(contentsOf: url, encoding: .utf8)
        else { return "(FoodPlan.md missing from the app bundle)" }
        return text
    }()

    // MARK: - Prompt

    static let systemPrompt = """
    You plan one day's home meals for Mukul, 42, vegetarian plus eggs, in Gurgaon/Delhi. \
    His kitchen staff cook what he picks, so every option must be a real, named dish an \
    Indian home kitchen can make the same day, with the portion cues Prachi uses.

    Prachi's rules in the plan you are given are hard constraints: never suggest anything \
    on the keep-out list, respect every cap, and keep dinners light with the ½ cup \
    reheated rice. His stated preferences come next. Within those, your job is to make \
    the week enjoyable and balanced: he finds weekday food dull, so vary cuisine and \
    flavour (Bengali, South Indian, Gujarati, Asian-style tofu, a good tadka or chutney).

    For each dish give: name (short, what he'd tell the cook), detail (one line: the \
    components and portions), protein_g (your estimate for the whole meal, using the \
    plan's protein numbers), vegetables, protein_sources and grains as short lowercase \
    words (e.g. "lauki", "tofu", "egg", "paneer", "moong", "jowar", "rice"), and \
    is_gluten_meal (true only for wheat rotis, khapli atta or whole-wheat sourdough \
    beyond a single breakfast slice).

    Plan food only. No supplement, medical or dosing advice.
    """

    // MARK: - Wire

    struct Dish: Decodable {
        let name: String
        let detail: String
        let proteinG: Double
        let vegetables: [String]
        let proteinSources: [String]
        let grains: [String]
        let isGlutenMeal: Bool

        enum CodingKeys: String, CodingKey {
            case name, detail, vegetables, grains
            case proteinG = "protein_g"
            case proteinSources = "protein_sources"
            case isGlutenMeal = "is_gluten_meal"
        }
    }

    struct PlanResult: Decodable {
        var breakfast: [Dish]?
        var lunch: [Dish]?
        var dinner: [Dish]?

        func dishes(for slot: MealSlot) -> [Dish] {
            switch slot {
            case .breakfast: breakfast ?? []
            case .lunch:     lunch ?? []
            case .dinner:    dinner ?? []
            }
        }

        static func schema(slots: [MealSlot]) -> [String: Any] {
            let strings: [String: Any] = ["type": "array", "items": ["type": "string"]]
            let dish: [String: Any] = [
                "type": "object",
                "properties": [
                    "name": ["type": "string"],
                    "detail": ["type": "string"],
                    "protein_g": ["type": "number"],
                    "vegetables": strings,
                    "protein_sources": strings,
                    "grains": strings,
                    "is_gluten_meal": ["type": "boolean"],
                ],
                "required": ["name", "detail", "protein_g", "vegetables", "protein_sources", "grains", "is_gluten_meal"],
                "additionalProperties": false,
            ]
            var properties: [String: Any] = [:]
            for slot in slots {
                properties[slot.rawValue] = ["type": "array", "items": dish]
            }
            return [
                "type": "object",
                "properties": properties,
                "required": slots.map(\.rawValue),
                "additionalProperties": false,
            ]
        }
    }
}
