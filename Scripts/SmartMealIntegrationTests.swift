// LoopFollow
// SmartMealIntegrationTests.swift

import Foundation
@testable import LoopFollow
import Testing
@testable import Trio

@Suite struct SmartMealIntegrationTests {
    @Test func postMealSettingCrossesActualWireWithoutTreatments() throws {
        let id = UUID()
        let request = LoopFollow.PostMealSMBSettingRequest(id: id, expectedRevision: "initial", enabled: false)
        let payload = LoopFollow.CommandPayload(user: "synthetic", commandType: .postMealSMB,
                                                timestamp: 1_800_000_000, postMealSMB: request)
        let decoded = try JSONDecoder().decode(Trio.CommandPayload.self, from: JSONEncoder().encode(payload))
        #expect(decoded.commandType == .postMealSMB)
        #expect(decoded.postMealSMB?.id == id)
        #expect(decoded.postMealSMB?.enabled == false)
        #expect(decoded.postMealSMB?.expectedRevision == "initial")
        #expect(decoded.carbs == nil && decoded.smartMeal == nil && decoded.bolusAmount == nil)
        let disable = try #require(decoded.postMealSMB)
        let disabled = try disable.applying(to: Trio.PostMealSMBStatus(enabled: true, revision: "initial", durationMinutes: 30))
        #expect(!disabled.enabled)
        #expect(try disable.applying(to: disabled) == disabled)
        let enable = Trio.PostMealSMBSettingRequest(id: UUID(), expectedRevision: disabled.revision, enabled: true)
        let enabled = try enable.applying(to: disabled)
        #expect(enabled.enabled)
        #expect(throws: (any Error).self) { try disable.applying(to: enabled) }
        let status = Trio.PostMealSMBStatus(enabled: false, revision: id.uuidString, durationMinutes: 30)
        let senderStatus = try JSONDecoder().decode(LoopFollow.PostMealSMBStatus.self, from: JSONEncoder().encode(status))
        #expect(senderStatus.revision == id.uuidString && !senderStatus.enabled && senderStatus.durationMinutes == 30)
    }

    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private let source = "https://example.invalid/integration"
    private let bundleID = "test.trio"
    private var config: LoopFollow.SmartMealConfiguration {
        .init(percentage: 90, maxIOB: 10, maxCOB: 125, maxBolus: 9,
              maxCarbs: 150, maxFat: 100, maxProtein: 100, bolusIncrement: 0.05)
    }

