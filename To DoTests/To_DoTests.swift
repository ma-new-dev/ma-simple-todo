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
}
