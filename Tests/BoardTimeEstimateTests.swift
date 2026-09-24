// LoopFollow
// BoardTimeEstimateTests.swift

import Foundation
@testable import LoopFollow
import Testing

struct BoardTimeEstimateTests {
    let now = Date(timeIntervalSince1970: 1_700_000_000)

    @Test("insulin curve starts at full dose and reaches zero at DIA")
    func exponentialCurveEndpoints() {
        #expect(BoardTimeEstimate.fractionRemaining(minutes: 0) == 1)
        #expect(BoardTimeEstimate.fractionRemaining(minutes: 360) == 0)
        #expect(BoardTimeEstimate.fractionRemaining(minutes: 120) >
            BoardTimeEstimate.fractionRemaining(minutes: 240))
    }

    @Test("small new SMB does not restart an older bolus tail")
    func newSMB() {
        let old = BoardTimeEstimate.Dose(units: 2, date: now.addingTimeInterval(-4 * 3600))
        let tiny = BoardTimeEstimate.Dose(units: 0.05, date: now)
        let end = BoardTimeEstimate.insulinEnd(doses: [old, tiny], now: now)
        #expect(end != nil)
        #expect(end!.timeIntervalSince(now) < 3 * 3600)
    }

    @Test("carb estimate needs a recent, falling trace after food")
    func carbTrend() {
        let samples = [
            BoardTimeEstimate.CarbSample(grams: 30, date: now.addingTimeInterval(-30 * 60)),
            BoardTimeEstimate.CarbSample(grams: 25, date: now.addingTimeInterval(-20 * 60)),
            BoardTimeEstimate.CarbSample(grams: 20, date: now.addingTimeInterval(-10 * 60)),
        ]
        let meal = now.addingTimeInterval(-60 * 60)
        let end = BoardTimeEstimate.carbEnd(samples: samples, mostRecentCarb: meal, now: now)
        #expect(end != nil)
        #expect(abs(end!.timeIntervalSince(now) / 60 - 30) < 1)
        #expect(BoardTimeEstimate.carbEnd(samples: samples, mostRecentCarb: now, now: now) == nil)
        let flat = Array(samples.dropLast()) + [BoardTimeEstimate.CarbSample(grams: 25, date: now.addingTimeInterval(-10 * 60))]
        #expect(BoardTimeEstimate.carbEnd(samples: flat, mostRecentCarb: meal, now: now) == nil)
    }
}
