import XCTest

@MainActor
final class CrickiOSUITests: XCTestCase {
    // Shape the Bend (2–4): exercise the asynchronous presentation and explicit
    // retry/keep closure through the accessibility-facing UI.
    func testShapeTheBendAsyncJourney() {
        let app = XCUIApplication()
        app.launchEnvironment["CRICK_UI_TEST_RESET"] = "1"
        app.launch()

        let scene = app.otherElements["creek-scene"]
        XCTAssertTrue(scene.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["placement-prompt"].exists)
        attachScreenshot(named: "Shape the Bend — flowing baseline")

        let menu = app.buttons["choose-stone-position"]
        menu.tap()
        XCTAssertFalse(app.buttons["place-stone-5"].exists)
        app.buttons["place-stone-4"].tap()
        XCTAssertTrue(app.staticTexts["stone-set"].waitForExistence(timeout: 2))

        menu.tap()
        XCTAssertFalse(app.buttons["place-stone-4"].exists)
        app.tap()

        let waterWork = app.buttons["let-water-work"]
        XCTAssertTrue(waterWork.isEnabled)
        waterWork.tap()
        XCTAssertTrue(app.staticTexts["water-playing"].waitForExistence(timeout: 1))
        XCTAssertTrue(app.staticTexts["water-playing"].label.contains("of 20"))
        XCTAssertTrue(app.staticTexts["result-copy"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["result-copy"].label.contains("current is still quick"))
        attachScreenshot(named: "Shape the Bend — first outcome")
        XCTAssertTrue(app.buttons["try-another-spot"].exists)
        XCTAssertFalse(app.buttons["keep-creek"].exists)

        app.buttons["try-another-spot"].tap()
        XCTAssertTrue(app.staticTexts["move-stone-prompt"].waitForExistence(timeout: 2))
        XCTAssertFalse(waterWork.isEnabled)

        menu.tap()
        app.buttons["place-stone-3"].tap()
        waterWork.tap()
        XCTAssertTrue(app.staticTexts["water-playing"].waitForExistence(timeout: 1))
        XCTAssertTrue(app.staticTexts["water-playing"].label.contains("of 20"))
        XCUIDevice.shared.press(.home)
        app.activate()
        XCTAssertTrue(app.staticTexts["result-copy"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.staticTexts["result-copy"].label.contains("deep, calm pool"))
        attachScreenshot(named: "Shape the Bend — successful pool")
        app.buttons["keep-creek"].tap()
        XCTAssertTrue(app.staticTexts["creek-kept"].waitForExistence(timeout: 2))
        XCTAssertFalse(app.buttons["let-water-work"].exists)
        XCTAssertFalse(app.buttons["choose-stone-position"].exists)

        app.buttons["field-notes"].tap()
        let tick = app.staticTexts["authoritative-tick"]
        XCTAssertTrue(tick.waitForExistence(timeout: 3))
        XCTAssertEqual(tick.label, "Fixed ticks, 40")
    }

    private func attachScreenshot(named name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
