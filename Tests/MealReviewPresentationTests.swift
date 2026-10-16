// LoopFollow
// MealReviewPresentationTests.swift

import Foundation
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
    private func captureReview(sizeCategory: ContentSizeCategory, name: String) async throws {
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
        snapshot.minGuardMgdl = 100
        snapshot.activity = 0.01
        snapshot.calculationIOB = 1
        snapshot.trioVersion = "1.0.2"
        snapshot.reportedBolusIncrement = 0.05
        snapshot.pumpDate = now
        snapshot.uploadUnitSource = "Trio mg/dL fields"
        Observable.shared.mealReview.value = snapshot
        Observable.shared.mealReviewGlucose.value = [.init(date: now.addingTimeInterval(-900), mgdl: 175), .init(date: now, mgdl: 180)]
        Observable.shared.mealReviewNewestTreatment.value = nil
        let testSource = "https://example.invalid/nightscout"
        let source = StorageValue<String>(key: "test_meal_review_source", defaultValue: testSource)
        let settings = StorageValue<MealReviewSettings?>(key: "test_meal_review_settings", defaultValue: .init(percentage: 80, maxIOB: 15, maxCOB: 120, maxBolus: 10, sourceFingerprint: MealReviewSettings.fingerprint(testSource), trioVersion: "1.0.2", checkedAt: now, historicalReference: sizeCategory == .accessibilityLarge ? "Synthetic historical fixture; not verified current." : nil))
        defer { source.remove(); settings.remove() }
        let auditDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let audit = MealReviewAuditStore(directory: auditDirectory)
        defer { audit.flush(); try? FileManager.default.removeItem(at: auditDirectory) }
        let controller = UIHostingController(rootView: MealReviewView(initialCarbs: 80, settings: settings, source: source, audit: audit).environment(\.sizeCategory, sizeCategory))
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.first { $0 is UIWindowScene } as? UIWindowScene)
        let previousWindow = scene.windows.first { $0.isKeyWindow }
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 393, height: 852)
        window.rootViewController = controller
        window.makeKeyAndVisible()
        defer { window.isHidden = true; previousWindow?.makeKeyAndVisible() }
        try await Task.sleep(nanoseconds: 500_000_000)
        controller.view.layoutIfNeeded()
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
