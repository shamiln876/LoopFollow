// LoopFollow
// CarnivalFoodPresentationTests.swift

import Foundation
@testable import LoopFollow
import SwiftUI
import UIKit
import XCTest

final class CarnivalFoodPresentationTests: XCTestCase {
    @MainActor
    func testFoodSearchAtPhoneSize() async throws {
        try await capture(size: .large, showPlate: false, name: "Carnival — offline food search")
    }

    @MainActor
    func testPlateAtAccessibilitySize() async throws {
        try await capture(size: .accessibilityLarge, showPlate: true, name: "Carnival — accessible plate")
    }

    @MainActor
    private func capture(size: ContentSizeCategory, showPlate: Bool, name: String) async throws {
        let guide = try CarnivalFoodCatalog.bundled.get()
        let food = try XCTUnwrap(guide.foods.first { $0.id == "MG8D7CE49" })
        let plate = CarnivalMeal(sourceFilename: guide.sourceFilename, sourceSHA256: guide.sourceSHA256, items: [.init(food: food, portions: 0.5)])
        let controller = UIHostingController(rootView: CarnivalFoodGuideView(initialMeal: showPlate ? plate : nil) { _ in XCTFail("A presentation capture cannot apply carbs.") }.environment(\.sizeCategory, size))
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.first { $0 is UIWindowScene } as? UIWindowScene)
        let previousWindow = scene.windows.first { $0.isKeyWindow }
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 393, height: 852)
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
