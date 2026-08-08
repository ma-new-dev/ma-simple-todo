//
//  To_DoUITestsLaunchTests.swift
//  To DoUITests
//
//  Created by Mukul Arora on 28/02/26.
//

import XCTest

/// Smoke test that the app launches in each UI configuration (portrait/landscape,
/// light/dark) and captures a screenshot of each.
final class To_DoUITestsLaunchTests: XCTestCase {

    override class var runsForEachTargetApplicationUIConfiguration: Bool {
        true
    }

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testLaunch() throws {
        let app = XCUIApplication()
        // Required, and easy to miss: a UI test's target app only sees arguments set here.
        // The scheme's test-action arguments apply to the host app for unit tests, not to
        // XCUIApplication. Without this the app opens its CloudKit-backed store, which
        // cannot initialize in an unsigned CI build and takes the process down.
        app.launchArguments += ["UITEST_IN_MEMORY_STORE"]
        app.launch()

        XCTAssertTrue(
            app.buttons["newListRowTrigger"].waitForExistence(timeout: 10),
            "The app should reach its task list on launch"
        )

        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Launch Screen"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
