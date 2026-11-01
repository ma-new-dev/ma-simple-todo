//
//  To_DoTests.swift
//  To DoTests
//
//  Created by Mukul Arora on 28/02/26.
//

import Foundation
import SwiftData
import Testing
@testable import To_Do

struct To_DoTests {

    @Test
    func taskCompletionStateChangesAsExpected() {
        let list = TodoList(name: "Work")
        let task = TaskItem(title: "Submit report", list: list)

        #expect(task.isCompleted == false)

        task.completedAt = .now
        #expect(task.isCompleted == true)

        task.completedAt = nil
        #expect(task.isCompleted == false)
    }

    @Test
    func contactInitialsHandlesOneTwoAndManyWordNames() {
        #expect(Contact(name: "").initials == "?")
        #expect(Contact(name: "Cher").initials == "C")
        #expect(Contact(name: "Mukul Arora").initials == "MA")
        #expect(Contact(name: "Jean  Luc  Picard").initials == "JP")
    }

    @Test
    func reconnectIsOverdueOnlyForPastDates() {
        let contact = Contact(name: "Priya")
        #expect(contact.isReconnectOverdue == false)

        contact.nextReconnect = Date().addingTimeInterval(-3600)
        #expect(contact.isReconnectOverdue == true)

        contact.nextReconnect = Date().addingTimeInterval(3600)
        #expect(contact.isReconnectOverdue == false)
    }

    @Test
    func locationDisplaySkipsMissingComponents() {
        #expect(Contact(name: "A", city: "Delhi", country: "India").locationDisplay == "Delhi, India")
        #expect(Contact(name: "B", city: "Delhi").locationDisplay == "Delhi")
        #expect(Contact(name: "C", country: "India").locationDisplay == "India")
        #expect(Contact(name: "D").locationDisplay == "")
    }

    @Test
    func priorityOrdersHighestFirst() {
        #expect(Priority.high < Priority.medium)
        #expect(Priority.medium < Priority.low)
        #expect([Priority.low, .high, .medium].sorted() == [.high, .medium, .low])
    }

    @Test
    func interactionsListIsNeverNil() {
        let contact = Contact(name: "Aakash")
        contact.interactions = nil
        #expect(contact.interactionsList.isEmpty)
    }

    @Test
    func catchUpQueueOrdersOverdueThenDueTodayThenNeglectedHighPriority() {
        let now = Date()
        let day: TimeInterval = 86_400

        let overdueOld = Contact(name: "Overdue old", nextReconnect: now.addingTimeInterval(-10 * day))
        let overdueNew = Contact(name: "Overdue new", nextReconnect: now.addingTimeInterval(-1 * day))
        let future = Contact(name: "Future", nextReconnect: now.addingTimeInterval(20 * day))
        let neglected = Contact(name: "Neglected", priority: .high, lastContacted: now.addingTimeInterval(-90 * day))
        let recentHigh = Contact(name: "Recent high", priority: .high, lastContacted: now.addingTimeInterval(-5 * day))
        let neglectedLow = Contact(name: "Neglected low", priority: .low, lastContacted: now.addingTimeInterval(-90 * day))

        let queue = ContactActions.catchUpQueue(
            from: [future, neglected, overdueNew, recentHigh, overdueOld, neglectedLow],
            now: now
        )
        #expect(queue.map(\.name) == ["Overdue old", "Overdue new", "Neglected"])
    }

    @Test @MainActor
    func contactsViewModelScopeFiltersOverdue() {
        let vm = ContactsViewModel()
        let overdue = Contact(name: "A", nextReconnect: Date().addingTimeInterval(-3600))
        let fine = Contact(name: "B")
        vm.scope = .overdue
        #expect(vm.filtered([overdue, fine]).map(\.name) == ["A"])
        vm.scope = .neverContacted
        #expect(vm.filtered([overdue, fine]).count == 2)
    }

    // MARK: - Food

