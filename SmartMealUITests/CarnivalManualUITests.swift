// LoopFollow
// CarnivalManualUITests.swift

import XCTest

final class CarnivalManualUITests: XCTestCase {
    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    func testManualHalfBagelStillFillsAdvisorAfterCancellingScanner() {
        let app = XCUIApplication()
        app.launchArguments = ["--smart-meal-ui-test"]
        app.launch()
        defer { app.terminate() }

        let advisor = app.buttons["home-meal-dashboard"]
        XCTAssertTrue(advisor.waitForExistence(timeout: 30))
        advisor.tap()
        let guide = app.buttons["Carnival food & portions"]
        XCTAssertTrue(guide.waitForExistence(timeout: 10))
        guide.tap()

        let scanner = app.buttons["carnival-photo-scanner"]
        XCTAssertTrue(scanner.waitForExistence(timeout: 10))
        scanner.tap()
        let upload = app.buttons["plate-upload"]
        XCTAssertTrue(upload.waitForExistence(timeout: 10))
        XCTAssertFalse(upload.isEnabled)
        app.buttons["Cancel"].tap()

        let search = app.textFields["Search Carnival foods"]
        XCTAssertTrue(search.waitForExistence(timeout: 10))
        search.tap()
        search.typeText("Bagel Plain")
        let bagel = app.staticTexts["Bagel - Plain"].firstMatch
        XCTAssertTrue(bagel.waitForExistence(timeout: 5))
        bagel.tap()
        let half = app.buttons["0.5 base portions"]
        XCTAssertTrue(half.waitForExistence(timeout: 5))
        half.tap()
        let addFood = app.buttons["Add to plate"]
        for _ in 0 ..< 4 where !addFood.isHittable {
            app.swipeUp()
        }
        XCTAssertTrue(addFood.isHittable)
        addFood.tap()
        let use = app.buttons["carnival-use-total"]
        for _ in 0 ..< 4 where !use.isHittable {
            app.swipeUp()
        }
        XCTAssertTrue(use.waitForExistence(timeout: 5))
        XCTAssertEqual(use.label, "Use 26 g in meal review")
        use.tap()
        let carbs = app.textFields["advisor-meal-carbs"]
        XCTAssertTrue(carbs.waitForExistence(timeout: 10))
        XCTAssertEqual(carbs.value as? String, "26")
        let capture = XCTAttachment(screenshot: app.screenshot())
        capture.name = "Manual half bagel fills Advisor with 26 g"
        capture.lifetime = .keepAlways
        add(capture)
        // Only estimate entry is exercised; do not advance to Send Meal or authentication.
    }
}
