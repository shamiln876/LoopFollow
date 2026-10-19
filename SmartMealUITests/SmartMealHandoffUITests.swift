// LoopFollow
// SmartMealHandoffUITests.swift

import XCTest

final class SmartMealHandoffUITests: XCTestCase {
    override func setUp() { super.setUp(); continueAfterFailure = false }

    func testFivePercentControlLinksFullMealCarbsAndTransfersUnits() {
        exercisePercentageControl(rice: false)
    }

    func testFivePercentControlLinksRiceCarbsAndTransfersUnits() {
        exercisePercentageControl(rice: true)
    }

    func testCustomPercentageCanKeepCarbsIndependent() {
        exercisePercentageControl(rice: false, linked: false)
    }

    func testOptionalScannerRequiresReviewAndUnknownResolution() {
        let app = XCUIApplication()
        app.launchArguments = ["--smart-meal-ui-test", "--plate-scanner-ui-test"]
        app.launch()
        let entry = app.buttons["home-meal-dashboard"]
        XCTAssertTrue(entry.waitForExistence(timeout: 30)); entry.tap()
        app.buttons["advisor-scan-plate"].tap()
        let accept = app.buttons["plate-scan-accept"]
        for _ in 0 ..< 4 where !accept.isHittable {
            app.swipeUp()
        }
        XCTAssertTrue(accept.waitForExistence(timeout: 10)); XCTAssertFalse(accept.isEnabled)
        let remove = app.buttons.matching(identifier: "Remove food")
        XCTAssertEqual(remove.count, 2)
        remove.element(boundBy: 1).tap()
        app.buttons["Add food"].tap()
        let search = app.textFields["plate-match-query"]
        XCTAssertTrue(search.waitForExistence(timeout: 5)); search.tap(); search.typeText("Bagel Plain")
        app.buttons["plate-match-MG8D7CE49"].tap()
        let addedRemove = app.buttons.matching(identifier: "Remove food")
        for _ in 0 ..< 4 where !addedRemove.element(boundBy: 1).isHittable {
            app.swipeUp()
        }
        XCTAssertEqual(addedRemove.count, 2)
        addedRemove.element(boundBy: 1).tap()
        let increase = app.buttons["Increase portion"].firstMatch
        for _ in 0 ..< 4 where !increase.isHittable {
            app.swipeDown()
        }
        increase.tap()
        XCTAssertTrue(app.staticTexts["Estimated carbs: 39 g"].exists)
        app.buttons["Decrease portion"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Estimated carbs: 26 g"].exists)
        let confirm = app.switches["I checked this match and portion"]
        for _ in 0 ..< 4 where !confirm.isHittable {
            app.swipeUp()
        }
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        confirm.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap()
        for _ in 0 ..< 4 where !accept.isHittable {
            app.swipeUp()
        }
        XCTAssertTrue(accept.isEnabled)
        let capture = XCTAttachment(screenshot: app.screenshot()); capture.name = "Reviewed optional plate scanner"; capture.lifetime = .keepAlways; add(capture)
        accept.tap()
        XCTAssertTrue(app.textFields["advisor-meal-carbs"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.textFields["advisor-meal-carbs"].value as? String, "26")
        app.terminate()
    }

    func testDirectPhotoCancellationKeepsAdvisorCarbs() {
        let app = XCUIApplication()
        app.launchArguments = ["--smart-meal-ui-test"]
        app.launch()
        let entry = app.buttons["home-meal-dashboard"]
        XCTAssertTrue(entry.waitForExistence(timeout: 30)); entry.tap()
        let carbs = app.textFields["advisor-meal-carbs"]
        carbs.tap(); carbs.typeText("42"); hideKeyboard(app)
        app.buttons["advisor-scan-plate"].tap()
        XCTAssertTrue(app.staticTexts["plate-device-status"].waitForExistence(timeout: 10))
        app.buttons["Cancel"].tap()
        XCTAssertTrue(carbs.waitForExistence(timeout: 10))
        XCTAssertEqual(carbs.value as? String, "42")
        app.terminate()
    }

    private func exercisePercentageControl(rice: Bool, linked: Bool = true) {
        let app = XCUIApplication()
        app.launchArguments = ["--smart-meal-ui-test", "--smart-meal-percentage-test"]
        app.launch()
        let entry = app.buttons["fixture-percentage-advisor"]
        XCTAssertTrue(entry.waitForExistence(timeout: 30)); entry.tap()
        if rice { selectRice(app) }
        if !linked {
            app.buttons["Custom percentages and timing"].tap()
            let toggle = app.switches["advisor-link-percentages"]
            XCTAssertTrue(toggle.waitForExistence(timeout: 5))
            toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap()
            XCTAssertEqual(toggle.value as? String, "0")
        }
        let decrease = app.buttons["advisor-percent-decrease"]
        for _ in 0 ..< 4 where !decrease.isHittable {
            app.swipeUp()
        }
        XCTAssertTrue(decrease.waitForExistence(timeout: 10))
        let value = app.staticTexts["advisor-percent-value"]
        XCTAssertEqual(value.label, rice ? "75%" : "100%")
        decrease.tap()
        XCTAssertEqual(value.label, rice ? "70%" : "95%")
        let increase = app.buttons["advisor-percent-increase"]
        increase.tap()
        XCTAssertEqual(value.label, rice ? "75%" : "100%")
        if !rice { XCTAssertFalse(increase.isEnabled) }
        decrease.tap()
        let use = app.buttons["advisor-review-meal"]
        XCTAssertTrue(use.isEnabled)
        XCTAssertTrue(use.label.contains(rice ? "56 g" : linked ? "76 g" : "80 g"), use.label)
        XCTAssertTrue(use.label.contains(rice ? "6.20" : "8.45"))
        let advisorCapture = XCTAttachment(screenshot: app.screenshot())
        advisorCapture.name = rice ? "5 percent control links Rice carbs" : "5 percent control links full meal carbs"
        advisorCapture.lifetime = .keepAlways; add(advisorCapture)
        use.tap()
        let dose = app.textFields["meal-input-bolus-amount"]
        for _ in 0 ..< 5 where !dose.isHittable {
            app.swipeUp()
        }
        XCTAssertTrue(dose.waitForExistence(timeout: 10))
        XCTAssertEqual(dose.value as? String, rice ? "6.20" : "8.45")
        XCTAssertEqual(app.textFields["meal-input-carbs"].value as? String, rice ? "56" : linked ? "76" : "80")
        let capture = XCTAttachment(screenshot: app.screenshot())
        capture.name = rice ? "Rice split with linked 5 percent control" : "Full meal with linked 5 percent control"
        capture.lifetime = .keepAlways; add(capture)
        // Stop before Send Meal. The simulator has no treatment credentials.
        app.terminate()
    }

    func testHomeAdvisorEditedUnitsPopulateMeal() {
        exerciseHandoff(fromMeal: false)
    }

    func testRiceSplitEditedUnitsPopulateMeal() {
        exerciseHandoff(fromMeal: false, riceSplit: true)
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
        selectRice(app)
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

    private func exerciseHandoff(fromMeal: Bool, riceSplit: Bool = false) {
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
        if riceSplit { selectRice(app) }
        let carbs = app.textFields["advisor-meal-carbs"]
        XCTAssertTrue(carbs.waitForExistence(timeout: 10)); carbs.tap(); carbs.typeText("80")
        hideKeyboard(app)
        let dose = app.textFields["advisor-edit-bolus"]
        for _ in 0 ..< 4 where !dose.isHittable {
            app.swipeUp()
        }
        XCTAssertTrue(dose.isHittable)
        XCTAssertTrue(app.staticTexts[riceSplit ? "Suggested upfront (75%)" : "Suggested upfront (100%)"].exists)
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
        XCTAssertEqual(mealCarbs.value as? String, riceSplit ? "60" : "80")
        XCTAssertFalse(app.staticTexts["Split meal sending is unavailable"].exists)
        XCTAssertTrue(app.buttons["Send Meal"].isEnabled)
        let capture = XCTAttachment(screenshot: app.screenshot())
        capture.name = fromMeal ? "Meal-to-advisor edited dose handoff" : "Home-to-advisor edited dose handoff"
        capture.lifetime = .keepAlways; add(capture)
        // Never tap Send Meal or authenticate. No credential/transport is configured.
        app.terminate()
    }

    private func selectRice(_ app: XCUIApplication) {
        let picker = app.descendants(matching: .any)["advisor-preset"].firstMatch
        XCTAssertTrue(picker.waitForExistence(timeout: 10)); picker.tap()
        app.buttons["Rice · 75/25 split"].tap()
    }

    private func hideKeyboard(_ app: XCUIApplication) {
        let hide = app.buttons["Hide keyboard"].firstMatch
        if hide.waitForExistence(timeout: 2) { hide.tap() }
    }
}
