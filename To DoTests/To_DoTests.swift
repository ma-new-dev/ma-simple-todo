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
}
