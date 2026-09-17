import XCTest

@MainActor
final class CrickiOSUITests: XCTestCase {
    func testConnectedDiggingStrokePersistsAndDeepens() {
        let app = XCUIApplication()
        app.launchEnvironment["CRICK_UI_TEST_RESET"] = "1"
        app.launch()

        let surface = app.otherElements["digging-surface"]
        XCTAssertTrue(surface.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["let-water-flow"].exists)
        attachScreenshot(named: "Digging — flowing authored bend")

        // A real connected exploratory stroke starts at the visible wet bend and
        // continues onto its inside shoulder; no product copy guides this route.
        let start = surface.coordinate(withNormalizedOffset: CGVector(dx: 0.36, dy: 0.28))
        let end = surface.coordinate(withNormalizedOffset: CGVector(dx: 0.66, dy: 0.62))
        start.press(forDuration: 0.15, thenDragTo: end)
        XCTAssertTrue(app.staticTexts["excavated-cell-count"].label.contains("lowered"))
        XCTAssertFalse(app.staticTexts["excavated-cell-count"].label.hasPrefix("0 "))
        XCTAssertTrue(app.buttons["let-water-flow"].waitForExistence(timeout: 4))
        let firstTick = app.staticTexts["digging-tick"].label
        XCTAssertTrue(firstTick.contains("18"), "one drag must commit 18 actual fixed ticks")
        let firstSummary = surface.value as? String ?? ""
        XCTAssertTrue(firstSummary.contains("newly wet"), "scene summary must report measured wetting")
        XCTAssertTrue(firstSummary.contains("along the stroke"))

        let countAfterFirst = app.staticTexts["excavated-cell-count"].label
        start.press(forDuration: 0.15, thenDragTo: end)
        XCTAssertTrue(app.buttons["let-water-flow"].waitForExistence(timeout: 4))
        attachScreenshot(named: "Digging — lowered route with redirected water")
        let countAfterSecond = app.staticTexts["excavated-cell-count"].label
        let secondSummary = surface.value as? String ?? ""
        XCTAssertTrue(secondSummary.contains("2 digging increments deep"), "repeat stroke must increase depth")
        let firstCount = Int(countAfterFirst.split(separator: " ").first ?? "0") ?? 0
        let secondCount = Int(countAfterSecond.split(separator: " ").first ?? "0") ?? 0
        XCTAssertLessThanOrEqual(
            secondCount - firstCount,
            4,
            "compact-device repeat input may rasterize endpoint neighbors, but must primarily deepen the same route"
        )

        app.buttons["digging-menu"].tap()
        app.buttons["save-digging"].tap()
        app.buttons["digging-menu"].tap()
        app.buttons["reset-digging"].tap()
        XCTAssertTrue(app.staticTexts["digging-tick"].label.contains("0"))
        app.buttons["digging-menu"].tap()
        app.buttons["resume-digging"].tap()
        XCTAssertTrue(app.staticTexts["digging-tick"].label.contains("36"))

        XCUIDevice.shared.press(.home)
        app.activate()
        XCTAssertTrue(app.buttons["let-water-flow"].waitForExistence(timeout: 2))
    }

    // Shape the Bend (2–4): exercise the asynchronous presentation and explicit
    // retry/keep closure through the accessibility-facing UI.
    func testShapeTheBendAsyncJourney() {
        let app = XCUIApplication()
        app.launchEnvironment["CRICK_UI_TEST_RESET"] = "1"
        app.launch()

        app.buttons["digging-menu"].tap()
        app.buttons["open-legacy"].tap()
        let scene = app.otherElements["creek-scene"]
        XCTAssertTrue(scene.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["placement-prompt"].exists)
        attachScreenshot(named: "Shape the Bend — flowing baseline")

        let menu = app.buttons["choose-stone-position"]
        let start = scene.coordinate(withNormalizedOffset: CGVector(dx: 0.16, dy: 0.86))
        let upstream = scene.coordinate(withNormalizedOffset: CGVector(dx: 0.07, dy: 0.21))
        start.press(forDuration: 0.25, thenDragTo: upstream)
        XCTAssertTrue(
            app.staticTexts["stone-set"].waitForExistence(timeout: 2),
            "Dragging the bank stone to an eligible seat must succeed"
        )

        // Exercise the accessibility/menu path independently; it must not mask drag failure.
        menu.tap()
        XCTAssertFalse(app.buttons["place-stone-0"].exists)
        app.tap()

        let waterWork = app.buttons["let-water-work"]
        XCTAssertTrue(waterWork.isEnabled)
        waterWork.tap()
        XCTAssertTrue(app.staticTexts["water-playing"].waitForExistence(timeout: 1))
        XCTAssertTrue(app.staticTexts["water-playing"].label.contains("of 20"))
        XCTAssertTrue(app.buttons["reveal-result"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["result-copy"].exists)
        XCTAssertFalse(app.buttons["try-another-spot"].exists)
        XCTAssertFalse(app.buttons["keep-creek"].exists)
        app.buttons["Before"].tap()
        attachScreenshot(named: "Shape the Bend — before comparison")
        app.buttons["reveal-result"].tap()
        XCTAssertTrue(app.staticTexts["result-copy"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.staticTexts["result-copy"].label.contains("did not form"))
        attachScreenshot(named: "Shape the Bend — revealed first outcome")
        XCTAssertTrue(app.buttons["try-another-spot"].exists)
        XCTAssertFalse(app.buttons["keep-creek"].exists)

        app.buttons["try-another-spot"].tap()
        XCTAssertTrue(app.staticTexts["move-stone-prompt"].waitForExistence(timeout: 2))
        XCTAssertFalse(waterWork.isEnabled)

        menu.tap()
        app.buttons["place-stone-2"].tap()
        waterWork.tap()
        XCTAssertTrue(app.staticTexts["water-playing"].waitForExistence(timeout: 1))
        XCTAssertTrue(app.staticTexts["water-playing"].label.contains("of 20"))
        XCUIDevice.shared.press(.home)
        app.activate()
        XCTAssertTrue(app.buttons["reveal-result"].waitForExistence(timeout: 2))
        XCTAssertFalse(app.staticTexts["result-copy"].exists)
        app.buttons["reveal-result"].tap()
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
