// LoopFollow
// CarnivalFoodTests.swift

import Foundation
@testable import LoopFollow
import Testing

struct CarnivalFoodTests {
    private func guide() throws -> CarnivalFoodCatalog { try CarnivalFoodCatalog.bundled.get() }

    private func meal(_ food: CarnivalFood, portions: Double) throws -> CarnivalMeal {
        let guide = try guide()
        return CarnivalMeal(sourceFilename: guide.sourceFilename, sourceSHA256: guide.sourceSHA256, items: [.init(food: food, portions: portions)])
    }

    @Test func bundledPDFExtractionRetainsEveryFoodAndMissingRecipe() throws {
        let guide = try guide()
        #expect(guide.foods.count == 1085)
        #expect(guide.foods.filter(\.available).count == 1031)
        #expect(guide.foods.filter { $0.nutrition == .unavailable }.count == 54)
        #expect(guide.venues.count == 30)
        #expect(guide.sourceSHA256 == "fbf12613fa1574124e834424e077f7ea69b1af3615f0ab2645cb03e3e1074aa8")
        #expect(Set(guide.foods.map(\.id)).count == 1085)
    }

    @Test func exactPDFReferenceUsesTotalCarbsAndRetainsPrintedNetValue() throws {
        let bagel = try #require(guide().foods.first { $0.id == "MG8D7CE49" })
        #expect(bagel.name == "Bagel - Plain")
        #expect(bagel.portion == "1 medium bagel, 100 g")
        #expect(bagel.carbs == 52)
        #expect(bagel.netCarbs == 51)
        #expect(bagel.sourcePage == 5)
        let half = try meal(bagel, portions: 0.5)
        #expect(half.carbsForReview == 26)
        #expect(half.total(\.netCarbs) == 25.5)
        #expect(half.total(\.low) == 19.5)
        #expect(half.total(\.high) == 33)
    }

    @Test func quarterPortionsAndPieceCountsStayExact() throws {
        let guide = try guide()
        let food = try #require(guide.foods.first { $0.available && ($0.carbs ?? 0) > 0 })
        #expect(CarnivalNumber.text(0.25) == "0.25")
        #expect(try meal(food, portions: 0.25).total(\.carbs) == food.carbs! / 4)
        #expect(try meal(food, portions: 6).total(\.carbs) == food.carbs! * 6)
    }

    @Test func mixedPlateTotalsDoNotTreatMissingFoodAsZero() throws {
        let guide = try guide()
        let known = try #require(guide.foods.first { $0.available })
        let unknown = try #require(guide.foods.first { !$0.available })
        var plate = try meal(known, portions: 0.5)
        let second = try #require(guide.foods.first { $0.available && $0.id != known.id })
        plate.items.append(.init(food: second, portions: 2))
        #expect(plate.total(\.carbs) == known.carbs! * 0.5 + second.carbs! * 2)
        plate.items.append(.init(food: unknown, portions: 1))
        #expect(!plate.complete)
        #expect(plate.carbsForReview == nil)
        #expect(plate.total(\.low) == nil)
    }

    @Test func emptyDuplicateAndInvalidQuantitiesNeverProduceUsableTotals() throws {
        let food = try #require(guide().foods.first { $0.available })
        for quantity in [0, -1, 101, .infinity, .nan] {
            #expect(try meal(food, portions: quantity).carbsForReview == nil)
        }
        var plate = try meal(food, portions: 1)
        plate.items.append(.init(food: food, portions: 1))
        #expect(plate.carbsForReview == nil)
        plate.items = []
        #expect(plate.carbsForReview == nil)
    }

    @Test func offlineSearchHandlesWordsVenuesAccentsAndUnknownQueries() throws {
        let guide = try guide()
        let bagels = guide.search("plain BAGEL", venue: "Bagels @ Sea")
        #expect(bagels.contains { $0.id == "MG8D7CE49" })
        #expect(bagels.allSatisfy { $0.venue == "Bagels @ Sea" })
        #expect(!guide.search("JavaBlue Cafe").isEmpty)
        #expect(guide.search("no-such-food-zzzz").isEmpty)
        #expect(!guide.search("nugget").isEmpty)
        #expect(!guide.search("rice").isEmpty)
    }

    @Test func invalidCatalogDoesNotSilentlyDropBadRecords() throws {
        let url = try #require(Bundle.main.url(forResource: "CarnivalFoodGuide", withExtension: "json"))
        let original = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        var object = original
        var foods = try #require(object["foods"] as? [[String: Any]])
        foods.append(foods[0]); object["foods"] = foods
        #expect(throws: Error.self) { try CarnivalFoodCatalog.decode(JSONSerialization.data(withJSONObject: object)) }
        object = original; foods = try #require(object["foods"] as? [[String: Any]])
        foods[0]["carbs"] = -1; object["foods"] = foods
        #expect(throws: Error.self) { try CarnivalFoodCatalog.decode(JSONSerialization.data(withJSONObject: object)) }
    }

    @Test func reviewHistoryRoundTripsFoodProvenanceAndStillReadsLegacyRecords() throws {
        let food = try #require(guide().foods.first { $0.id == "MG8D7CE49" })
        let plate = try meal(food, portions: 0.5)
        let payload = try #require(MealReviewAudit.Payload.capture(carbs: plate.carbsForReview, source: "https://example.invalid", settings: nil, snapshot: nil, glucose: [], newestTreatment: nil, sensorArrow: nil, now: Date(), foodMeal: plate))
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .millisecondsSince1970
        let encoded = try MealReviewAudit.encoder().encode(payload)
        let decoded = try decoder.decode(MealReviewAudit.Payload.self, from: encoded)
        #expect(decoded.foodMeal == plate)
        #expect(decoded.carbs == 26)
        let edited = try #require(MealReviewAudit.Payload.capture(carbs: 27, source: "https://example.invalid", settings: nil, snapshot: nil, glucose: [], newestTreatment: nil, sensorArrow: nil, now: Date(), foodMeal: plate))
        #expect(edited.foodMeal == nil)
        var legacy = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        legacy.removeValue(forKey: "foodMeal")
        #expect(try decoder.decode(MealReviewAudit.Payload.self, from: JSONSerialization.data(withJSONObject: legacy)).foodMeal == nil)
    }
    @Test func roundedRemoteEntryRetainsFoodProvenanceWithoutSendingMacros() throws {
        let bagel = try #require(guide().foods.first { $0.id == "MG8D7CE49" })
        let chosen = try meal(bagel, portions: 0.3)
        let total = try #require(chosen.carbsForReview)
        let now = Date()
        let linked = MealReviewAudit.Payload.capture(carbs: total.rounded(), source: "https://example.invalid", settings: nil,
            snapshot: nil, glucose: [], newestTreatment: nil, sensorArrow: nil, now: now, foodMeal: chosen)
        #expect(linked?.foodMeal == chosen)
        let changed = MealReviewAudit.Payload.capture(carbs: total.rounded() + 1, source: "https://example.invalid", settings: nil,
            snapshot: nil, glucose: [], newestTreatment: nil, sensorArrow: nil, now: now, foodMeal: chosen)
        #expect(changed?.foodMeal == nil)
    }

}
