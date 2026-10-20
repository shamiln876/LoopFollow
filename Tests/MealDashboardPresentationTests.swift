// LoopFollow
// MealDashboardPresentationTests.swift

import Foundation
@testable import LoopFollow
import SwiftUI
import UIKit
import XCTest

final class MealDashboardPresentationTests: XCTestCase {
    @MainActor
    func testHomeWithMealCard() async throws {
        let now = Date()
        let snapshot = Observable.shared.mealReview.value
        let readings = Observable.shared.mealReviewGlucose.value
        let treatment = Observable.shared.mealReviewNewestTreatment.value
        let source = Storage.shared.url.value
        let settings = Storage.shared.mealReviewSettings.value
        let hideInfo = Storage.shared.hideInfoTable.value
        defer {
            Observable.shared.mealReview.value = snapshot
            Observable.shared.mealReviewGlucose.value = readings
            Observable.shared.mealReviewNewestTreatment.value = treatment
            Storage.shared.url.value = source
            Storage.shared.mealReviewSettings.value = settings
            Storage.shared.hideInfoTable.value = hideInfo
        }
        Observable.shared.mealReview.value = MealDashboardFixture.snapshot(now: now)
        Observable.shared.mealReviewGlucose.value = MealDashboardFixture.readings(now: now)
        Observable.shared.mealReviewNewestTreatment.value = nil
        Storage.shared.url.value = MealDashboardFixture.source
        Storage.shared.mealReviewSettings.value = MealDashboardFixture.settings(now: now)
        Storage.shared.hideInfoTable.value = true
        let model = BGChartModel()
        model.bg = MealDashboardFixture.readings(now: now).map { .init(date: $0.date, value: $0.mgdl, color: .green) }
        try await capture(MainHomeView(chartModel: model, infoManager: InfoManager(), statsModel: StatsDisplayModel()), name: "Home — meal dashboard entry", size: CGSize(width: 393, height: 760))
    }

    @MainActor
    func testStaleHomeCardAtAccessibilitySize() async throws {
        let now = Date()
        let s = MealDashboardFixture.snapshot(now: now.addingTimeInterval(-1200))
        let status = MealDashboardStatus(snapshot: s, samples: MealDashboardFixture.readings(now: now.addingTimeInterval(-1200)), newestTreatment: nil, settings: MealDashboardFixture.settings(now: now.addingTimeInterval(-1200)), source: MealDashboardFixture.source, now: now)
        try await capture(VStack { MealDashboardHomeLabel(status: status, snapshot: s, now: now); Spacer() }.padding().environment(\.sizeCategory, .accessibilityLarge), name: "Home — stale inputs accessible", size: CGSize(width: 393, height: 760))
    }

    @MainActor
    func testDashboardOverviewWithGlucoseChart() async throws {
        let now = Date()
        let s = MealDashboardFixture.snapshot(now: now)
        let samples = MealDashboardFixture.readings(now: now)
        let status = MealDashboardStatus(snapshot: s, samples: samples, newestTreatment: nil, settings: MealDashboardFixture.settings(now: now), source: MealDashboardFixture.source, now: now)
        try await capture(Form {
            Section("At a glance") { MealDashboardOverview(status: status, snapshot: s, sensorArrow: "Flat", now: now) }
            Section("Recent glucose") { MealDashboardGlucoseChart(samples: samples, now: now) }
        }, name: "Dashboard — live overview and glucose", size: CGSize(width: 393, height: 852))
    }

    @MainActor
    private func capture(_ view: some View, name: String, size: CGSize) async throws {
        let controller = UIHostingController(rootView: view)
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.first { $0 is UIWindowScene } as? UIWindowScene)
        let previousWindow = scene.windows.first { $0.isKeyWindow }
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(origin: .zero, size: size)
        window.rootViewController = controller
        window.makeKeyAndVisible()
        defer { window.isHidden = true; previousWindow?.makeKeyAndVisible() }
        try await Task.sleep(nanoseconds: 500_000_000)
        controller.view.layoutIfNeeded()
        let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in window.drawHierarchy(in: window.bounds, afterScreenUpdates: true) }
        XCTAssertGreaterThan(image.pngData()?.count ?? 0, 1000)
        let data = try XCTUnwrap(image.cgImage?.dataProvider?.data)
        let bytes = try XCTUnwrap(CFDataGetBytePtr(data))
        var low = UInt8.max; var high = UInt8.min
        for offset in stride(from: 0, to: CFDataGetLength(data), by: 4) {
            low = min(low, bytes[offset]); high = max(high, bytes[offset])
        }
        XCTAssertGreaterThan(Int(high) - Int(low), 20)
        let attachment = XCTAttachment(image: image)
        attachment.name = name; attachment.lifetime = .keepAlways
        add(attachment)
    }
}
