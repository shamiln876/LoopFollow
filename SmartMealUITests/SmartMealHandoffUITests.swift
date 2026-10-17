// LoopFollow
// SmartMealHandoffUITests.swift

import XCTest

final class SmartMealHandoffUITests: XCTestCase {
    override func setUp() { super.setUp(); continueAfterFailure = false }

    func testHomeAdvisorEditedUnitsPopulateMeal() {
        exerciseHandoff(fromMeal: false)
    }

    func testMealAdvisorEditedUnitsPopulateExistingMeal() {
        exerciseHandoff(fromMeal: true)
    }

    func testPizzaChoiceAndPercentagesSurviveReopeningAdvisor() {
        let app = XCUIApplication()
        app.launchArguments = ["--smart-meal-ui-test"]
        app.launch()
        let home = app.buttons["home-meal-dashboard"]
        XCTAssertTrue(home.waitForExistence(timeout: 30)); home.tap()
        let picker = app.descendants(matching: .any)["advisor-preset"].firstMatch
        XCTAssertTrue(picker.waitForExistence(timeout: 10)); picker.tap()
        app.buttons["Pizza"].tap()
        let carbs = app.textFields["advisor-meal-carbs"]
        carbs.tap(); carbs.typeText("80"); hideKeyboard(app)
        let use = app.buttons["advisor-review-meal"]
        XCTAssertTrue(use.waitForExistence(timeout: 5))
        XCTAssertTrue(use.label.contains("56 g") && use.label.contains("6.20"))
        use.tap()
        let advisor = app.buttons["meal-open-advisor"]
        XCTAssertTrue(advisor.waitForExistence(timeout: 10)); advisor.tap()
        XCTAssertTrue(app.textFields["advisor-meal-carbs"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["advisor-review-meal"].label.contains("56 g"))
        XCTAssertTrue(app.buttons["advisor-review-meal"].label.contains("6.20"))
        XCTAssertTrue(app.staticTexts["Suggested upfront (70%)"].exists)
        let capture = XCTAttachment(screenshot: app.screenshot())
        capture.name = "Pizza preserved when reopening Advisor"; capture.lifetime = .keepAlways; add(capture)
        app.terminate()
    }

    func testOlderTrioCannotSendSplitMeal() {
        let app = XCUIApplication()
        app.launchArguments = ["--smart-meal-ui-test", "--smart-meal-old-trio"]
        app.launch()
        let home = app.buttons["home-meal-dashboard"]
        XCTAssertTrue(home.waitForExistence(timeout: 30)); home.tap()
        let carbs = app.textFields["advisor-meal-carbs"]
        XCTAssertTrue(carbs.waitForExistence(timeout: 10)); carbs.tap(); carbs.typeText("80")
        hideKeyboard(app)
        let use = app.buttons["advisor-review-meal"]
        XCTAssertTrue(use.waitForExistence(timeout: 5)); use.tap()
        let send = app.buttons["Send Meal"]
        XCTAssertTrue(send.waitForExistence(timeout: 10)); XCTAssertFalse(send.isEnabled)
        XCTAssertTrue(app.staticTexts["Split carbs need the matching Trio update and its latest connection. Nothing has been sent or scheduled."].exists)
        app.terminate()
    }

    private func exerciseHandoff(fromMeal: Bool) {
        let app = XCUIApplication()
        app.launchArguments = ["--smart-meal-ui-test"]
        app.launch()
        let entry = app.buttons[fromMeal ? "fixture-open-meal" : "home-meal-dashboard"]
        XCTAssertTrue(entry.waitForExistence(timeout: 30))
        entry.tap()
        if fromMeal {
            let openAdvisor = app.buttons["meal-open-advisor"]
            XCTAssertTrue(openAdvisor.waitForExistence(timeout: 10)); openAdvisor.tap()
        }
        let carbs = app.textFields["advisor-meal-carbs"]
        XCTAssertTrue(carbs.waitForExistence(timeout: 10)); carbs.tap(); carbs.typeText("80")
        hideKeyboard(app)
        let dose = app.textFields["advisor-edit-bolus"]
        for _ in 0 ..< 4 where !dose.isHittable {
            app.swipeUp()
        }
        XCTAssertTrue(dose.isHittable)
        dose.tap()
        let previous = dose.value as? String ?? ""
        dose.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: previous.count) + "0.65")
        XCTAssertEqual(dose.value as? String, "0.65")
        hideKeyboard(app)
        let use = app.buttons["advisor-review-meal"]
        XCTAssertTrue(use.waitForExistence(timeout: 5)); XCTAssertTrue(use.isEnabled)
        XCTAssertTrue(use.label.contains("0.65")); use.tap()
        let mealDose = app.textFields["meal-input-bolus-amount"]
        for _ in 0 ..< 5 where !mealDose.isHittable {
            app.swipeUp()
        }
        XCTAssertTrue(mealDose.waitForExistence(timeout: 10))
        XCTAssertEqual(mealDose.value as? String, "0.65")
        let mealCarbs = app.textFields["meal-input-carbs"]
        XCTAssertEqual(mealCarbs.value as? String, "60")
        XCTAssertFalse(app.staticTexts["Split meal sending is unavailable"].exists)
        XCTAssertTrue(app.buttons["Send Meal"].isEnabled)
        let capture = XCTAttachment(screenshot: app.screenshot())
        capture.name = fromMeal ? "Meal-to-advisor edited dose handoff" : "Home-to-advisor edited dose handoff"
        capture.lifetime = .keepAlways; add(capture)
        // Never tap Send Meal or authenticate. No credential/transport is configured.
        app.terminate()
    }

    private func hideKeyboard(_ app: XCUIApplication) {
        let hide = app.buttons["Hide keyboard"].firstMatch
        if hide.waitForExistence(timeout: 2) { hide.tap() }
    }
}
