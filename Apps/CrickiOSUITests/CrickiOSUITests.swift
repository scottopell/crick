import XCTest

final class CrickiOSUITests: XCTestCase {
    func testInteractiveCreekAndRecovery() {
        let app = XCUIApplication()
        app.launchEnvironment["CRICK_UI_TEST_RESET"] = "1"
        app.launch()

        let guide = app.descendants(matching: .any)
            .matching(identifier: "first-use-guide").firstMatch
        XCTAssertTrue(guide.waitForExistence(timeout: 5))
        XCTAssertTrue(guide.label.contains("tap a plus"))
        XCTAssertTrue(app.buttons["advance-one"].isHittable)
        XCTAssertTrue(app.buttons["advance-ten"].isHittable)
        XCTAssertFalse(app.buttons["resume-snapshot"].isEnabled)

        let tick = app.staticTexts["tick-value"]
        XCTAssertTrue(tick.waitForExistence(timeout: 5))
        XCTAssertEqual(tick.label, "Tick 0")

        let creekCell = app.buttons["creek-cell-2"]
        XCTAssertTrue(creekCell.isHittable)
        creekCell.tap()
        XCTAssertTrue(creekCell.label.contains("rock resistance 0.800"))
        XCTAssertEqual(tick.label, "Tick 0")

        let advanceTen = app.buttons["advance-ten"]
        scrollToElement(advanceTen, in: app)
        advanceTen.tap()
        XCTAssertEqual(tick.label, "Tick 10")
        let effectCard = app.descendants(matching: .any)
            .matching(identifier: "rock-effect-card").firstMatch
        scrollToElement(effectCard, in: app)
        XCTAssertTrue(effectCard.label.contains("Observed around selected rock over 10 fixed ticks"))
        XCTAssertTrue(effectCard.label.contains("Upstream-side depth change"))

        let save = app.buttons["save-snapshot"]
        scrollToElement(save, in: app)
        save.tap()
        XCTAssertTrue(app.staticTexts["session-message"].label.contains("Saved tick 10"))

        let advance = app.buttons["advance-one"]
        scrollToElement(advance, in: app, direction: .down)
        advance.tap()
        XCTAssertEqual(tick.label, "Tick 11")

        let resume = app.buttons["resume-snapshot"]
        scrollToElement(resume, in: app)
        resume.tap()
        XCTAssertTrue(app.staticTexts["session-message"].label.contains("Resumed tick 10"))
        scrollToElement(tick, in: app, direction: .down)
        XCTAssertEqual(tick.label, "Tick 10")
    }

    private enum ScrollDirection { case up, down }

    private func scrollToElement(
        _ element: XCUIElement,
        in app: XCUIApplication,
        direction: ScrollDirection = .up
    ) {
        for _ in 0..<5 where !element.isHittable {
            switch direction {
            case .up: app.swipeUp()
            case .down: app.swipeDown()
            }
        }
        XCTAssertTrue(element.isHittable)
    }
}
