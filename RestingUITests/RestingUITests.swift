import XCTest

/// Drives the real app through every screen and control.
@MainActor
final class RestingUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() async throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launch()
    }

    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private var timeRemaining: XCUIElement {
        app.staticTexts["Time remaining"]
    }

    private func text(containing value: String) -> XCUIElement {
        app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", value)).firstMatch
    }

    func testPauseResumeEndAndReturnHome() throws {
        XCTAssertTrue(app.staticTexts["Resting"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["3 minutes"].isSelected, "3 minutes is selected by default")
        XCTAssertFalse(timeRemaining.exists, "No countdown on the welcome screen")

        app.buttons["5 minutes"].tap()
        XCTAssertTrue(app.buttons["5 minutes"].isSelected)
        XCTAssertFalse(app.buttons["3 minutes"].isSelected)
        capture("Welcome - 5 minutes selected")

        app.buttons["Begin Resting"].tap()
        XCTAssertTrue(timeRemaining.waitForExistence(timeout: 5))
        XCTAssertTrue(text(containing: "Breathe in").waitForExistence(timeout: 3))
        XCTAssertTrue(text(containing: "Slowly and gently").exists)

        let startValue = timeRemaining.value as? String ?? ""
        XCTAssertTrue(startValue == "5 minutes" || startValue.hasPrefix("4 minutes, 5"),
                      "Countdown starts at 5:00, got \(startValue)")
        XCTAssertTrue(text(containing: "Breathe out").waitForExistence(timeout: 6), "Instruction alternates to exhale")
        capture("Session - breathe out")

        app.buttons["Pause"].tap()
        XCTAssertTrue(app.buttons["Resume"].waitForExistence(timeout: 3))
        XCTAssertTrue(text(containing: "Paused").exists)
        let pausedValue = timeRemaining.value as? String
        sleep(3)
        XCTAssertEqual(timeRemaining.value as? String, pausedValue, "Countdown holds while paused")
        capture("Session - paused")

        app.buttons["Resume"].tap()
        XCTAssertTrue(app.buttons["Pause"].waitForExistence(timeout: 3))
        sleep(2)
        XCTAssertNotEqual(timeRemaining.value as? String, pausedValue, "Countdown continues after resume")

        app.buttons["End Session"].tap()
        XCTAssertTrue(app.staticTexts["Session Ended"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Rest Complete"].exists, "Ending early is not reported as complete")
        capture("Session ended early")

        app.buttons["Back to Home"].tap()
        XCTAssertTrue(app.buttons["Begin Resting"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["5 minutes"].isSelected, "Selected duration is remembered")
    }

    func testUnguidedSessionCompletesAndRestsAgain() throws {
        XCTAssertTrue(app.buttons["Begin Resting"].waitForExistence(timeout: 10))
        app.buttons["1 minute"].tap()
        let guide = app.switches.firstMatch
        XCTAssertEqual(guide.value as? String, "1")
        guide.tap()
        XCTAssertEqual(guide.value as? String, "0")
        capture("Welcome - 1 minute, no guide")

        app.buttons["Begin Resting"].tap()
        XCTAssertTrue(text(containing: "Rest quietly").waitForExistence(timeout: 5))
        XCTAssertFalse(text(containing: "Breathe in").exists)
        XCTAssertFalse(text(containing: "Breathe out").exists)
        capture("Session - unguided")

        XCTAssertFalse(app.staticTexts["Rest Complete"].exists)
        XCTAssertTrue(app.staticTexts["Rest Complete"].waitForExistence(timeout: 70), "Session completes at zero")
        capture("Rest complete")

        app.buttons["Rest Again"].tap()
        XCTAssertTrue(timeRemaining.waitForExistence(timeout: 5))
        let value = timeRemaining.value as? String ?? ""
        XCTAssertTrue(value == "1 minute" || value.hasSuffix("seconds"), "Fresh 1 minute session, got \(value)")
        XCTAssertTrue(text(containing: "Rest quietly").exists, "Breathing preference carried over")

        app.buttons["End Session"].tap()
        XCTAssertTrue(app.staticTexts["Session Ended"].waitForExistence(timeout: 5))
        app.buttons["Back to Home"].tap()
        XCTAssertTrue(app.buttons["Begin Resting"].waitForExistence(timeout: 5))
    }
}
