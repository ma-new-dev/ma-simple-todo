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
}