    private func chosenMeal(_ name: String, day: Int, sources: [String], veg: [String] = [], gluten: Bool = false, protein: Double = 25) -> MealOption {
        let date = Calendar.current.date(byAdding: .day, value: day, to: Calendar.current.startOfDay(for: .now)) ?? .now
        let option = MealOption(date: date, slot: .lunch, sortOrder: 0, name: name, detail: "")
        option.proteinSources = sources
        option.vegetables = veg
        option.isGlutenMeal = gluten
        option.proteinGrams = protein
        option.decision = .chosen
        return option
    }

    @Test
    func weekBalanceCountsPaneerDaysNotMeals() {
        let meals = [
            chosenMeal("Palak paneer", day: 0, sources: ["paneer"]),
            chosenMeal("Paneer bhurji", day: 0, sources: ["paneer"]),
            chosenMeal("Matar paneer", day: -1, sources: ["Paneer"]),
            chosenMeal("Tofu stir-fry", day: -1, sources: ["tofu"], veg: ["Bhindi", "carrot"]),
            chosenMeal("Khapli roti and dal", day: -2, sources: ["moong"], veg: ["carrot"], gluten: true),
        ]
        let balance = WeekBalance(chosen: meals)
        #expect(balance.paneerDays == 2)
        #expect(balance.tofuMeals == 1)
        #expect(balance.glutenMeals == 1)
        #expect(balance.vegetables == ["bhindi", "carrot"])
        #expect(balance.mealsChosen == 5)
    }

    @Test
    func weekBalanceNudgesWhenPaneerCapReached() {
        let meals = (0..<3).map { chosenMeal("Paneer \($0)", day: -$0, sources: ["paneer"]) }
        let balance = WeekBalance(chosen: meals)
        #expect(balance.nudges.first?.contains("Paneer cap reached") == true)
    }

    @Test
    func weekBalanceIgnoresUnchosenOptions() {
        let liked = chosenMeal("Paneer tikka", day: 0, sources: ["paneer"])
        liked.decision = .liked
        #expect(WeekBalance(chosen: [liked]).paneerDays == 0)
    }

    @Test
    func dishKeyNormalisesPunctuationAndCase() {
        #expect(DishImage.key(for: "Moong Dal Chilla (with lauki)") == "moong-dal-chilla-with-lauki")
        #expect(DishImage.key(for: "moong dal  chilla, with LAUKI") == "moong-dal-chilla-with-lauki")
    }

    @Test @MainActor
    func tasteHistoryCollapsesRepeats() {
        #expect(FoodPlanService.counted(["Idli", "Upma", "Idli"]) == "Idli ×2; Upma")
    }

    @Test @MainActor
    func foodPlanIsBundled() {
        #expect(FoodPlanService.foodPlan.contains("Keep out"))
        #expect(FoodPlanService.foodPlan.contains("## Week 4"))
    }

    // MARK: - Net worth

    @Test
    func netWorthSummaryDecodesWithOptionalFieldsOmitted() throws {
        let json = """
        {"asOf":"2026-09-30","refreshedAt":"2026-10-18",
         "totals":{"netInvestedCr":100,"fmvCr":120,"gainCr":20,"lifetimeGainPct":20,"blendedIrrPct":11},
         "allocation":[{"name":"Equity","pct":100}],
         "segments":[{"name":"Equity","netInvestedCr":100,"fmvCr":120}],
         "managers":[{"name":"A","type":"PMS","fmvCr":120,"gainCr":20}],
         "decisions":[{"title":"#1","status":"open"}],
         "history":[{"date":"2026-10-18","fmvCr":120}]}
        """
        let summary = try JSONDecoder().decode(NetWorthSummary.self, from: Data(json.utf8))
        #expect(summary.totals.fmvCr == 120)
        #expect(summary.totals.vsNifty500Cr == nil)
        #expect(summary.managers.first?.irrPct == nil)
        #expect(NetWorthSummary.date(summary.asOf) != nil)
    }

