// LoopFollow
// MealReviewSnapshotTests.swift

import Foundation
@testable import LoopFollow
import Testing

struct MealReviewSnapshotTests {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)
    private func snapshot(cr: Any = 20.0, cob: Any? = 0.0, iob: Any? = 0.3, time: String? = "2023-11-14T22:13:20Z") -> MealReviewSnapshot {
        var calculation: [String: Any] = ["timestamp": "2023-11-14T22:13:20Z", "CR": cr]
        calculation["COB"] = cob
        var insulin: [String: Any] = [:]
        insulin["iob"] = iob
        insulin["time"] = time
        return MealReviewSnapshot.parse(["suggested": calculation as AnyObject, "iob": insulin as AnyObject], profileRatio: nil)!
    }

    @Test func freshArithmetic() {
        #expect(snapshot().carbEquivalent(carbs: 30, glucose: 100, glucoseDate: now, now: now) == 1.5)
    }

    @Test func missingIsNotZero() {
        for s in [snapshot(cob: nil), snapshot(iob: nil), snapshot(time: nil), snapshot(cr: 0), snapshot(cr: -1)] {
            #expect(s.carbEquivalent(carbs: 30, glucose: 100, glucoseDate: now, now: now) == nil)
        }
        #expect(snapshot(iob: 0).carbEquivalent(carbs: 30, glucose: 100, glucoseDate: now, now: now) == 1.5)
    }

    @Test func lowStaleFutureAndInvalidData() {
        #expect(snapshot().carbEquivalent(carbs: 30, glucose: 69, glucoseDate: now, now: now) == nil)
        for date in [now.addingTimeInterval(-601), now.addingTimeInterval(61)] {
            #expect(snapshot().carbEquivalent(carbs: 30, glucose: 100, glucoseDate: date, now: now) == nil)
        }
        #expect(snapshot().carbEquivalent(carbs: .nan, glucose: 100, glucoseDate: now, now: now) == nil)
        #expect(snapshot().carbEquivalent(carbs: 30, glucose: 100, glucoseDate: now, now: now.addingTimeInterval(601)) == nil)
        #expect(MealReviewSnapshot.number(true) == nil)
        #expect(MealReviewSnapshot.number(Double.infinity) == nil)
    }

    @Test func failedAndReplacementRecords() {
        #expect(MealReviewSnapshot.parse(["failureReason": "failed" as AnyObject], profileRatio: 20) == nil)
        #expect(snapshot(cob: nil).cob == nil)
        #expect(snapshot(cob: -1).cob == nil)
    }

    @Test func reasonAndProfileFallback() {
        let record: [String: AnyObject] = ["enacted": ["CR": 0, "reason": "CR: 25, COB: 10", "deliverAt": "2023-11-14T22:13:20.000Z"] as AnyObject]
        let s = MealReviewSnapshot.parse(record, profileRatio: 30)!
        #expect(s.carbRatio == 25)
        #expect(s.cob == 10)
        #expect(s.date == now)
        #expect(s.ratioSource == "Trio reported")
        let fallback = MealReviewSnapshot.parse(["suggested": [:] as AnyObject], profileRatio: 30)!
        #expect(fallback.carbRatio == 30)
        #expect(fallback.ratioSource == "Scheduled profile fallback")
        #expect(fallback.carbEquivalent(carbs: 30, glucose: 100, glucoseDate: now, now: now) == nil)
    }

    @Test func flatArrowWithNegativeChangeShowsReferenceAndNotice() {
        #expect(MealReviewSnapshot.trendNotice(delta: -1, trend: "Flat") == .negativeChange)
        #expect(snapshot(cr: 12).reviewEquivalent(carbs: 25, glucose: 162, glucoseDate: now, delta: -4, trend: "Flat", now: now) == 25.0 / 12.0)
        #expect(MealReviewSnapshot.trendNotice(delta: 0, trend: "Flat") == nil)
        #expect(snapshot().reviewEquivalent(carbs: 10, glucose: 166, glucoseDate: now, delta: 0, trend: "Flat", now: now) == 0.5)
    }

    @Test func referenceStillBlocksLowStaleAndMissingData() {
        #expect(snapshot().reviewEquivalent(carbs: 25, glucose: 69, glucoseDate: now, delta: -4, trend: "Flat", now: now) == nil)
        #expect(snapshot().reviewEquivalent(carbs: 25, glucose: 162, glucoseDate: now.addingTimeInterval(-601), delta: -4, trend: "Flat", now: now) == nil)
        #expect(snapshot(iob: nil).reviewEquivalent(carbs: 25, glucose: 162, glucoseDate: now, delta: -4, trend: "Flat", now: now) == nil)
        #expect(snapshot(cob: nil).reviewEquivalent(carbs: 25, glucose: 162, glucoseDate: now, delta: -4, trend: "Flat", now: now) == nil)
    }

    @Test func downwardArrowAndMissingTrendAreReviewNotices() {
        #expect(MealReviewSnapshot.trendNotice(delta: 1, trend: "SingleDown") == .downwardArrow)
        #expect(snapshot().reviewEquivalent(carbs: 10, glucose: 166, glucoseDate: now, delta: 1, trend: "SingleDown", now: now) == 0.5)
        #expect(MealReviewSnapshot.trendNotice(delta: nil, trend: nil) == .unavailable)
        #expect(snapshot().reviewEquivalent(carbs: 10, glucose: 166, glucoseDate: now, delta: nil, trend: nil, now: now) == 0.5)
        #expect(MealReviewSnapshot.trendNotice(delta: nil, trend: "Flat") == nil)
    }

    @Test func receiverDecimalRoundTripPreservesConfigurationAndReceiptIdentity() throws {
        let configuration = SmartMealConfiguration(percentage: 90, maxIOB: 10, maxCOB: 125, maxBolus: 9,
                                                   maxCarbs: 150, maxFat: 250, maxProtein: 250, bolusIncrement: 0.05)
        let request = SmartMealRequest(id: UUID(), confirmedAt: now.timeIntervalSince1970 + 0.123456,
                                       calculationAt: now.timeIntervalSince1970, configurationID: configuration.identifier,
                                       immediateCarbs: 60, delayedCarbs: 20, delaySeconds: 1800,
                                       fullRecommendation: 5.8, upfrontPercent: 75, bolusAmount: 0.65,
                                       includeFatProtein: false, protein: 0, fat: 0)
        let status = SmartMealReceiverStatus(protocolVersion: 1, generatedAt: now.timeIntervalSince1970 + 0.3,
                                             calculationAt: now.timeIntervalSince1970, bundleIdentifier: "test.trio", enabled: true,
                                             configuration: configuration,
                                             receipts: [.init(request: request, phase: .accepted, updatedAt: now.timeIntervalSince1970 + 0.234567, message: "test")])
        let wire = try JSONSerialization.jsonObject(with: JSONEncoder().encode(status))
        let record: [String: AnyObject] = ["version": "1.0.2" as AnyObject,
                                           "suggested": ["deliverAt": "2023-11-14T22:13:20.000Z", "CR": 10] as AnyObject,
                                           "smartMeal": wire as AnyObject]
        let snapshot = try #require(MealReviewSnapshot.parse(record, profileRatio: nil))
        let parsed = try #require(snapshot.smartMeal)
        #expect(parsed == status)
        #expect(parsed.configuration.bolusIncrement == Decimal(string: "0.05")!)
        #expect(parsed.configuration.identifier == configuration.identifier)
        #expect(parsed.receipts.first?.request.digest == request.digest)
        let live = try #require(SmartMealDelivery.liveSettings(snapshot: snapshot, source: "https://example.invalid", bundleID: "test.trio", now: now.addingTimeInterval(1)))
        #expect(live.receiverConfigurationID == configuration.identifier)
        #expect(SmartMealDelivery.liveSettings(snapshot: snapshot, source: "https://example.invalid", bundleID: "other.trio", now: now.addingTimeInterval(1)) == nil)
        #expect(SmartMealDelivery.liveSettings(snapshot: snapshot, source: "https://example.invalid", bundleID: "test.trio", now: now.addingTimeInterval(601)) == nil)
    }

    @Test func receiverNormalizationDoesNotRoundAnInvalidPumpStepIntoValidity() throws {
        for increment in [NSNumber(value: 0.051), NSDecimalNumber(string: "0.050000000000000003")] {
            let wire: [String: Any] = ["protocolVersion": 1, "generatedAt": now.timeIntervalSince1970,
                                       "calculationAt": now.timeIntervalSince1970, "bundleIdentifier": "test.trio", "enabled": true,
                                       "receipts": [], "configuration": ["percentage": 90, "maxIOB": 10, "maxCOB": 125, "maxBolus": 9,
                                                                         "maxCarbs": 150, "maxFat": 250, "maxProtein": 250, "bolusIncrement": increment]]
            let record: [String: AnyObject] = ["version": "1.0.2" as AnyObject,
                                               "suggested": ["deliverAt": "2023-11-14T22:13:20.000Z", "CR": 10] as AnyObject,
                                               "smartMeal": wire as AnyObject]
            let snapshot = try #require(MealReviewSnapshot.parse(record, profileRatio: nil))
            #expect(snapshot.smartMeal?.configuration.valid != true)
            #expect(SmartMealDelivery.liveSettings(snapshot: snapshot, source: "https://example.invalid", bundleID: "test.trio", now: now) == nil)
        }
    }
}
