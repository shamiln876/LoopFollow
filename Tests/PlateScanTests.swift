// LoopFollow
// PlateScanTests.swift

import Foundation
@testable import LoopFollow
import Testing

struct PlateScanTests {
    private func catalog() throws -> CarnivalFoodCatalog {
        let url = ProcessInfo.processInfo.environment["PLATE_TEST_CATALOG"].flatMap(URL.init(fileURLWithPath:)) ?? Bundle.main.url(forResource: "CarnivalFoodGuide", withExtension: "json")!
        return try CarnivalFoodCatalog.decode(Data(contentsOf: url))
    }

    @Test func suggestionsRequireExplicitConfirmationAndUseCatalogNutritionOnly() throws {
        let guide = try catalog()
        let food = try #require(guide.foods.first { $0.id == "MG8D7CE49" })
        let response = PlateScanResponse(sourceSHA256: guide.sourceSHA256, items: [.init(label: "Bagel", foodID: food.id, portions: 0.5, uncertainty: "Check size")])
        var review = try response.review(catalog: guide)
        #expect(PlateScanReview.meal(review, catalog: guide) == nil)
        review[0].confirmed = true
        #expect(PlateScanReview.meal(review, catalog: guide)?.carbsForReview == 26)
        review[0].portions = 1
        #expect(PlateScanReview.meal(review, catalog: guide)?.carbsForReview == 52)
    }

    @Test func unknownAndMissingNutritionBlockAcceptance() throws {
        let guide = try catalog()
        for id in ["invented", guide.foods.first { !$0.available }!.id] {
            var review = try PlateScanResponse(sourceSHA256: guide.sourceSHA256, items: [.init(label: "Unknown sauce", foodID: id, portions: nil, uncertainty: "Unknown")]).review(catalog: guide)
            review[0].confirmed = true
            #expect(PlateScanReview.meal(review, catalog: guide) == nil)
        }
    }

    @Test func missingPortionRequiresManualEntryAndMalformedAmountFails() throws {
        let guide = try catalog(), food = guide.foods.first { $0.available }!
        var review = try PlateScanResponse(sourceSHA256: guide.sourceSHA256, items: [.init(label: "Food", foodID: food.id, portions: nil, uncertainty: "")]).review(catalog: guide)
        review[0].confirmed = true
        #expect(review[0].portionNeedsEntry)
        #expect(PlateScanReview.meal(review, catalog: guide) == nil)
        review[0].portionNeedsEntry = false
        #expect(PlateScanReview.meal(review, catalog: guide) != nil)
        for amount in [0.0, -1, 101, .infinity] {
            #expect(throws: Error.self) { try PlateScanResponse(sourceSHA256: guide.sourceSHA256, items: [.init(label: "Food", foodID: food.id, portions: amount, uncertainty: "")]).review(catalog: guide) }
        }
    }

    @Test func incompatibleEmptyAndOverlongResponsesFail() throws {
        let guide = try catalog()
        for response in [PlateScanResponse(sourceSHA256: "wrong", items: []), .init(sourceSHA256: guide.sourceSHA256, items: []), .init(sourceSHA256: guide.sourceSHA256, items: Array(repeating: .init(label: "Food", foodID: nil, portions: nil, uncertainty: ""), count: 21))] {
            #expect(throws: Error.self) { try response.review(catalog: guide) }
        }
    }

    @Test func duplicateMatchesMergeAndRejectOverflow() throws {
        let guide = try catalog(), food = guide.foods.first { $0.available }!
        var items = [PlateScanItem(label: "A", food: food, portions: 0.5, uncertainty: "", confirmed: true), .init(label: "B", food: food, portions: 0.5, uncertainty: "", confirmed: true)]
        #expect(PlateScanReview.meal(items, catalog: guide)?.items.count == 1)
        #expect(PlateScanReview.meal(items, catalog: guide)?.carbsForReview == food.carbs)
        items[0].portions = 100
        #expect(PlateScanReview.meal(items, catalog: guide) == nil)
    }

    @Test func transportSendsOnlyPhotoAndFingerprintAndRejectsHTTPFailure() async throws {
        let guide = try catalog()
        let result = try await PlateScanClient.scan(jpeg: Data([255, 216, 255, 0]), endpoint: "https://example.test/scan", token: "private-service-token", catalog: guide) { request in
            #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer private-service-token")
            let body = try #require(JSONSerialization.jsonObject(with: request.httpBody!) as? [String: Any])
            #expect(Set(body.keys) == Set(["image", "sourceSHA256"]))
            #expect(body["sourceSHA256"] as? String == guide.sourceSHA256)
            let data = try JSONEncoder().encode(PlateScanResponse(sourceSHA256: guide.sourceSHA256, items: [.init(label: "Unknown food", foodID: nil, portions: nil, uncertainty: "Unclear")]))
            return (data, HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }
        #expect(result.count == 1)
        #expect(PlateScanReview.meal(result, catalog: guide) == nil)
        do {
            _ = try await PlateScanClient.scan(jpeg: Data([255, 216, 255, 0]), endpoint: "https://example.test/scan", token: "token", catalog: guide) { request in
                (Data(), HTTPURLResponse(url: request.url!, statusCode: 401, httpVersion: nil, headerFields: nil)!)
            }
            Issue.record("HTTP failure incorrectly accepted")
        } catch { #expect(error is PlateScanError) }
    }

    @Test func insecureAndCredentialBearingEndpointsAreRejected() {
        for url in ["http://example.com/scan", "https://user:secret@example.com/scan", "https://example.com/scan?key=secret", "https://example.com/#secret", "nonsense"] { #expect(PlateScanClient.endpoint(url) == nil) }
        #expect(PlateScanClient.endpoint("https://example.com/scan") != nil)
    }

    @Test func onDeviceLookupIsBoundedRelevantAndContainsNoNutrition() throws {
        let guide = try catalog()
        let matches = PlateScanLocalCatalog.matches("plain bagel", catalog: guide)
        #expect(!matches.isEmpty && matches.count <= 4)
        #expect(matches.contains { $0.id == "MG8D7CE49" })
        let json = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(matches)) as? [[String: Any]])
        #expect(json.allSatisfy { Set($0.keys) == Set(["id", "name", "venue", "portion"]) })
        #expect(PlateScanLocalCatalog.matches("the food on a plate", catalog: guide).isEmpty)
        #expect(PlateScanLocalCatalog.matches("unidentifiablexyz", catalog: guide).isEmpty)
    }

    @Test func nativeMatchesMustHaveBeenOfferedAndUnknownsStayVisible() throws {
        let guide = try catalog(), food = guide.foods.first { $0.available }!
        let response = PlateScanResponse(sourceSHA256: guide.sourceSHA256, items: [
            .init(label: "Unverified food", foodID: food.id, portions: 1, uncertainty: "Check preparation"),
            .init(label: "Unknown sauce", foodID: nil, portions: nil, uncertainty: "Unknown ingredients"),
        ])
        let blocked = PlateScanLocalCatalog.ground(response, offeredIDs: [])
        #expect(blocked.items.count == 2)
        #expect(blocked.items.allSatisfy { $0.foodID == nil && $0.portions == nil })
        #expect(try blocked.review(catalog: guide).allSatisfy { !$0.resolved && $0.portionNeedsEntry })
        let offered = PlateScanLocalCatalog.ground(response, offeredIDs: [food.id])
        #expect(offered.items[0].foodID == food.id)
        #expect(offered.items[1].foodID == nil)
    }
}
