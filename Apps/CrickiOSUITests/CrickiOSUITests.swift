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

        let waterWork = app.buttons["let-water-work"]
        XCTAssertFalse(waterWork.isEnabled)
        scene.coordinate(withNormalizedOffset: CGVector(dx: 0.42, dy: 0.36)).tap()
        XCTAssertTrue(waterWork.isEnabled)

        waterWork.tap()
        XCTAssertFalse(app.staticTexts["objective-message"].label.contains("Find a place"))

        app.buttons["field-notes"].tap()
        let save = app.buttons["save-snapshot"]
        XCTAssertTrue(save.waitForExistence(timeout: 3))
        save.tap()
        XCTAssertTrue(app.buttons["resume-snapshot"].isEnabled)
        app.buttons["Done"].tap()

        waterWork.tap()
        app.buttons["field-notes"].tap()
        app.buttons["resume-snapshot"].tap()
        XCTAssertEqual(app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS '20'")
        ).count > 0, true)
    }
}
