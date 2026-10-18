// LoopFollow
// SmartMealDeliveryTests.swift

import Foundation
@testable import LoopFollow
import Testing

struct SmartMealDeliveryTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private let source = "https://example.invalid/smart-meal"
    private let bundleID = "test.trio"
    private var configuration: SmartMealConfiguration {
        .init(percentage: 90, maxIOB: 10, maxCOB: 125, maxBolus: 9, maxCarbs: 150, maxFat: 100, maxProtein: 100, bolusIncrement: 0.05)
    }

    private func snapshot(date: Date? = nil) -> MealReviewSnapshot {
        var s = MealReviewSnapshot(date: date ?? now, carbRatio: 10, ratioSource: "Trio reported", iob: 1, iobDate: now, cob: 0)
        s.smartMeal = SmartMealReceiverStatus(protocolVersion: 1, generatedAt: now.timeIntervalSince1970, calculationAt: now.timeIntervalSince1970,
                                              bundleIdentifier: bundleID, enabled: true, configuration: configuration, receipts: [])
        s.trioVersion = "1.0.2"
        s.effectiveISF = 40; s.isfSource = "Trio structured effective ISF"
        s.targetMgdl = 100; s.minPredMgdl = 100; s.minGuardMgdl = 100
        s.activity = 0.01; s.calculationIOB = 1
        s.reportedBolusIncrement = 0.05; s.pumpDate = now; s.uploadUnitSource = "Trio mg/dL fields"
        return s
    }

    @Test func liveSettingsAreBoundToCurrentCycleAndPairedTrio() throws {
        let s = snapshot()
        let live = try #require(SmartMealDelivery.liveSettings(snapshot: s, source: source, bundleID: bundleID, now: now))
        #expect(!live.isHistorical && live.percentage == 90 && live.maxBolus == 9)
        #expect(live.receiverConfigurationID == configuration.identifier)
        #expect(SmartMealDelivery.liveSettings(snapshot: s, source: source, bundleID: "other", now: now) == nil)
        #expect(SmartMealDelivery.liveSettings(snapshot: s, source: "", bundleID: bundleID, now: now) == nil)
        #expect(SmartMealDelivery.liveSettings(snapshot: s, source: source, bundleID: bundleID, now: now.addingTimeInterval(601)) == nil)
        var mismatched = s
        mismatched.smartMeal = SmartMealReceiverStatus(protocolVersion: 1, generatedAt: now.timeIntervalSince1970,
                                                       calculationAt: now.addingTimeInterval(-300).timeIntervalSince1970, bundleIdentifier: bundleID, enabled: true, configuration: configuration, receipts: [])
        #expect(SmartMealDelivery.liveSettings(snapshot: mismatched, source: source, bundleID: bundleID, now: now) == nil)
        mismatched.smartMeal = nil
        #expect(SmartMealDelivery.liveSettings(snapshot: mismatched, source: source, bundleID: bundleID, now: now) == nil)
    }

    @Test func requestUsesFullCarbsExactEditedDoseAndConfirmationRelativeDelay() throws {
        let s = snapshot()
        let live = try #require(SmartMealDelivery.liveSettings(snapshot: s, source: source, bundleID: bundleID, now: now))
        let earlier = now.addingTimeInterval(-60)
        let plan = try #require(RiceMealPlan(carbs: 80, fullRecommendation: 5.8, upfrontPercent: 75,
                                             confirmedAt: earlier, upfrontInsulinOverride: 0.65))
        let draft = SmartMealDraft(plan: plan, protein: 0, fat: 0, settings: live, snapshot: s, source: source, createdAt: earlier)
        let request = try #require(SmartMealDelivery.request(draft: draft, bolus: plan.upfrontInsulin, protein: 0, fat: 0,
                                                             snapshot: s, settings: live, bundleID: bundleID, now: now))
        #expect(request.totalCarbs == 80 && request.immediateCarbs == 60 && request.delayedCarbs == 20)
        #expect(request.bolusAmount == Decimal(string: "0.65")!)
        #expect(request.fullRecommendation == Decimal(string: "5.8")!)
        #expect(request.delayedAt == now.addingTimeInterval(1800).timeIntervalSince1970)
        #expect(request.id == draft.transactionID && !request.includeFatProtein)
        let payload = CommandPayload(user: "test", commandType: .smartMeal, timestamp: request.confirmedAt, smartMeal: request)
        let json = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(payload)) as? [String: Any])
        #expect(json["bolus_amount"] == nil && json["carbs"] == nil && json["scheduled_time"] == nil)
        #expect(json["command_type"] as? String == "smart_meal")
        #expect(json["smart_meal"] != nil)
    }

    @Test func requestKeepsAuthoritativeCycleTimestampRatherThanRoundedDisplayDate() throws {
        let s = snapshot(date: now.addingTimeInterval(-0.5))
        let live = try #require(SmartMealDelivery.liveSettings(snapshot: s, source: source, bundleID: bundleID, now: now))
        let plan = try #require(RiceMealPlan(carbs: 80, fullRecommendation: 5.8, upfrontPercent: 75, confirmedAt: now))
        let draft = SmartMealDraft(plan: plan, protein: 0, fat: 0, settings: live, snapshot: s, source: source, createdAt: now)
        let request = try #require(SmartMealDelivery.request(draft: draft, bolus: 4.35, protein: 0, fat: 0,
                                                             snapshot: s, settings: live, bundleID: bundleID, now: now))
        #expect(request.calculationAt == s.smartMeal?.calculationAt)
        #expect(request.calculationAt != s.date?.timeIntervalSince1970)
    }

    @Test func explicitCaregiverCheckCanClearOnlyAnExpiredSenderAttempt() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let journal = SmartMealSendJournal(directory: root)
        let s = snapshot(); let live = try #require(SmartMealDelivery.liveSettings(snapshot: s, source: source, bundleID: bundleID, now: now))
        let plan = try #require(RiceMealPlan(carbs: 80, fullRecommendation: 5.8, upfrontPercent: 75, confirmedAt: now))
        let draft = SmartMealDraft(plan: plan, protein: 0, fat: 0, settings: live, snapshot: s, source: source, createdAt: now)
        let request = try #require(SmartMealDelivery.request(draft: draft, bolus: 4.35, protein: 0, fat: 0, snapshot: s, settings: live, bundleID: bundleID, now: now))
        #expect(journal.claim(request: request, source: source))
        #expect(!journal.reconcile(source: source, now: now.addingTimeInterval(120)))
        #expect(journal.hasPending(source: source))
        #expect(journal.reconcile(source: source, now: now.addingTimeInterval(121)))
        #expect(!journal.hasPending(source: source))
    }

    @Test func onlyExactFreshCorrelatedReceiptResolvesPendingAttempt() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let journal = SmartMealSendJournal(directory: root)
        let s = snapshot(); let live = try #require(SmartMealDelivery.liveSettings(snapshot: s, source: source, bundleID: bundleID, now: now))
        let plan = try #require(RiceMealPlan(carbs: 80, fullRecommendation: 5.8, upfrontPercent: 75, confirmedAt: now))
        let draft = SmartMealDraft(plan: plan, protein: 0, fat: 0, settings: live, snapshot: s, source: source, createdAt: now)
        let request = try #require(SmartMealDelivery.request(draft: draft, bolus: 4.35, protein: 0, fat: 0, snapshot: s, settings: live, bundleID: bundleID, now: now))
        #expect(journal.claim(request: request, source: source))
        #expect(!journal.claim(request: request, source: source))
        #expect(!journal.reconcile(source: source, now: now))
        func status(_ phase: SmartMealPhase) -> SmartMealReceiverStatus {
            .init(protocolVersion: 1, generatedAt: now.timeIntervalSince1970, calculationAt: now.timeIntervalSince1970,
                  bundleIdentifier: bundleID, enabled: true, configuration: configuration,
                  receipts: [.init(request: request, phase: phase, updatedAt: now.timeIntervalSince1970, message: "test")])
        }
        #expect(journal.receive(status(.accepted), source: source, bundleID: "other", now: now) == nil)
        #expect(journal.receive(status(.accepted), source: source, bundleID: bundleID, now: now.addingTimeInterval(601)) == nil)
        #expect(journal.hasPending(source: source))
        #expect(journal.receive(status(.bolusRequested), source: source, bundleID: bundleID, now: now)?.phase == .bolusRequested)
        #expect(journal.hasPending(source: source))
        let reloaded = SmartMealSendJournal(directory: root)
        #expect(reloaded.pendingRequest(source: source) == request)
        #expect(reloaded.receive(status(.accepted), source: source, bundleID: bundleID, now: now)?.phase == .accepted)
        #expect(!reloaded.hasPending(source: source))
        #expect(reloaded.lastReceipt(source: source)?.request == request)
    }
}
