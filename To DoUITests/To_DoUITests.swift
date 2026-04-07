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

    @MainActor
    func testCreateListAndCompleteThenMoveBackTask() throws {
        let app = XCUIApplication()
        app.launchArguments += ["UITEST_DISABLE_AUTH", "UITEST_IN_MEMORY_STORE"]
        app.launch()

        let newListRowTrigger = app.buttons["newListRowTrigger"]
        XCTAssertTrue(newListRowTrigger.waitForExistence(timeout: 5))
        newListRowTrigger.tap()

        let listNameField = app.textFields["newListInlineField"]
        XCTAssertTrue(listNameField.waitForExistence(timeout: 3))
        listNameField.tap()
        listNameField.typeText("Personal")

        app.buttons["Add"].firstMatch.tap()

        let newTaskRowTrigger = app.buttons["newTaskRowTrigger"]
        XCTAssertTrue(newTaskRowTrigger.waitForExistence(timeout: 3))
        newTaskRowTrigger.tap()

        let taskTitleField = app.textFields["newTaskInlineField"]
        XCTAssertTrue(taskTitleField.waitForExistence(timeout: 3))
        taskTitleField.tap()
        taskTitleField.typeText("Buy milk")

        app.buttons["Add"].firstMatch.tap()

        let taskLabel = app.staticTexts["Buy milk"]
        XCTAssertTrue(taskLabel.waitForExistence(timeout: 3))

        let markCompleteButton = app.buttons["markCompleteButton"].firstMatch
        XCTAssertTrue(markCompleteButton.waitForExistence(timeout: 3))
        markCompleteButton.tap()

        let confirmCompleteTaskButton = app.buttons["confirmCompleteTaskButton"]
        XCTAssertTrue(confirmCompleteTaskButton.waitForExistence(timeout: 3))
        confirmCompleteTaskButton.tap()

        let completedDisclosure = app.staticTexts["Completed"]
        XCTAssertTrue(completedDisclosure.waitForExistence(timeout: 3))
        completedDisclosure.tap()

        let moveBackButton = app.buttons["moveBackButton"].firstMatch
        XCTAssertTrue(moveBackButton.waitForExistence(timeout: 3))
        moveBackButton.tap()

        XCTAssertTrue(taskLabel.waitForExistence(timeout: 3))
    }
}
