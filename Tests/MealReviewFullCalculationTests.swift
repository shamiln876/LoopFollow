// LoopFollow
// MealReviewFullCalculationTests.swift

import Foundation
@testable import LoopFollow
import Testing

struct MealReviewFullCalculationTests {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)
    private let source = "https://example.invalid/nightscout"
    private func settings(percentage: Double = 80, maxIOB: Double = 15, maxCOB: Double = 120, maxBolus: Double = 10) -> MealReviewSettings {
        .init(percentage: percentage, maxIOB: maxIOB, maxCOB: maxCOB, maxBolus: maxBolus, sourceFingerprint: MealReviewSettings.fingerprint(source), trioVersion: "1.0.2", checkedAt: now)
    }

    private func calculation(_ settings: MealReviewSettings, newCarbs: Double = 80, iob: Double = 1) -> MealReviewFullCalculation.Result? {
        MealReviewFullCalculation.calculate(newCarbs: newCarbs, cob: 20, ratio: 10, glucose: 180, target: 100, isf: 40, iob: iob, delta: 5, settings: settings)
    }

    @Test func trioSourceFixtureAndEachLimit() {
        let r = calculation(settings())!
        #expect(r.balance == 11.125)
        #expect(r.afterPercentage == 8.9)
        #expect(r.rounded == 8.9)
        let cob = calculation(settings(maxCOB: 60))!
        #expect(cob.cappedCarbs == 60)
        #expect(cob.balance == 7.125)
        #expect(cob.rounded == 5.7)
        let bolus = calculation(settings(maxBolus: 2.07))!
        #expect(bolus.afterBolusLimit == 2.07)
        #expect(bolus.rounded == 2.05)
        let iob = calculation(settings(maxIOB: 1.12))!
        #expect(iob.afterIOBLimit == 0.12)
        #expect(iob.rounded == 0.1)
        #expect(calculation(settings(maxIOB: 0))?.rounded == 0)
        #expect(calculation(settings(maxBolus: 0))?.rounded == 0)
    }

    @Test func negativeBalanceDoesNotGetFactoredOrBecomeNegativeDose() {
        let r = MealReviewFullCalculation.calculate(newCarbs: 0, cob: 0, ratio: 10, glucose: 100, target: 100, isf: 40, iob: 10, delta: 0, settings: settings())!
        #expect(r.balance == -10)
        #expect(r.afterPercentage == -10)
        #expect(r.rounded == 0)
        #expect(calculation(settings(maxIOB: 1), iob: 10)?.rounded == 0)
    }

    @Test func dashRoundingDoesNotRoundUpAcrossLimits() {
        for limit in [0.0, 0.049, 0.05, 0.099, 0.1, 0.29, 0.3, 1.999, 2.05, 5.7, 8.9, 30] {
            let r = calculation(settings(percentage: 150, maxBolus: limit))!
            #expect(r.rounded <= limit)
            let nativeAllowed = (1 ... 600).map { Double($0) / 20 }.last { $0 <= r.afterIOBLimit } ?? 0
            #expect(r.rounded == nativeAllowed)
        }
        for step in 1 ... 600 {
            let boundary = Double(step) / 20
            let r = calculation(settings(percentage: 150, maxIOB: 100, maxBolus: boundary))!
            #expect(r.rounded == min(boundary, 16.65)) // 11.125 × 1.5 = 16.6875, rounded down.
        }
    }

    @Test func settingsAreNotGuessedOrSharedAcrossConnections() throws {
        let s = settings()
        #expect(s.matches(source: source, version: "1.0.2", now: now))
        #expect(!s.matches(source: "https://another.invalid", version: "1.0.2", now: now))
        #expect(!s.matches(source: source, version: "1.0.3", now: now))
        #expect(!s.matches(source: source, version: "1.0.2", now: now.addingTimeInterval(-61)))
        #expect(!s.matches(source: "", version: "1.0.2", now: now))
        #expect(MealReviewFullCalculation.reasons(settings: nil, snapshot: nil, source: source, now: now).contains { $0.contains("Copy") })
        let data = try JSONEncoder().encode(s)
        #expect(!String(decoding: data, as: UTF8.self).contains(source))
        #expect(try JSONDecoder().decode(MealReviewSettings.self, from: data) == s)
        for invalid in [settings(percentage: 0), settings(percentage: 151), settings(maxIOB: -1), settings(maxCOB: -1), settings(maxBolus: 31), settings(maxIOB: .nan)] {
            #expect(!invalid.numbersValid)
            #expect(calculation(invalid) == nil)
        }
    }

    @Test func fullReviewRequiresFreshMatchingPumpAndContext() {
        var s = MealReviewSnapshot(date: now, carbRatio: 10, ratioSource: "Trio reported", iob: 1, iobDate: now, cob: 20)
        s.calculationIOB = 1
        s.effectiveISF = 40
        s.targetMgdl = 100
        s.minPredMgdl = 100
        s.minGuardMgdl = 100
        s.trioVersion = "1.0.2"
        let readings: [MealReviewCalculation.GlucoseSample] = [.init(date: now.addingTimeInterval(-900), mgdl: 175), .init(date: now, mgdl: 180)]
        func review(_ settings: MealReviewSettings? = nil) -> MealReviewFullCalculation.Result? {
            MealReviewFullCalculation.review(newCarbs: 80, settings: settings, snapshot: s, source: source, samples: readings, newestTreatment: nil, now: now)
        }
        #expect(review() == nil)
        #expect(review(settings()) == nil)
        s.reportedBolusIncrement = 0.05
        s.pumpDate = now
        #expect(review(settings())?.rounded == 8.9)
        s.reportedBolusIncrement = 0.1
        #expect(review(settings()) == nil)
        s.reportedBolusIncrement = 0.05
        s.pumpDate = now.addingTimeInterval(-601)
        #expect(review(settings()) == nil)
        s.pumpDate = now
        s.minGuardMgdl = 60
        #expect(review(settings()) == nil)
    }

    @Test func extremeOrMalformedNumbersFailClosed() {
        for value in [Double.nan, .infinity, 1e300] {
            #expect(calculation(settings(), newCarbs: value) == nil)
        }
        #expect(calculation(settings(maxIOB: 1e300)) == nil)
        #expect(MealReviewFullCalculation.calculate(newCarbs: 10, cob: 0, ratio: Double.leastNonzeroMagnitude, glucose: 100, target: 100, isf: 40, iob: 0, delta: 0, settings: settings()) == nil)
    }

    @Test func pumpMetadataMustBeReportedNotDefaulted() {
        let record: [String: AnyObject] = ["version": "1.0.2" as AnyObject, "suggested": ["timestamp": "2023-11-14T22:13:20Z"] as AnyObject]
        let missing = MealReviewSnapshot.parse(record, profileRatio: nil)!
        #expect(missing.reportedBolusIncrement == nil)
        let reported = MealReviewSnapshot.parse(record, profileRatio: nil, pumpRecord: ["clock": "2023-11-14T22:13:20Z" as AnyObject, "bolusIncrement": 0.05 as AnyObject])!
        #expect(reported.reportedBolusIncrement == 0.05)
        #expect(reported.pumpDate == now)
    }
}