    private func senderRequest(_ preset: LoopFollow.SmartMealPreset, dose: Double? = nil, lowForecastReview: Bool = false) throws -> LoopFollow.SmartMealRequest {
        var snapshot = LoopFollow.MealReviewSnapshot(date: now, carbRatio: 10, ratioSource: "Trio reported", iob: 1, iobDate: now, cob: 0)
        snapshot.smartMeal = .init(protocolVersion: 1, generatedAt: now.timeIntervalSince1970,
                                   calculationAt: now.timeIntervalSince1970, bundleIdentifier: bundleID, enabled: true, configuration: config, receipts: [])
        snapshot.trioVersion = "1.0.2"; snapshot.effectiveISF = 40; snapshot.isfSource = "Trio structured effective ISF"
        snapshot.targetMgdl = 100; snapshot.minPredMgdl = 100; snapshot.minGuardMgdl = 100
        snapshot.activity = 0.01; snapshot.calculationIOB = 1; snapshot.reportedBolusIncrement = 0.05
        snapshot.pumpDate = now; snapshot.uploadUnitSource = "Trio mg/dL fields"
        if lowForecastReview {
            snapshot.minPredMgdl = 65; snapshot.minGuardMgdl = 29
            snapshot.smartMeal?.allowsLowPredictionReview = true
        }
        let settings = try #require(LoopFollow.SmartMealDelivery.liveSettings(snapshot: snapshot, source: source, bundleID: bundleID, now: now))
        let samples: [LoopFollow.MealReviewCalculation.GlucoseSample] = [.init(date: now.addingTimeInterval(-900), mgdl: 140), .init(date: now, mgdl: 140)]
        let full = try #require(LoopFollow.MealReviewFullCalculation.review(newCarbs: 80, settings: settings, snapshot: snapshot,
                                                                            source: source, samples: samples, newestTreatment: nil, now: now, allowLowPredictionReview: lowForecastReview))
        let proposedPlan = LoopFollow.RiceMealPlan(carbs: 80, fullRecommendation: full.rounded,
                                                   upfrontPercent: preset.insulinPercent, confirmedAt: now, carbsNowPercent: preset.carbsNowPercent,
                                                   delayMinutes: preset.delayMinutes, upfrontInsulinOverride: dose)
        let plan = try #require(proposedPlan)
        let draft = try #require(LoopFollow.SmartMealDraft.make(plan: plan, protein: 0, fat: 0, settings: settings,
                                                                snapshot: snapshot, source: source, samples: samples, newestTreatment: nil, now: now, lowPredictionAcknowledged: lowForecastReview))
        return try #require(LoopFollow.SmartMealDelivery.request(draft: draft, bolus: plan.upfrontInsulin,
                                                                 protein: 0, fat: 0, snapshot: snapshot, settings: settings, bundleID: bundleID, now: now))
    }

    private func decodeAtTrio(_ request: LoopFollow.SmartMealRequest) throws -> Trio.SmartMealRequest {
        let payload = LoopFollow.CommandPayload(user: "synthetic", commandType: .smartMeal, timestamp: request.confirmedAt, smartMeal: request)
        let wire = try JSONEncoder().encode(payload)
        let payloadAtTrio = try JSONDecoder().decode(Trio.CommandPayload.self, from: wire)
        #expect(payloadAtTrio.commandType == .smartMeal)
        #expect(payloadAtTrio.carbs == nil && payloadAtTrio.bolusAmount == nil && payloadAtTrio.scheduledTime == nil)
        let decoded = try #require(payloadAtTrio.smartMeal)
        if request.delayedCarbs > 0, request.delaySeconds == 2100 {
            #expect(decoded.delayedAt == request.confirmedAt + 2100)
        }
        let nativeConfig = try JSONDecoder().decode(Trio.SmartMealConfiguration.self, from: JSONEncoder().encode(config))
        #expect(nativeConfig.identifier == config.identifier)
        try decoded.validate(configuration: nativeConfig, now: now)
        return decoded
    }

    private actor Effects {
        var stored: [[Int]] = []; var boluses: [Decimal] = []
        func store(_ request: Trio.SmartMealRequest) { stored.append([request.immediateCarbs, request.delayedCarbs]) }
        func bolus(_ amount: Decimal) -> Bool { boluses.append(amount); return true }
        func counts() -> [Int] { [stored.count, boluses.count] }
    }

    @Test func reviewedLowForecastRoundTripsThroughActualCommandDecoderAndReceipt() async throws {
        let request = try senderRequest(.rice, dose: 0.65, lowForecastReview: true)
        let decoded = try decodeAtTrio(request)
        #expect(decoded.lowPredictionAcknowledged == true)
        #expect(decoded.bolusAmount == 0.65 && decoded.immediateCarbs == 60 && decoded.delayedCarbs == 20)
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let receiver = try Trio.SmartMealReceiver(file: root.appendingPathComponent("receiver.json"))
        let effects = Effects()
        let receipt = try await receiver.execute(decoded, now: now, validate: {
            guard Trio.SmartMealForecastPolicy.permits(glucose: 140, minimum: 65, guardMinimum: 29,
                                                       bolus: decoded.bolusAmount, acknowledged: decoded.lowPredictionAcknowledged == true)
            else { throw Trio.SmartMealError.contextChanged }
        }, store: { await effects.store(decoded) }, bolus: { await effects.bolus(decoded.bolusAmount) })
        #expect(receipt.phase == .accepted)
        let echoed = try JSONDecoder().decode(LoopFollow.SmartMealReceipt.self, from: JSONEncoder().encode(receipt))
        #expect(echoed.request == request)
        #expect(await effects.counts() == [1, 1])
    }

    @Test func allPresetsCrossActualCommandDecoderAndReturnCorrelatedReceipt() async throws {
        for preset in LoopFollow.SmartMealPreset.allCases {
            let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: root) }
            let request = try senderRequest(preset)
            let decoded = try decodeAtTrio(request)
            let receiver = try Trio.SmartMealReceiver(file: root.appendingPathComponent("receiver.json"))
            let effects = Effects()
            let journal = LoopFollow.SmartMealSendJournal(directory: root.appendingPathComponent("sender"))
            #expect(journal.claim(request: request, source: source))
            let receipt = try await receiver.execute(decoded, now: now, validate: {},
                                                     store: { await effects.store(decoded) }, bolus: { await effects.bolus(decoded.bolusAmount) })
            #expect(receipt.phase == .accepted && receipt.request.totalCarbs == 80)
            #expect(receipt.request.delayedAt == (preset.delayMinutes == 0 ? nil : now.addingTimeInterval(preset.delayMinutes * 60).timeIntervalSince1970))
            let nativeConfig = try JSONDecoder().decode(Trio.SmartMealConfiguration.self, from: JSONEncoder().encode(config))
            let status = Trio.SmartMealReceiverStatus(protocolVersion: 1, generatedAt: now.timeIntervalSince1970,
                                                      calculationAt: now.timeIntervalSince1970, bundleIdentifier: bundleID, enabled: true,
                                                      configuration: nativeConfig, receipts: [receipt])
            let returned = try JSONDecoder().decode(LoopFollow.SmartMealReceiverStatus.self, from: JSONEncoder().encode(status))
            #expect(journal.receive(returned, source: source, bundleID: bundleID, now: now)?.phase == .accepted)
            #expect(!journal.hasPending(source: source))
            let restarted = try Trio.SmartMealReceiver(file: root.appendingPathComponent("receiver.json"))
            _ = try await restarted.execute(decoded, now: now, validate: {}, store: { await effects.store(decoded) }, bolus: { await effects.bolus(decoded.bolusAmount) })
            #expect(await effects.counts() == [1, 1])
        }
    }

    @Test func editedUnitsAndZeroInsulinRemainExactAcrossBothApps() async throws {
        for amount in [0.65, 0.0] {
            let request = try senderRequest(.rice, dose: amount)
            let decoded = try decodeAtTrio(request)
            #expect(decoded.bolusAmount == Decimal(string: String(amount)))
            let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: root) }
            let receiver = try Trio.SmartMealReceiver(file: root.appendingPathComponent("receiver.json"))
            let effects = Effects()
            let receipt = try await receiver.execute(decoded, now: now, validate: {}, store: { await effects.store(decoded) }, bolus: { await effects.bolus(decoded.bolusAmount) })
            #expect(receipt.phase == .accepted)
            #expect(await effects.counts() == [1, amount > 0 ? 1 : 0])
        }
    }
}