    // MARK: - Upgrade backup

    @Test @MainActor
    func upgradeBackupIncludesTasksContactsAndInteractions() throws {
        let container = try ModelContainer(
            for: TodoList.self, TaskItem.self, Contact.self, Interaction.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = container.mainContext
        let list = TodoList(name: "Work")
        context.insert(list)
        context.insert(TaskItem(title: "Send memo", list: list))
        let contact = Contact(name: "Priya", tags: ["investor"])
        context.insert(contact)
        let interaction = Interaction(type: .call, notes: "Caught up")
        interaction.contact = contact
        context.insert(interaction)
        try context.save()

        let data = try UpgradeBackup.snapshot(in: context)
        let text = String(decoding: data, as: UTF8.self)
        #expect(text.contains("Send memo"))
        #expect(text.contains("Priya"))
        #expect(text.contains("Caught up"))
        #expect(!text.contains("photoData"))
    }

    // MARK: - Food, on-device version

    @Test @MainActor
    func catalogCoversEveryMeal() {
        let dishes = FoodCatalog.dishes
        #expect(dishes.count >= 80)
        for slot in MealSlot.allCases {
            #expect(dishes.filter { $0.slot == slot }.count >= 20)
        }
        #expect(Set(dishes.map(\.name)).count == dishes.count)
    }

    @Test @MainActor
    func catalogKeepsPrachisKeepOutList() {
        // "no chilli" / "no cashew" style notes are fine; the food itself is not.
        let banned = ["poha", "cashew", "maida", "naan", "baingan", "brinjal", "bell pepper", "capsicum",
                      "karela", "mushroom", "rava", "suji", "dosa", "chole", "chana", "lobia", "sattu",
                      "edamame", "soya", "papaya", "besan chilla", "kadhi"]
        for dish in FoodCatalog.dishes {
            let text = (dish.name + " " + dish.detail).lowercased()
                .replacingOccurrences(of: "no rava, no poha", with: "")
                .replacingOccurrences(of: "no cashew", with: "")
            for word in banned {
                #expect(!text.contains(word), "\(dish.name) mentions \(word)")
            }
            if dish.slot == .dinner {
                #expect(!dish.gluten, "\(dish.name): gluten belongs at lunch")
                #expect(!dish.name.lowercased().contains("omelette"), "\(dish.name): no omelette at dinner")
            }
        }
    }

    private func date(_ string: String) -> Date {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: string)!
    }

    @Test @MainActor
    func pickerKeepsTuesdayBreakfastEggFree() {
        // 2026-11-03 is a Tuesday.
        let picker = FoodPicker(dishes: FoodCatalog.dishes, date: date("2026-11-03"), slot: .breakfast,
                                history: [], week: WeekBalance(), shownToday: [])
        #expect(picker.weekday == 2)
        let picks = picker.pick(4)
        #expect(picks.count == 4)
        #expect(picks.allSatisfy { !$0.dish.hasEgg })
    }

    @Test @MainActor
    func pickerRespectsWeeklyCaps() {
        var week = WeekBalance()
        week.paneerDays = 3
        week.glutenMeals = 3
        week.rajmaMeals = 1
        let picker = FoodPicker(dishes: FoodCatalog.dishes, date: date("2026-11-05"), slot: .lunch,
                                history: [], week: week, shownToday: [])
        let allowed = picker.scored().map(\.dish)
        #expect(!allowed.isEmpty)
        #expect(allowed.allSatisfy { !$0.hasPaneer && !$0.gluten && !$0.hasRajma })
    }

