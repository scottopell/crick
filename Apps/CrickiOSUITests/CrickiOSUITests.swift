import XCTest

@MainActor
final class CrickiOSUITests: XCTestCase {
    func testConnectedDiggingStrokePersistsAndDeepens() {
        let app = XCUIApplication()
        app.launchEnvironment["CRICK_UI_TEST_RESET"] = "1"
        app.launch()

        let surface = app.otherElements["digging-surface"]
        XCTAssertTrue(surface.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["hold-two-x"].firstMatch.exists)
        attachScreenshot(named: "Digging — flowing authored bend")

        // A real connected exploratory stroke starts at the visible wet bend and
        // continues onto its inside shoulder; no product copy guides this route.
        let start = surface.coordinate(withNormalizedOffset: CGVector(dx: 0.36, dy: 0.28))
        let end = surface.coordinate(withNormalizedOffset: CGVector(dx: 0.66, dy: 0.62))
        start.press(forDuration: 0.15, thenDragTo: end)
        XCTAssertTrue(app.staticTexts["excavated-cell-count"].label.contains("lowered"))
        XCTAssertFalse(app.staticTexts["excavated-cell-count"].label.hasPrefix("0 "))
        let tickAfterStroke = tickValue(app)
        XCTAssertGreaterThan(tickAfterStroke, 0, "live world must keep advancing after the intervention")
        let bedStatus = app.staticTexts["digging-status"].label
        XCTAssertTrue(bedStatus.contains("current") || bedStatus.contains("live"))

        let holdControl = app.buttons["hold-two-x"].firstMatch
        let heldStatus = app.staticTexts["digging-status"]
        let beforeHold = tickValue(app)
        // XCUITest requires input synthesis and element queries on the main thread,
        // so the pure clock test asserts the transient while-down state directly;
        // this native action verifies a real physical hold drives the app clock.
        holdControl.press(forDuration: 1.0)
        XCTAssertGreaterThan(tickValue(app), beforeHold, "a real hold must drive fixed-step pulses")
        XCTAssertFalse(heldStatus.label.contains("2× held"), "release must immediately clear held state")
        assertTickResumes(in: app, after: tickValue(app), message: "release must return the next pulse to live 1×")

        // A drag leaving the control still ends the gesture and restores 1×.
        let holdCenter = holdControl.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        let outside = surface.coordinate(withNormalizedOffset: CGVector(dx: 0.05, dy: 0.05))
        holdCenter.press(forDuration: 0.15, thenDragTo: outside)
        XCTAssertFalse(heldStatus.label.contains("2× held"))

        let countAfterFirst = app.staticTexts["excavated-cell-count"].label
        start.press(forDuration: 0.15, thenDragTo: end)
        Thread.sleep(forTimeInterval: 1.2)
        attachScreenshot(named: "Live erosion — cut evolving with carried sediment and deposition")
        let countAfterSecond = app.staticTexts["excavated-cell-count"].label
        let secondSummary = surface.value as? String ?? ""
        XCTAssertTrue(secondSummary.contains("digging increment"), "repeat stroke must retain measured cut depth")
        let firstCount = Int(countAfterFirst.split(separator: " ").first ?? "0") ?? 0
        let secondCount = Int(countAfterSecond.split(separator: " ").first ?? "0") ?? 0
        XCTAssertLessThanOrEqual(
            secondCount - firstCount,
            12,
            "a repeat drag may rasterize at most the connected line's twelve grid cells"
        )

        for _ in 0..<3 {
            app.buttons["digging-menu"].tap()
            let cancelPaused = tickValue(app)
            assertTickStaysPaused(in: app, at: cancelPaused)
            app.buttons["Cancel"].tap()
            let restart = tickValue(app)
            Thread.sleep(forTimeInterval: 0.16)
            let onePulseWindow = tickValue(app) - restart
            XCTAssertLessThanOrEqual(onePulseWindow, 2, "repeated menu dismissal must not duplicate clocks")
            assertTickResumes(in: app, after: cancelPaused, message: "cancel dismissal must resume ticking")
        }

        app.buttons["digging-menu"].tap()
        let savePaused = tickValue(app)
        app.buttons["save-digging"].tap()
        assertTickResumes(in: app, after: savePaused, message: "save dismissal must resume ticking")

        app.buttons["digging-menu"].tap()
        app.buttons["reset-digging"].tap()
        XCTAssertLessThan(tickValue(app), 4)
        assertTickResumes(in: app, after: tickValue(app), message: "reset dismissal must resume ticking")

        app.buttons["digging-menu"].tap()
        app.buttons["resume-digging"].tap()
        let resumed = tickValue(app)
        XCTAssertGreaterThan(resumed, 0)
        assertTickResumes(in: app, after: resumed, message: "resume dismissal must resume ticking")

        XCUIDevice.shared.press(.home)
        Thread.sleep(forTimeInterval: 0.5) // let the lifecycle transition itself settle
        let tickAtStartOfAwayInterval = tickValue(app)
        Thread.sleep(forTimeInterval: 3.0)
        let tickAfterAwayInterval = tickValue(app)
        XCTAssertEqual(tickAfterAwayInterval, tickAtStartOfAwayInterval, "the measured inactive interval must perform zero work")
        app.activate()
        XCTAssertTrue(app.buttons["hold-two-x"].firstMatch.waitForExistence(timeout: 2))
        let afterActivation = tickValue(app)
        assertTickResumes(in: app, after: afterActivation, message: "activation must resume ticking without replaying elapsed inactive time")
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

    private func assertTickResumes(in app: XCUIApplication, after tick: Int, message: String) {
        let predicate = NSPredicate { _, _ in self.tickValue(app) > tick }
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: app)
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: 1.5), .completed, message)
    }

    private func assertTickStaysPaused(in app: XCUIApplication, at tick: Int) {
        let predicate = NSPredicate { _, _ in self.tickValue(app) != tick }
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: app)
        expectation.isInverted = true
        XCTAssertEqual(
            XCTWaiter.wait(for: [expectation], timeout: 0.35),
            .completed,
            "an open menu must own the live pause"
        )
    }

    private func tickValue(_ app: XCUIApplication) -> Int {
        let label = app.staticTexts["digging-tick"].label
        return Int(label.split(separator: " ").last ?? "0") ?? 0
    }

    private func attachScreenshot(named name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
