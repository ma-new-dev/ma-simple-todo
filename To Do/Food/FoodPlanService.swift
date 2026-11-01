import Foundation
import FoundationModels
import SwiftData

/// Plans each day's breakfast, lunch and dinner options from Prachi's plan, and learns
/// from what he swipes and picks.
///
/// Everything runs on the phone and costs nothing. `FoodPicker` applies Prachi's rules to
/// the bundled dish catalog and ranks what's left by his last four weeks of swipes and
/// picks and this week's gaps; Apple's on-device model then keeps four of the top eight
/// and says why. Without Apple Intelligence the picker's own top four are shown.
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

    /// Offers fresh options for `slots`. Options he already liked or chose stay, skips
    /// stay as history, and nothing already shown today comes back.
    func generate(for date: Date, slots: [MealSlot], in context: ModelContext) async {
        guard !isGenerating else { return }
        isGenerating = true
        lastError = nil
        defer { isGenerating = false }

        let day = Calendar.current.startOfDay(for: date)
        let history = recentHistory(before: day, in: context)
        let week = weekBalance(for: day, in: context)

        for slot in slots {
            let existing = options(for: day, in: context).filter { $0.slot == slot }
            let picker = FoodPicker(
                dishes: FoodCatalog.dishes, date: day, slot: slot, history: history,
                week: week, shownToday: Set(existing.map(\.name))
            )
            let shortlist = Array(picker.scored().prefix(Self.shortlistSize))
            guard !shortlist.isEmpty else {
                lastError = "No more \(slot.title.lowercased()) options fit Prachi's rules today."
                continue
            }
            let fallback = picker.pick(Self.optionsPerSlot)
            let chosen = await chooseOnDevice(from: shortlist, slot: slot, history: history, week: week) ?? fallback

            for stale in existing where stale.decision == .pending {
                context.delete(stale)
            }
            let base = slotBase(slot) + existing.count
            for (index, pick) in chosen.enumerated() {
                let option = MealOption(date: day, slot: slot, sortOrder: base + index, name: pick.dish.name, detail: pick.dish.detail)
                option.proteinGrams = pick.dish.protein
                option.vegetables = pick.dish.vegetables
                option.proteinSources = pick.dish.proteins
                option.grains = pick.dish.grains
                option.isGlutenMeal = pick.dish.gluten
                option.reason = pick.reason
                context.insert(option)
            }
        }
        try? context.save()
    }

    /// The model sees this many of the picker's best and keeps four.
    static let shortlistSize = 8

    private func slotBase(_ slot: MealSlot) -> Int {
        (MealSlot.allCases.firstIndex(of: slot) ?? 0) * 100
    }

    private func recentHistory(before day: Date, in context: ModelContext) -> [FoodPicker.Past] {
        let cutoff = Calendar.current.date(byAdding: .day, value: -28, to: day) ?? day
        let pending = MealDecision.pending.rawValue
        let rows = (try? context.fetch(FetchDescriptor<MealOption>(
            predicate: #Predicate { $0.date >= cutoff && $0.date < day && $0.decisionRaw != pending }
        ))) ?? []
        return rows.map { FoodPicker.Past(name: $0.name, date: $0.date, decision: $0.decision) }
    }

    // MARK: - On-device choice

    /// Asks Apple's on-device model to keep four of the shortlist and say why in a line.
    /// Returns nil when the model is unavailable or its answer doesn't check out, and the
    /// picker's own order is used instead.
    private func chooseOnDevice(
        from shortlist: [FoodPicker.Scored], slot: MealSlot,
        history: [FoodPicker.Past], week: WeekBalance
    ) async -> [FoodPicker.Scored]? {
        guard OnDeviceModel.isAvailable, shortlist.count > Self.optionsPerSlot else { return nil }

        let liked = history.filter { $0.decision == .chosen || $0.decision == .liked }.map(\.name)
        let skipped = history.filter { $0.decision == .skipped }.map(\.name)
        let list = shortlist.enumerated().map { index, item in
            let tags = (item.dish.proteins + item.dish.vegetables + item.dish.grains).joined(separator: ", ")
            return "\(index + 1). \(item.dish.name) (\(tags); \(Int(item.dish.protein)) g protein)"
        }.joined(separator: "\n")

        let prompt = """
        Choose \(Self.optionsPerSlot) of these \(slot.title.lowercased()) dishes for today. All of \
        them already follow his dietitian's rules.
        \(list)

        He has enjoyed: \(liked.isEmpty ? "nothing recorded yet" : Self.counted(liked)).
        He skipped: \(skipped.isEmpty ? "nothing" : Self.counted(skipped)).
        This week: \(week.nudges.isEmpty ? "balanced so far" : week.nudges.joined(separator: " "))

        Prefer what he enjoys, avoid what he skipped, fill this week's gaps, and keep the \
        four different from each other (different protein or cuisine).
        """

        do {
            let session = LanguageModelSession(instructions: """
            You help one person choose home-cooked Indian vegetarian meals. Reply only with \
            dish numbers from the list and a short reason for each. Never mention medicine \
            or supplements.
            """)
            let response = try await session.respond(to: prompt, generating: MealChoice.self)
            var seen = Set<Int>()
            var result: [FoodPicker.Scored] = []
            for pick in response.content.picks {
                let index = pick.number - 1
                guard shortlist.indices.contains(index), seen.insert(index).inserted else { continue }
                var item = shortlist[index]
                let reason = pick.reason.trimmingCharacters(in: .whitespacesAndNewlines)
                if !reason.isEmpty, reason.count <= 90 { item.reason = reason }
                result.append(item)
            }
            guard result.count == Self.optionsPerSlot else { return nil }
            return result
        } catch {
            return nil
        }
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
}

@Generable
struct MealChoice {
    @Guide(description: "The chosen dishes", .count(4))
    var picks: [MealPick]
}

@Generable
struct MealPick {
    @Guide(description: "The dish's number from the list")
    var number: Int
    @Guide(description: "Why it suits today, under 12 words")
    var reason: String
}