    @Test @MainActor
    func pickerAvoidsRepeatsAndSkips() {
        let day = date("2026-11-05")
        let history = [
            FoodPicker.Past(name: "Lemon-pepper tofu with quinoa", date: date("2026-11-02"), decision: .chosen),
            FoodPicker.Past(name: "Bengali bhapa paneer with bhindi", date: date("2026-11-04"), decision: .skipped),
            FoodPicker.Past(name: "Bengali egg and pumpkin curry", date: date("2026-10-20"), decision: .chosen),
        ]
        let picker = FoodPicker(dishes: FoodCatalog.dishes, date: day, slot: .lunch,
                                history: history, week: WeekBalance(), shownToday: ["Khapli roti tofu wraps"])
        let names = Set(picker.scored().map(\.dish.name))
        #expect(!names.contains("Lemon-pepper tofu with quinoa"))      // eaten 3 days ago
        #expect(!names.contains("Bengali bhapa paneer with bhindi"))   // skipped yesterday
        #expect(!names.contains("Khapli roti tofu wraps"))             // already shown today
        #expect(names.contains("Bengali egg and pumpkin curry"))       // eaten over two weeks ago
    }

    @Test @MainActor
    func pickerSpreadsProteins() {
        let picker = FoodPicker(dishes: FoodCatalog.dishes, date: date("2026-11-06"), slot: .dinner,
                                history: [], week: WeekBalance(), shownToday: [])
        let picks = picker.pick(4)
        #expect(picks.count == 4)
        #expect(Set(picks.compactMap { $0.dish.proteins.first }).count >= 3)
        #expect(picks.allSatisfy { !$0.reason.isEmpty })
    }

    // MARK: - Health facts

    @MainActor
    private func sampleDays(now: Date, sleep: Double, need: Double, strainRecent: Double) -> [DailyMetric] {
        (0..<60).map { offset in
            let day = DailyMetric(date: Calendar.current.date(byAdding: .day, value: -offset, to: now)!)
            day.recovery = offset == 0 ? 72 : 55
            day.hrv = offset == 0 ? 56 : 48
            day.restingHR = 54
            day.sleepHours = sleep
            day.sleepNeedHours = need
            day.dayStrain = offset <= 7 ? strainRecent : 8
            return day
        }
    }

    @Test @MainActor
    func healthFactsMatchTheDashboardsComparisons() {
        let now = date("2026-11-05")
        let facts = HealthFacts(metrics: sampleDays(now: now, sleep: 6.8, need: 8.2, strainRecent: 12), workouts: [], now: now)
        #expect(facts.headline.hasPrefix("Recovery 72 (from 55)"))
        #expect(facts.goingWell.contains { $0.contains("green") })
        #expect(facts.goingWell.contains { $0.contains("HRV 56.0 ms") })
        #expect(facts.watch.contains { $0.contains("short") })
        #expect(facts.watch.contains { $0.contains("Load ratio") })
        #expect(facts.workOn.contains { $0.contains("22:15") })
    }

    @Test @MainActor
    func healthFactsRestOnRedAfterLoadDays() {
        let now = date("2026-11-05")
        let days = sampleDays(now: now, sleep: 7.8, need: 7.5, strainRecent: 14)
        days.first { Calendar.current.isDate($0.date, inSameDayAs: now) }?.recovery = 30
        let facts = HealthFacts(metrics: days, workouts: [], now: now)
        #expect(facts.watch.contains { $0.contains("in the red") })
        #expect(facts.workOn.first?.hasPrefix("Rest today") == true)
    }

    @Test @MainActor
    func writtenBriefCannotInventNumbers() {
        let facts = HealthFacts(headline: "Recovery 66 (from 51).", goingWell: ["Slept 8.3 h."],
                                watch: ["Sleep debt is 78 min."], workOn: ["Lights out by 22:30."])
        let invented = WrittenBrief(headline: "Recovery 66, best in 90 days.", goingWell: ["Slept 8.3 h, a great night."],
                                    watch: ["Debt 78 min."], workOn: ["Lights out by 22:30."])
        let accepted = HealthBriefService.accept(invented, against: facts)
        #expect(accepted.headline == facts.headline)           // 90 is not in the facts
        #expect(accepted.goingWell == ["Slept 8.3 h, a great night."])
        #expect(accepted.watch == ["Debt 78 min."])
    }
}
