// LoopFollow
// MealDashboardTests.swift

import Foundation
@testable import LoopFollow
import Testing

enum MealDashboardFixture {
    static let source = "https://example.invalid/dashboard"

    static func snapshot(now: Date) -> MealReviewSnapshot {
        var s = MealReviewSnapshot(date: now, carbRatio: 10, ratioSource: "Trio reported", iob: 1, iobDate: now, cob: 20)
        s.effectiveISF = 40; s.targetMgdl = 100; s.activity = 0.01
        s.isfSource = "Trio structured effective ISF"
        s.calculationIOB = 1; s.minPredMgdl = 100; s.minGuardMgdl = 95
        s.trioVersion = "1.0.2"; s.reportedBolusIncrement = 0.05; s.pumpDate = now
        return s
    }

    static func readings(now: Date) -> [MealReviewCalculation.GlucoseSample] {
        (0 ..< 24).map { .init(date: now.addingTimeInterval(Double($0 - 23) * 300), mgdl: 140 + Double($0)) }
    }

    static func settings(now: Date) -> MealReviewSettings {
        .init(percentage: 80, maxIOB: 15, maxCOB: 120, maxBolus: 10, sourceFingerprint: MealReviewSettings.fingerprint(source), trioVersion: "1.0.2", checkedAt: now, historicalReference: "Synthetic fixture; not verified current.")
    }
}

struct MealDashboardTests {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    private func state(snapshot: MealReviewSnapshot? = nil, samples: [MealReviewCalculation.GlucoseSample]? = nil, treatment: Date? = nil, at: Date? = nil) -> MealDashboardStatus {
        MealDashboardStatus(snapshot: snapshot ?? MealDashboardFixture.snapshot(now: now), samples: samples ?? MealDashboardFixture.readings(now: now), newestTreatment: treatment, settings: MealDashboardFixture.settings(now: now), source: MealDashboardFixture.source, now: at ?? now)
    }

    @Test func inputReadinessDoesNotRequireMealOrClaimSettingsVerified() {
        let status = state()
        #expect(status.inputsAvailable)
        #expect(status.glucose?.mgdl == 163)
        #expect(status.title == "Live inputs available")
        #expect(MealDashboardFixture.settings(now: now).isHistorical)
    }

    @Test func cachedDataExpiresWithoutANewUpload() {
        #expect(state(at: now.addingTimeInterval(600)).inputsAvailable)
        let expired = state(at: now.addingTimeInterval(601))
        #expect(!expired.inputsAvailable)
        #expect(expired.reasons.contains { $0.contains("Glucose is missing or stale") })
        #expect(expired.reasons.contains { $0.contains("IOB is missing or stale") })
        #expect(MealDashboardFormat.age(now, now: now.addingTimeInterval(601)).contains("stale"))
        #expect(MealDashboardFormat.age(now.addingTimeInterval(61), now: now) == "clock mismatch")
    }

    @Test func newTreatmentAndMismatchedIOBPreventAvailableBadge() {
        #expect(!state(treatment: now.addingTimeInterval(10)).inputsAvailable)
        var s = MealDashboardFixture.snapshot(now: now)
        s.calculationIOB = 2
        #expect(!state(snapshot: s).inputsAvailable)
        s = MealDashboardFixture.snapshot(now: now)
        s.minGuardMgdl = 60
        #expect(!state(snapshot: s).inputsAvailable)
        #expect(!state(samples: [.init(date: now, mgdl: 60)]).inputsAvailable)
    }

    @Test func disconnectedOrUnconfiguredDashboardKeepsUnavailableInputsExplicit() {
        let missing = MealDashboardStatus(snapshot: nil, samples: [], newestTreatment: nil, settings: nil, source: "", now: now)
        #expect(!missing.inputsAvailable)
        #expect(missing.glucose == nil)
        #expect(!missing.reasons.isEmpty)
        #expect(MealDashboardFormat.number(nil, unit: "U") == "Unavailable")
        let wrongConnection = MealDashboardStatus(snapshot: MealDashboardFixture.snapshot(now: now), samples: MealDashboardFixture.readings(now: now), newestTreatment: nil, settings: MealDashboardFixture.settings(now: now), source: "https://another.invalid", now: now)
        #expect(!wrongConnection.inputsAvailable)
    }
}
