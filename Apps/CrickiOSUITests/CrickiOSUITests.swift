import XCTest

final class CrickiOSUITests: XCTestCase {
    func testExplicitControlsAndRecovery() {
        let app = XCUIApplication()
        app.launch()

        let tick = app.staticTexts["tick-value"]
        XCTAssertTrue(tick.waitForExistence(timeout: 5))
        XCTAssertEqual(tick.label, "Tick, 0")

        app.buttons["advance-one"].tap()
        XCTAssertEqual(tick.label, "Tick, 1")

        app.buttons["place-rock"].tap()
        XCTAssertEqual(tick.label, "Tick, 1")

        let save = app.buttons["save-snapshot"]
        scrollToElement(save, in: app)
        save.tap()
        XCTAssertTrue(app.staticTexts["session-message"].label.contains("Saved tick 1"))

        let advance = app.buttons["advance-one"]
        scrollToElement(advance, in: app, direction: .down)
        advance.tap()
        XCTAssertEqual(tick.label, "Tick, 2")

        let resume = app.buttons["resume-snapshot"]
        scrollToElement(resume, in: app)
        resume.tap()
        XCTAssertTrue(app.staticTexts["session-message"].label.contains("Resumed tick 1"))
        scrollToElement(tick, in: app, direction: .down)
        XCTAssertEqual(tick.label, "Tick, 1")
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
