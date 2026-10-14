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
}
