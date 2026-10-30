//
//  To_DoTests.swift
//  To DoTests
//
//  Created by Mukul Arora on 28/02/26.
//

import Foundation
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
}
