// LoopFollow
// MealReviewPresentationTests.swift

import Foundation
import HealthKit
@testable import LoopFollow
import SwiftUI
import UIKit
import XCTest

final class MealReviewPresentationTests: XCTestCase {
    @MainActor
    func testReviewAtPhoneSize() async throws {
        try await captureReview(sizeCategory: .large, name: "Meal review — standard text")
    }

    @MainActor
    func testReviewAtAccessibilitySize() async throws {
        try await captureReview(sizeCategory: .accessibilityLarge, name: "Meal review — accessibility text")
    }

    @MainActor
    func testPrefilledEditableMealScreen() async throws {
        try await captureReview(sizeCategory: .large, name: "Editable Meal prefill — 80 g and 4.35 U", withDraft: true)
    }

    @MainActor
    func testLowForecastComparison() async throws {
        try await captureReview(sizeCategory: .large, name: "Automatic comparison — low forecast hold", lowForecast: true)
    }

    @MainActor
    func testAuditUsesCurrentTimeAfterLiveInputUpdate() async throws {
        try await captureReview(sizeCategory: .large, name: "Fresh upload — current evaluation time", checkAuditClock: true)
    }

    @MainActor
    func testRecommendationHandoffCopiesSelectedDose() async throws {
        try await captureReview(sizeCategory: .large, name: "Direct transfer — selected dose", checkTransfer: true)
    }

    @MainActor
    func testEditedBolusHandoffCopiesExactUnits() async throws {
        try await captureReview(sizeCategory: .large, name: "Edited bolus — exact handoff", checkTransfer: true, manualBolus: 0.65, withReceiver: true)
    }

    @MainActor
    func testHistoricalSettingsCannotTransferDose() async throws {
        try await captureReview(sizeCategory: .accessibilityLarge, name: "Historical settings — actionable hold", checkSettingsAction: true)
    }

