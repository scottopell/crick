import XCTest

final class CrickiOSUITests: XCTestCase {
    func testShapeTheBendJourney() {
        let app = XCUIApplication()
        app.launchEnvironment["CRICK_UI_TEST_RESET"] = "1"
        app.launch()

        let scene = app.otherElements["creek-scene"]
        XCTAssertTrue(scene.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["objective-message"].label.contains("gather"))
        XCTAssertTrue(app.staticTexts["placement-prompt"].exists)
        XCTAssertTrue(app.buttons["choose-stone-position"].exists)

        let waterWork = app.buttons["let-water-work"]
        XCTAssertFalse(waterWork.isEnabled)
        let bankStone = scene.coordinate(
            withNormalizedOffset: CGVector(dx: 0.16, dy: 0.86)
        )
        let insideBend = scene.coordinate(
            withNormalizedOffset: CGVector(dx: 0.59, dy: 0.50)
        )
        bankStone.press(forDuration: 0.15, thenDragTo: insideBend)
        XCTAssertTrue(waterWork.isEnabled)

        waterWork.tap()
        XCTAssertEqual(
            app.staticTexts["objective-message"].label,
            "A calm pool is holding."
        )
        let completedCreek = XCTAttachment(screenshot: app.screenshot())
        completedCreek.name = "Shape the Bend — holding pool"
        completedCreek.lifetime = .keepAlways
        add(completedCreek)

        app.buttons["field-notes"].tap()
        let tick = app.staticTexts["authoritative-tick"]
        XCTAssertEqual(tick.label, "Fixed ticks, 20")
        let save = app.buttons["save-snapshot"]
        XCTAssertTrue(save.waitForExistence(timeout: 3))
        save.tap()
        XCTAssertTrue(app.buttons["resume-snapshot"].isEnabled)
        app.buttons["Done"].tap()

        waterWork.tap()
        app.buttons["field-notes"].tap()
        app.buttons["resume-snapshot"].tap()
        XCTAssertEqual(app.staticTexts["authoritative-tick"].label, "Fixed ticks, 20")
    }
}
