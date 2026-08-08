//
//  To_DoUITests.swift
//  To DoUITests
//
//  Created by Mukul Arora on 28/02/26.
//

import XCTest

final class To_DoUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func launchApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["UITEST_IN_MEMORY_STORE"]
        app.launch()
        return app
    }

    /// Creates a list, opens it, and adds a task. Returns the running app.
    @discardableResult
    private func createListWithTask(
        _ app: XCUIApplication,
        listName: String,
        taskTitle: String
    ) -> XCUIApplication {
        let newListRowTrigger = app.buttons["newListRowTrigger"]
        XCTAssertTrue(newListRowTrigger.waitForExistence(timeout: 10))
        newListRowTrigger.tap()

        let listNameField = app.textFields["newListInlineField"]
        XCTAssertTrue(listNameField.waitForExistence(timeout: 3))
        listNameField.tap()
        listNameField.typeText(listName)

        app.buttons["Add"].firstMatch.tap()

        // On iPhone the split view collapses to a stack, so the list must be opened before
        // its detail pane appears. On iPad the detail is already visible and the tap is a
        // no-op selection.
        let listCell = app.staticTexts[listName]
        XCTAssertTrue(listCell.waitForExistence(timeout: 3))
        listCell.tap()

        let newTaskRowTrigger = app.buttons["newTaskRowTrigger"]
        XCTAssertTrue(newTaskRowTrigger.waitForExistence(timeout: 5))
        newTaskRowTrigger.tap()

        let taskTitleField = app.textFields["newTaskInlineField"]
        XCTAssertTrue(taskTitleField.waitForExistence(timeout: 3))
        taskTitleField.tap()
        taskTitleField.typeText(taskTitle)

        app.buttons["Add"].firstMatch.tap()

        XCTAssertTrue(app.staticTexts[taskTitle].waitForExistence(timeout: 3))
        return app
    }

    /// Completing is a single tap now — no confirmation dialog — and the completed task
    /// moves out of the active section.
    @MainActor
    func testCompletingATaskTakesOneTap() throws {
        let app = launchApp()
        createListWithTask(app, listName: "Personal", taskTitle: "Buy milk")

        let markCompleteButton = app.buttons["markCompleteButton"].firstMatch
        XCTAssertTrue(markCompleteButton.waitForExistence(timeout: 3))
        markCompleteButton.tap()

        // The old flow required confirming an alert; nothing should intercept the tap.
        XCTAssertFalse(
            app.buttons["confirmCompleteTaskButton"].waitForExistence(timeout: 1),
            "Completing a task should not present a confirmation dialog"
        )

        let undoButton = app.buttons["undoCompleteButton"]
        XCTAssertTrue(undoButton.waitForExistence(timeout: 3), "An Undo affordance should appear")
    }

    /// The Undo bar restores the task to the active section.
    @MainActor
    func testUndoRestoresACompletedTask() throws {
        let app = launchApp()
        createListWithTask(app, listName: "Personal", taskTitle: "Buy milk")

        app.buttons["markCompleteButton"].firstMatch.tap()

        let undoButton = app.buttons["undoCompleteButton"]
        XCTAssertTrue(undoButton.waitForExistence(timeout: 3))
        undoButton.tap()

        // Back to active: the incomplete-circle button returns and Undo goes away.
        XCTAssertTrue(app.buttons["markCompleteButton"].firstMatch.waitForExistence(timeout: 3))
        XCTAssertFalse(undoButton.waitForExistence(timeout: 1))
    }

    /// A completed task can still be moved back from the Completed section.
    @MainActor
    func testMoveCompletedTaskBackToActive() throws {
        let app = launchApp()
        createListWithTask(app, listName: "Personal", taskTitle: "Buy milk")

        app.buttons["markCompleteButton"].firstMatch.tap()

        let completedDisclosure = app.staticTexts["Completed"]
        XCTAssertTrue(completedDisclosure.waitForExistence(timeout: 3))
        completedDisclosure.tap()

        let moveBackButton = app.buttons["moveBackButton"].firstMatch
        XCTAssertTrue(moveBackButton.waitForExistence(timeout: 3))
        moveBackButton.tap()

        XCTAssertTrue(app.staticTexts["Buy milk"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["markCompleteButton"].firstMatch.waitForExistence(timeout: 3))
    }

    /// Tapping a list opens it rather than starting a rename, which the old
    /// tap-to-rename gesture used to intercept.
    @MainActor
    func testTappingAListOpensItRatherThanRenamingIt() throws {
        let app = launchApp()

        let newListRowTrigger = app.buttons["newListRowTrigger"]
        XCTAssertTrue(newListRowTrigger.waitForExistence(timeout: 10))
        newListRowTrigger.tap()

        let listNameField = app.textFields["newListInlineField"]
        XCTAssertTrue(listNameField.waitForExistence(timeout: 3))
        listNameField.tap()
        listNameField.typeText("Work")
        app.buttons["Add"].firstMatch.tap()

        let listCell = app.staticTexts["Work"]
        XCTAssertTrue(listCell.waitForExistence(timeout: 3))
        listCell.tap()

        // Opening the list shows its task entry point; a rename sheet would not.
        XCTAssertTrue(app.buttons["newTaskRowTrigger"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.textFields["renameField"].exists)
    }

    /// Reordering needs an Edit button; previously .onMove was wired up with no affordance.
    @MainActor
    func testListsHaveAnEditButtonForReordering() throws {
        let app = launchApp()
        XCTAssertTrue(app.buttons["newListRowTrigger"].waitForExistence(timeout: 10))
        XCTAssertTrue(
            app.buttons["editListsButton"].waitForExistence(timeout: 3),
            "Lists should expose an Edit button so the existing reordering is reachable"
        )
    }

    /// The app opens straight into the task list — there is no sign-in gate.
    @MainActor
    func testAppOpensWithoutASignInGate() throws {
        let app = launchApp()

        XCTAssertTrue(app.buttons["newListRowTrigger"].waitForExistence(timeout: 10))
        XCTAssertFalse(
            app.buttons["appleSignInButton"].exists,
            "Sign in with Apple has been removed; the app should open directly"
        )
    }
}
