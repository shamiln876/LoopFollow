// LoopFollow
// RiceMealPlanTests.swift

import Foundation
@testable import LoopFollow
import Testing

struct RiceMealPlanTests {
    @Test func editedUnitsReplaceSuggestedUnitsWithoutApplyingPercentageAgain() throws {
        let now = Date()
        let manual = try #require(RiceMealPlan(carbs: 80, fullRecommendation: 5.8, upfrontPercent: 75,
                                               confirmedAt: now, upfrontInsulinOverride: 0.65))
        #expect(manual.upfrontInsulin == 0.65)
        #expect(manual.suggestedUpfrontInsulin == 4.35)
        #expect(manual.usesManualBolus)
        #expect(manual.fullRecommendation == 5.8)
        #expect(manual.immediateCarbs == 60 && manual.delayedCarbs == 20)
        for invalid in [Double.nan, .infinity, -0.05, 0.67, 30.05] {
            #expect(RiceMealPlan(carbs: 80, fullRecommendation: 5.8, upfrontPercent: 75, confirmedAt: now, upfrontInsulinOverride: invalid) == nil)
        }
        #expect(RiceMealPlan(carbs: 80, fullRecommendation: 5.8, upfrontPercent: 75, confirmedAt: now, upfrontInsulinOverride: 0)?.upfrontInsulin == 0)
    }

    @Test func previewInvariants() {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        func plan(_ carbs: Double, _ full: Double = 5.8, _ percent: Double = 75) -> RiceMealPlan? {
            RiceMealPlan(carbs: carbs, fullRecommendation: full, upfrontPercent: percent, confirmedAt: date)
        }
        let rice = plan(80)!
        #expect(rice.immediateCarbs == 60 && rice.delayedCarbs == 20)
        #expect(rice.delayedDate.timeIntervalSince(date) == 1800)
        #expect(rice.fullRecommendation == 5.8 && rice.upfrontInsulin == 4.35)
        #expect(plan(80, 5.8, 60)!.upfrontInsulin == 3.45)
        #expect(plan(80, 5.8, 0)!.upfrontInsulin == 0)
        #expect(plan(80, 5.8, 100)!.upfrontInsulin == 5.8)
        for total in 4 ... 1000 {
            let p = plan(Double(total))!
            #expect(p.immediateCarbs + p.delayedCarbs == total)
            #expect(p.delayedCarbs > 0 && p.delayedInsulin == 0)
            #expect(abs(Double(p.delayedCarbs) - Double(total) * 0.25) <= 0.5)
        }
        for invalid in [Double.nan, .infinity, -.infinity, -1, 0, 4.5, 1001] {
            #expect(plan(invalid) == nil)
        }
        for invalid in [Double.nan, .infinity, -.infinity, -1, 101] {
            #expect(plan(80, invalid) == nil)
            #expect(plan(80, 5.8, invalid) == nil)
        }
        #expect(RiceMealPlan.sendingBlocker.contains("Nothing has been sent or scheduled"))
    }

    @Test func allPresetsAndIndependentControls() {
        let date = Date()
        for preset in SmartMealPreset.allCases {
            let p = RiceMealPlan(carbs: 80, fullRecommendation: 5.8, upfrontPercent: preset.insulinPercent,
                                 confirmedAt: date, carbsNowPercent: preset.carbsNowPercent, delayMinutes: preset.delayMinutes)!
            #expect(p.immediateCarbs + p.delayedCarbs == 80)
            #expect(p.delayedInsulin == 0)
            if preset == .pizza {
                #expect(p.immediateCarbs == 56 && p.delayedCarbs == 24)
                #expect(p.upfrontInsulin == 4.05)
                #expect(p.delayedDate.timeIntervalSince(date) == 3600)
            }
            if preset == .fruit { #expect(p.immediateCarbs == 80 && p.delayedCarbs == 0 && p.upfrontInsulin == 5.8) }
        }
        for total in 1 ... 1000 {
            for split in [0.0, 25, 70, 75, 100] {
                let p = RiceMealPlan(carbs: Double(total), fullRecommendation: 5.8, upfrontPercent: 60,
                                     confirmedAt: date, carbsNowPercent: split, delayMinutes: 60)!
                #expect(p.immediateCarbs + p.delayedCarbs == total)
                #expect(p.upfrontInsulin == 3.45)
            }
        }
        #expect(RiceMealPlan(carbs: 80, fullRecommendation: 5.8, upfrontPercent: 75, confirmedAt: date, carbsNowPercent: 75, delayMinutes: 0) == nil)
        for invalid in [Double.nan, .infinity, -1, 101] {
            #expect(RiceMealPlan(carbs: 80, fullRecommendation: 5.8, upfrontPercent: 75, confirmedAt: date, carbsNowPercent: invalid) == nil)
        }
    }

    @Test func fivePercentSelectionsKeepTheChosenCarbSplit() throws {
        for preset in SmartMealPreset.allCases {
            var previous = 0.0
            for percent in stride(from: 0.0, through: 100.0, by: 5.0) {
                let plan = try #require(RiceMealPlan(carbs: 80, fullRecommendation: 5.8, upfrontPercent: percent,
                                                     confirmedAt: Date(), carbsNowPercent: preset.carbsNowPercent,
                                                     delayMinutes: preset.delayMinutes, preset: preset))
                #expect(plan.immediateCarbs == (preset == .rice ? 60 : preset == .pizza ? 56 : 80))
                #expect(plan.immediateCarbs + plan.delayedCarbs == 80)
                #expect(plan.upfrontInsulin >= previous)
                #expect(plan.upfrontInsulin <= 5.8 * percent / 100 + 0.000001)
                #expect(plan.delayedInsulin == 0)
                previous = plan.upfrontInsulin
            }
        }
    }

    @Test func draftFreshnessAndHistoricalGuards() {
        let now = Date()
        let source = "https://example.invalid"
        func settings(_ date: Date, historical: String? = nil) -> MealReviewSettings {
            .init(percentage: 90, maxIOB: 10, maxCOB: 120, maxBolus: 10,
                  sourceFingerprint: MealReviewSettings.fingerprint(source), trioVersion: "1.0.2",
                  checkedAt: date, historicalReference: historical)
        }
        var snapshot = MealReviewSnapshot(date: now, carbRatio: 10, ratioSource: "Trio reported", iob: 1, iobDate: now, cob: 0)
        snapshot.trioVersion = "1.0.2"
        snapshot.reportedBolusIncrement = 0.05
        snapshot.pumpDate = now
        let plan = RiceMealPlan(carbs: 80, fullRecommendation: 5.8, upfrontPercent: 100,
                                confirmedAt: now, carbsNowPercent: 100, delayMinutes: 0)!
        for saved in [settings(now), settings(now, historical: "Historical"), settings(now.addingTimeInterval(-86401))] {
            let draft = SmartMealDraft(plan: plan, protein: 0, fat: 0, settings: saved, snapshot: snapshot, source: source, createdAt: now)
            #expect(draft.isCurrent(now: now, settings: saved, snapshot: snapshot, source: source) == (!saved.isHistorical && saved.checkedAt == now))
            #expect(!draft.isCurrent(now: now.addingTimeInterval(121), settings: saved, snapshot: snapshot, source: source))
            #expect(!draft.isCurrent(now: now, settings: saved, snapshot: snapshot, source: "other"))
            #expect(!draft.isCurrent(now: now, settings: nil, snapshot: snapshot, source: source))
            #expect(!draft.isCurrent(now: now, settings: saved, snapshot: nil, source: source))
        }
    }

    @Test func unchangedSettingsKeepVerificationWithoutRenewingIt() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let source = "https://example.invalid"
        func settings(_ date: Date, historical: String? = nil) -> MealReviewSettings {
            .init(percentage: 90, maxIOB: 10, maxCOB: 120, maxBolus: 10,
                  sourceFingerprint: MealReviewSettings.fingerprint(source), trioVersion: "1.0.2",
                  checkedAt: date, historicalReference: historical)
        }
        var saved = settings(now.addingTimeInterval(-60))
        saved.receiverConfigurationID = "paired-receiver"
        func retained(_ s: MealReviewSettings, percentage: Double? = nil, date: Date? = nil, connection: String? = nil) -> MealReviewSettings? {
            s.retainedIfUnchanged(percentage: percentage ?? s.percentage, maxIOB: s.maxIOB,
                                  maxCOB: s.maxCOB, maxBolus: s.maxBolus,
                                  source: connection ?? source, version: "1.0.2", now: date ?? now)
        }
        #expect(retained(saved) == saved)
        #expect(retained(saved)?.checkedAt == now.addingTimeInterval(-60))
        #expect(retained(saved)?.receiverConfigurationID == "paired-receiver")
        #expect(retained(saved, percentage: saved.percentage + 1) == nil)
        #expect(retained(saved, date: now.addingTimeInterval(86400)) == nil)
        #expect(retained(saved, connection: "another server") == nil)
        #expect(retained(settings(now, historical: "Unverified reference")) == nil)
    }

    @Test func pendingAttemptSurvivesRecreationAndRequiresReconciliation() {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let first = SmartMealSendJournal(directory: directory)
        #expect(!first.hasPending(source: "test"))
        #expect(first.claim(source: "test"))
        let restarted = SmartMealSendJournal(directory: directory)
        #expect(restarted.hasPending(source: "test"))
        #expect(!restarted.claim(source: "test"))
        #expect(restarted.reconcile(source: "test"))
        #expect(restarted.claim(source: "test"))
        #expect(restarted.claim(source: "other connection"))
        // A regular file cannot serve as the journal directory.
        let regular = directory.appendingPathComponent("file")
        try? Data().write(to: regular)
        #expect(!SmartMealSendJournal(directory: regular).claim(source: "test"))
    }

    @Test func fullCarbsThenExistingNinetyPercentThenPreset() {
        let settings = MealReviewSettings(percentage: 90, maxIOB: 20, maxCOB: 120, maxBolus: 10,
                                          sourceFingerprint: "fixture", trioVersion: "1.0.2", checkedAt: Date())
        let full = MealReviewFullCalculation.calculate(newCarbs: 80, cob: 0, ratio: 10,
                                                       glucose: 100, target: 100, isf: 40, iob: 0, delta: 0, settings: settings)!
        let rice = RiceMealPlan(carbs: 80, fullRecommendation: full.rounded, upfrontPercent: 75, confirmedAt: Date())!
        #expect(full.rounded == 7.2)
        #expect(rice.immediateCarbs == 60)
        #expect(rice.upfrontInsulin == 5.4)
        #expect(settings.percentage == 90)
    }

    @Test func automaticDraftNeedsNoTypedRecommendationAndRechecksFullMeal() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let source = "https://example.invalid"
        let saved = MealReviewSettings(percentage: 90, maxIOB: 20, maxCOB: 120, maxBolus: 10,
                                       sourceFingerprint: MealReviewSettings.fingerprint(source), trioVersion: "1.0.2", checkedAt: now)
        var snapshot = MealReviewSnapshot(date: now, carbRatio: 10, ratioSource: "Trio reported", iob: 0, iobDate: now, cob: 0)
        snapshot.effectiveISF = 40
        snapshot.isfSource = "Trio structured effective ISF"
        snapshot.targetMgdl = 100
        snapshot.calculationIOB = 0
        snapshot.minPredMgdl = 100
        snapshot.minGuardMgdl = 100
        snapshot.trioVersion = "1.0.2"
        snapshot.reportedBolusIncrement = 0.05
        snapshot.pumpDate = now
        let samples: [MealReviewCalculation.GlucoseSample] = [.init(date: now.addingTimeInterval(-900), mgdl: 100), .init(date: now, mgdl: 100)]
        func make(_ settings: MealReviewSettings = saved, full: Double = 7.2, protein: Double = 0) -> SmartMealDraft? {
            let plan = RiceMealPlan(carbs: 80, fullRecommendation: full, upfrontPercent: 75, confirmedAt: now)!
            return SmartMealDraft.make(plan: plan, protein: protein, fat: 0, settings: settings, snapshot: snapshot,
                                       source: source, samples: samples, newestTreatment: nil, now: now)
        }
        // No manually copied recommendation is supplied to the production factory.
        #expect(make()?.plan.upfrontInsulin == 5.4)
        #expect(make()?.plan.immediateCarbs == 60)
        #expect(make(full: 5.4) == nil) // Never calculate from only the 60 g now.
        #expect(make(protein: .nan) == nil)
        let historical = MealReviewSettings(percentage: 90, maxIOB: 20, maxCOB: 120, maxBolus: 10,
                                            sourceFingerprint: MealReviewSettings.fingerprint(source), trioVersion: "1.0.2", checkedAt: now, historicalReference: "Fixture")
        #expect(make(historical) == nil)
        let expired = MealReviewSettings(percentage: 90, maxIOB: 20, maxCOB: 120, maxBolus: 10,
                                         sourceFingerprint: MealReviewSettings.fingerprint(source), trioVersion: "1.0.2", checkedAt: now.addingTimeInterval(-86401))
        #expect(make(expired) == nil)
        snapshot.minGuardMgdl = 60
        #expect(MealReviewFullCalculation.comparison(newCarbs: 80, settings: saved, snapshot: snapshot, source: source,
                                                     samples: samples, newestTreatment: nil, now: now)?.rounded == 7.2)
        #expect(make() == nil) // A visible comparison never clears the low-forecast hold.
        snapshot.minGuardMgdl = 100
        snapshot.isfSource = "Trio reason (rounded)"
        #expect(make() == nil)
    }
}