    @MainActor
    private func captureReview(sizeCategory: ContentSizeCategory, name: String, withDraft: Bool = false, lowForecast: Bool = false, checkAuditClock: Bool = false, checkTransfer: Bool = false, checkSettingsAction: Bool = false, manualBolus: Double? = nil, withReceiver: Bool = false) async throws {
        let previousSnapshot = Observable.shared.mealReview.value
        let previousHistory = Observable.shared.mealReviewGlucose.value
        let previousTreatment = Observable.shared.mealReviewNewestTreatment.value
        defer {
            Observable.shared.mealReview.value = previousSnapshot
            Observable.shared.mealReviewGlucose.value = previousHistory
            Observable.shared.mealReviewNewestTreatment.value = previousTreatment
        }
        let now = Date()
        var snapshot = MealReviewSnapshot(date: now, carbRatio: 10, ratioSource: "Trio reported", iob: 1, iobDate: now, cob: 20)
        snapshot.effectiveISF = 40
        snapshot.isfSource = "Trio structured effective ISF"
        snapshot.targetMgdl = 100
        snapshot.minPredMgdl = 100
        snapshot.minGuardMgdl = lowForecast ? 60 : 100
        snapshot.activity = 0.01
        snapshot.calculationIOB = 1
        snapshot.trioVersion = "1.0.2"
        snapshot.reportedBolusIncrement = 0.05
        snapshot.pumpDate = now
        snapshot.uploadUnitSource = "Trio mg/dL fields"
        if withReceiver {
            let config = SmartMealConfiguration(percentage: 80, maxIOB: 15, maxCOB: 120, maxBolus: 10,
                                                maxCarbs: 150, maxFat: 100, maxProtein: 100, bolusIncrement: 0.05)
            snapshot.smartMeal = SmartMealReceiverStatus(protocolVersion: 1, generatedAt: now.timeIntervalSince1970,
                                                         calculationAt: now.timeIntervalSince1970, bundleIdentifier: "test.trio", enabled: true, configuration: config, receipts: [])
        }
        Observable.shared.mealReview.value = snapshot
        Observable.shared.mealReviewGlucose.value = [.init(date: now.addingTimeInterval(-900), mgdl: 175), .init(date: now, mgdl: 180)]
        Observable.shared.mealReviewNewestTreatment.value = nil
        let testSource = "https://example.invalid/nightscout"
        let source = StorageValue<String>(key: "test_meal_review_source", defaultValue: testSource)
        let settings = StorageValue<MealReviewSettings?>(key: "test_meal_review_settings", defaultValue: .init(percentage: 80, maxIOB: 15, maxCOB: 120, maxBolus: 10, sourceFingerprint: MealReviewSettings.fingerprint(testSource), trioVersion: "1.0.2", checkedAt: now, historicalReference: sizeCategory == .accessibilityLarge ? "Synthetic historical fixture; not verified current." : nil))
        defer { source.remove(); settings.remove() }
        let previousBundle = Storage.shared.bundleId.value
        let previousCarbLimit = Storage.shared.maxCarbs.value
        defer { Storage.shared.bundleId.value = previousBundle; Storage.shared.maxCarbs.value = previousCarbLimit }
        Storage.shared.maxCarbs.value = HKQuantity(unit: .gram(), doubleValue: 150)
        if withReceiver {
            Storage.shared.bundleId.value = "test.trio"
            settings.value = SmartMealDelivery.liveSettings(snapshot: snapshot, source: testSource, bundleID: "test.trio", now: now)
        }
        let auditDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let audit = MealReviewAuditStore(directory: auditDirectory)
        defer { audit.flush(); try? FileManager.default.removeItem(at: auditDirectory) }
        let previousLimit = Storage.shared.maxBolus.value
        defer { Storage.shared.maxBolus.value = previousLimit }
        var transferred: SmartMealDraft?
        if checkTransfer { Storage.shared.maxBolus.value = HKQuantity(unit: .internationalUnit(), doubleValue: 10) }
        var review: MealReviewView?
        let root: AnyView
        if withDraft {
            Storage.shared.maxBolus.value = HKQuantity(unit: .internationalUnit(), doubleValue: 10)
            let plan = try XCTUnwrap(RiceMealPlan(carbs: 80, fullRecommendation: 5.8, upfrontPercent: 75,
                                                  confirmedAt: now, carbsNowPercent: 100, delayMinutes: 0))
            let draft = try SmartMealDraft(plan: plan, protein: 0, fat: 0, settings: XCTUnwrap(settings.value),
                                           snapshot: snapshot, source: testSource, createdAt: now)
            root = AnyView(MealView(initialAdvisorDraft: draft).environment(\.sizeCategory, sizeCategory))
        } else {
            let advisor = MealReviewView(initialCarbs: 80, initialBolus: manualBolus, settings: settings, source: source, audit: audit, onUse: { transferred = $0 })
            review = advisor
            root = AnyView(advisor.environment(\.sizeCategory, sizeCategory))
        }
        let controller = UIHostingController(rootView: root)
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.first { $0 is UIWindowScene } as? UIWindowScene)
        let previousWindow = scene.windows.first { $0.isKeyWindow }
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 393, height: 852)
        window.rootViewController = controller
        window.makeKeyAndVisible()
        defer { window.isHidden = true; previousWindow?.makeKeyAndVisible() }
        try await Task.sleep(nanoseconds: 500_000_000)
        controller.view.layoutIfNeeded()
        if checkTransfer {
            let fullResult = try XCTUnwrap(MealReviewFullCalculation.comparison(newCarbs: 80, settings: settings.value, snapshot: snapshot, source: testSource, samples: Observable.shared.mealReviewGlucose.value, newestTreatment: nil, now: Date()))
            try XCTUnwrap(review).useRecommendation(full: fullResult.rounded)
            let draft = try XCTUnwrap(transferred)
            XCTAssertEqual(draft.plan.immediateCarbs, 80)
            XCTAssertEqual(draft.plan.delayedCarbs, 0)
            XCTAssertEqual(draft.protein, 0)
            XCTAssertEqual(draft.fat, 0)
            let full = try XCTUnwrap(MealReviewFullCalculation.review(newCarbs: 80, settings: settings.value, snapshot: snapshot, source: testSource, samples: Observable.shared.mealReviewGlucose.value, newestTreatment: nil, now: Date()))
            XCTAssertEqual(draft.plan.fullRecommendation, full.rounded)
            XCTAssertEqual(draft.plan.upfrontInsulin, manualBolus ?? full.rounded, accuracy: 0.00001)
            XCTAssertEqual(draft.plan.usesManualBolus, manualBolus != nil)
            if manualBolus != nil { XCTAssertNotEqual(draft.plan.upfrontInsulin, full.rounded) }
        }
        if checkSettingsAction {
            let full = try XCTUnwrap(MealReviewFullCalculation.comparison(newCarbs: 80, settings: settings.value, snapshot: snapshot, source: testSource, samples: Observable.shared.mealReviewGlucose.value, newestTreatment: nil, now: Date()))
            try XCTUnwrap(review).useRecommendation(full: full.rounded)
            XCTAssertNil(transferred)
            XCTAssertTrue(settings.value?.isHistorical == true)
        }
        if checkAuditClock {
            var updated = try XCTUnwrap(Observable.shared.mealReview.value)
            updated.activity = 0.011
            Observable.shared.mealReview.value = updated
            // New data must be evaluated at capture time, not at the last
            // display-timer tick (which can remain frozen while suspended).
            try await Task.sleep(nanoseconds: 1_500_000_000)
            audit.flush()
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .millisecondsSince1970
            let files = try FileManager.default.contentsOfDirectory(at: auditDirectory, includingPropertiesForKeys: nil)
            let records = try files.filter { $0.pathExtension == "jsonl" }.flatMap { file in
                try Data(contentsOf: file).split(separator: 0x0A).map { try decoder.decode(MealReviewAudit.Entry.self, from: Data($0)) }
            }
            let record = try XCTUnwrap(records.last)
            XCTAssertLessThan(abs(record.capturedAt.timeIntervalSince(record.evaluatedAt)), 0.1)
            XCTAssertFalse(record.payload.holdReasons.contains { $0.contains("future timestamp") || $0.contains("calculation is missing or stale") })
        }
        if lowForecast {
            func scrollViews(in view: UIView) -> [UIScrollView] {
                (view as? UIScrollView).map { [$0] } ?? view.subviews.flatMap { scrollViews(in: $0) }
            }
            let form = try XCTUnwrap(scrollViews(in: controller.view).max { $0.contentSize.height < $1.contentSize.height })
            // Capture the calculation itself, rather than only the form header.
            let offset = min(820, max(0, form.contentSize.height - form.bounds.height))
            XCTAssertGreaterThan(offset, 0)
            form.setContentOffset(CGPoint(x: 0, y: offset), animated: false)
            try await Task.sleep(nanoseconds: 500_000_000)
            controller.view.layoutIfNeeded()
        }
        let renderer = UIGraphicsImageRenderer(bounds: window.bounds)
        let image = renderer.image { _ in window.drawHierarchy(in: window.bounds, afterScreenUpdates: true) }
        XCTAssertGreaterThan(image.pngData()?.count ?? 0, 1000)
        let pixelData = try XCTUnwrap(image.cgImage?.dataProvider?.data)
        let pixels = try XCTUnwrap(CFDataGetBytePtr(pixelData))
        // A detached window can yield an all-black PNG; require visible RGB
        // variation so a passing test actually gives us a reviewable screen.
        let length = CFDataGetLength(pixelData)
        var darkest = UInt8.max
        var brightest = UInt8.min
        for offset in stride(from: 0, to: length, by: 4) {
            darkest = min(darkest, pixels[offset])
            brightest = max(brightest, pixels[offset])
        }
        XCTAssertGreaterThan(Int(brightest) - Int(darkest), 20)
        let attachment = XCTAttachment(image: image)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
