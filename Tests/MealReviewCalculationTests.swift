// LoopFollow
// MealReviewCalculationTests.swift

import Foundation
@testable import LoopFollow
import Testing

struct MealReviewCalculationTests {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)
    private var samples: [MealReviewCalculation.GlucoseSample] {
        [.init(date: now.addingTimeInterval(-900), mgdl: 175), .init(date: now, mgdl: 180)]
    }

    private func snapshot() -> MealReviewSnapshot {
        var s = MealReviewSnapshot(date: now, carbRatio: 10, ratioSource: "Trio reported", iob: 1, iobDate: now, cob: 20)
        s.effectiveISF = 40
        s.targetMgdl = 100
        s.activity = 0.01
        s.calculationIOB = 1
        s.minPredMgdl = 100
        s.minGuardMgdl = 100
        s.trioVersion = "1.0.2"
        return s
    }

    @Test func trioComponentFixture() {
        let result = MealReviewCalculation.review(newCarbs: 80, snapshot: snapshot(), samples: samples, newestTreatment: nil, now: now)!
        #expect(result.newCarbUnits == 8)
        #expect(result.existingCarbUnits == 2)
        #expect(result.correctionUnits == 2)
        #expect(result.trendUnits == 0.125)
        #expect(result.iobCreditUnits == -1)
        #expect(result.total == 11.125) // Before Trio's fraction, caps and rounding.
    }

    @Test func highIOBAndExistingCOBCoverage() {
        let noFood = MealReviewCalculation.balance(newCarbs: 25, cob: 0, carbRatio: 10, glucose: 100, target: 100, isf: 40, iob: 10, delta: 0)!
        let coveredFood = MealReviewCalculation.balance(newCarbs: 25, cob: 100, carbRatio: 10, glucose: 100, target: 100, isf: 40, iob: 10, delta: 0)!
        #expect(noFood.total == -7.5)
        #expect(coveredFood.total == 2.5)
        #expect(coveredFood.iobCreditUnits == -10)
        #expect(MealReviewCalculation.balance(newCarbs: 0, cob: 2.9, carbRatio: 10, glucose: 100, target: 100, isf: 40, iob: 0, delta: 0)?.existingCarbUnits == 0.2)
    }

    @Test func remainingIOBAndActivityAreDifferent() {
        // Same remaining IOB has different modeled immediate action; it is not
        // discounted again when current activity is smaller.
        #expect(MealReviewCalculation.insulinEffect(activity: 0.01, isf: 40) == -2)
        #expect(MealReviewCalculation.insulinEffect(activity: 0.001, isf: 40) == -0.2)
        #expect(MealReviewCalculation.insulinEffect(activity: -0.01, isf: 40) == 2)
        #expect(MealReviewCalculation.insulinEffect(activity: nil, isf: 40) == nil)
        #expect(MealReviewCalculation.insulinEffect(activity: .nan, isf: 40) == nil)
    }

    @Test func negativeIOBRepresentsBasalDeficit() {
        let b = MealReviewCalculation.balance(newCarbs: 10, cob: 0, carbRatio: 10, glucose: 100, target: 100, isf: 40, iob: -0.3, delta: 0)!
        #expect(abs(b.total - 1.3) < 0.000001)
        #expect(b.iobCreditUnits == 0.3)
    }

    @Test func twentyMinuteWindowDoesNotUseLastFiveMinuteDelta() {
        let readings: [MealReviewCalculation.GlucoseSample] = [
            .init(date: now.addingTimeInterval(-1200), mgdl: 99), // Strict boundary: excluded.
            .init(date: now.addingTimeInterval(-900), mgdl: 175),
            .init(date: now.addingTimeInterval(-300), mgdl: 179),
            .init(date: now, mgdl: 180),
            .init(date: now.addingTimeInterval(300), mgdl: 900), // Future: excluded.
        ]
        #expect(MealReviewCalculation.recentDelta(samples: readings.reversed(), now: now) == 5)
        #expect(MealReviewCalculation.recentDelta(samples: [.init(date: now, mgdl: 180)], now: now) == nil)
        #expect(MealReviewCalculation.recentDelta(samples: [.init(date: now, mgdl: 175), .init(date: now, mgdl: 180)], now: now) == nil)
    }

    @Test func newTreatmentsMustReachSnapshot() {
        #expect(MealReviewCalculation.review(newCarbs: 80, snapshot: snapshot(), samples: samples, newestTreatment: now.addingTimeInterval(6), now: now.addingTimeInterval(6)) == nil)
        #expect(MealReviewCalculation.review(newCarbs: 80, snapshot: snapshot(), samples: samples, newestTreatment: now.addingTimeInterval(-300), now: now) != nil)
        var mismatched = snapshot()
        mismatched.calculationIOB = 0.8
        #expect(MealReviewCalculation.review(newCarbs: 80, snapshot: mismatched, samples: samples, newestTreatment: nil, now: now) == nil)
        mismatched.calculationIOB = nil
        #expect(MealReviewCalculation.review(newCarbs: 80, snapshot: mismatched, samples: samples, newestTreatment: nil, now: now) == nil)
    }

    @Test func incompleteStaleOrLowDataBlocksReview() {
        #expect(MealReviewCalculation.review(newCarbs: 80, snapshot: nil, samples: samples, newestTreatment: nil, now: now) == nil)
        #expect(MealReviewCalculation.review(newCarbs: 80, snapshot: snapshot(), samples: samples, newestTreatment: nil, now: now.addingTimeInterval(601)) == nil)
        for key in ["ISF", "target", "guard", "prediction", "version", "ratio"] {
            var s = snapshot()
            switch key {
            case "ISF": s.effectiveISF = nil
            case "target": s.targetMgdl = nil
            case "guard": s.minGuardMgdl = nil
            case "prediction": s.minPredMgdl = nil
            case "version": s.trioVersion = "unknown"
            default: s = MealReviewSnapshot(date: now, carbRatio: 10, ratioSource: "Scheduled profile fallback", iob: 1, iobDate: now, cob: 20)
            }
            #expect(MealReviewCalculation.review(newCarbs: 80, snapshot: s, samples: samples, newestTreatment: nil, now: now) == nil)
        }
        for low in [true, false] {
            var s = snapshot()
            if low { s.minPredMgdl = 60 } else { s.minGuardMgdl = 60 }
            #expect(MealReviewCalculation.review(newCarbs: 80, snapshot: s, samples: samples, newestTreatment: nil, now: now) == nil)
        }
        #expect(MealReviewCalculation.review(newCarbs: 80, snapshot: snapshot(), samples: [.init(date: now.addingTimeInterval(-300), mgdl: 100), .init(date: now, mgdl: 69)], newestTreatment: nil, now: now) == nil)
    }

    @Test func invalidNumbersAndMismatchedTimes() {
        #expect(MealReviewCalculation.balance(newCarbs: .nan, cob: 0, carbRatio: 10, glucose: 100, target: 100, isf: 40, iob: 1, delta: 0) == nil)
        #expect(MealReviewCalculation.balance(newCarbs: 10, cob: -1, carbRatio: 10, glucose: 100, target: 100, isf: 40, iob: 1, delta: 0) == nil)
        let s = MealReviewSnapshot(date: now, carbRatio: 10, ratioSource: "Trio reported", iob: 1, iobDate: now.addingTimeInterval(-300), cob: 20)
        #expect(MealReviewCalculation.reasons(snapshot: s, samples: samples, newestTreatment: nil, now: now).contains { $0.contains("timestamps do not match") })
        let future = samples + [.init(date: now.addingTimeInterval(61), mgdl: 180)]
        #expect(MealReviewCalculation.review(newCarbs: 80, snapshot: snapshot(), samples: future, newestTreatment: nil, now: now) == nil)
        let bad = samples + [.init(date: now.addingTimeInterval(-1), mgdl: .nan)]
        #expect(MealReviewCalculation.review(newCarbs: 80, snapshot: snapshot(), samples: bad, newestTreatment: nil, now: now)?.total == 11.125)
    }

    @Test func mmolUploadDoesNotConvertStructuredISFOrForecastTwice() {
        let record: [String: AnyObject] = [
            "version": "1.0.2" as AnyObject,
            "recommendedBolus": 0.15 as AnyObject,
            "iob": ["iob": 0.4, "activity": 0.001, "time": "2023-11-14T22:13:20Z"] as AnyObject,
            "suggested": ["timestamp": "2023-11-14T22:13:20Z", "ISF": 35, "CR": 12, "COB": 0, "current_target": 8,
                          "reason": "ISF: 2.2→1.9, minPredBG: 7.1, minGuardBG: 6.8", "predBGs": ["IOB": [166, 150], "COB": [166, 175]]] as AnyObject,
        ]
        let s = MealReviewSnapshot.parse(record, profileRatio: nil, profileUnits: "mmol")!
        #expect(s.effectiveISF == 35)
        #expect(abs(s.targetMgdl! - 144.12472) < 0.0001)
        #expect(abs(s.minPredMgdl! - 7.1 * 18.01559) < 0.0001)
        #expect(abs(s.minGuardMgdl! - 6.8 * 18.01559) < 0.0001)
        #expect(s.predictions["IOB"] == [166, 150])
        #expect(s.nativeRecommendation == 0.15)
        #expect(s.activity == 0.001)
        let unknown = MealReviewSnapshot.parse(record, profileRatio: nil)!
        #expect(unknown.targetMgdl == nil)
        #expect(unknown.minPredMgdl == nil)
    }

    @Test func roundedReasonFallbackUsesFinalArrowValue() {
        let record: [String: AnyObject] = ["version": "1.0.2" as AnyObject, "suggested": ["timestamp": "2023-11-14T22:13:20Z", "ISF": 0, "current_target": 0, "reason": "ISF: 2.2→1.9, Target: 8.0, minPredBG: 7.1, minGuardBG: 6.8"] as AnyObject]
        let s = MealReviewSnapshot.parse(record, profileRatio: nil, profileUnits: "mmol/L")!
        #expect(abs(s.effectiveISF! - 1.9 * 18.01559) < 0.0001)
        #expect(s.isfSource == "Trio reason (rounded)")
        #expect(abs(s.targetMgdl! - 8 * 18.01559) < 0.0001)
    }

    @Test func cachedSuggestionKeepsOriginalMgdlUnits() {
        let record: [String: AnyObject] = ["version": "1.0.2" as AnyObject,
                                           "suggested": ["deliverAt": "2023-11-14T22:13:20Z", "ISF": 39, "current_target": 144, "reason": "ISF: 39→39, Target: 144, minPredBG -1, minGuardBG 61"] as AnyObject]
        let s = MealReviewSnapshot.parse(record, profileRatio: nil, profileUnits: "mmol")!
        #expect(s.targetMgdl == 144)
        #expect(s.effectiveISF == 39)
        #expect(s.minPredMgdl == -1)
        #expect(s.minGuardMgdl == 61)
        #expect(s.date == now)
    }

    @Test func malformedForecastDoesNotBecomeNumericData() {
        let record: [String: AnyObject] = ["version": "1.0.2" as AnyObject,
                                           "suggested": ["predBGs": ["IOB": [true, true], "COB": [100, 120], "UAM": [100, -1]]] as AnyObject]
        let s = MealReviewSnapshot.parse(record, profileRatio: nil, profileUnits: "mg/dL")!
        #expect(s.predictions["IOB"] == nil)
        #expect(s.predictions["UAM"] == nil)
        #expect(s.predictions["COB"] == [100, 120])
    }
}
