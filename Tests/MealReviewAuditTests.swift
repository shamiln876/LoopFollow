// LoopFollow
// MealReviewAuditTests.swift

import Foundation
@testable import LoopFollow
import Testing

struct MealReviewAuditTests {
    private let now = Date()
    private let source = "https://example.invalid/private-connection"

    private func payload(carbs: Double = 25, held: Bool = false) -> MealReviewAudit.Payload {
        var snapshot = MealReviewSnapshot(date: now, carbRatio: 12, ratioSource: "Trio reported", iob: 1, iobDate: now, cob: 5)
        snapshot.effectiveISF = 50
        snapshot.isfSource = "Trio structured effective ISF"
        snapshot.targetMgdl = 100
        snapshot.minPredMgdl = 100
        snapshot.minGuardMgdl = 100
        snapshot.calculationIOB = 1
        snapshot.trioVersion = "1.0.2"
        snapshot.reportedBolusIncrement = 0.05
        snapshot.pumpDate = now
        let settings = MealReviewSettings(percentage: 80, maxIOB: 6, maxCOB: 90, maxBolus: 4, sourceFingerprint: MealReviewSettings.fingerprint(source), trioVersion: "1.0.2", checkedAt: now)
        return MealReviewAudit.Payload.capture(carbs: carbs, source: source, settings: settings, snapshot: held ? nil : snapshot,
                                               glucose: [.init(date: now.addingTimeInterval(-900), mgdl: 140), .init(date: now, mgdl: 150)], newestTreatment: nil, sensorArrow: "Flat", now: now)!
    }

    private func entry(_ payload: MealReviewAudit.Payload, session: UUID = UUID(), kind: MealReviewAudit.Entry.Kind = .comparisonDisplayed) -> MealReviewAudit.Entry {
        .init(kind: kind, session: session, capturedAt: now, evaluatedAt: now, payload: payload, appBuild: "test", sourceRevision: "fixture")
    }

    private func records(_ directory: URL) throws -> [MealReviewAudit.Entry] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        return try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil).filter { $0.pathExtension == "jsonl" }.flatMap { file in
            try Data(contentsOf: file).split(separator: 0x0A).map { try decoder.decode(MealReviewAudit.Entry.self, from: Data($0)) }
        }
    }

    @Test func capturesExactInputsAndExperimentalResultWithoutConnectionCredentials() throws {
        let p = payload()
        #expect(p.result != nil)
        #expect(p.holdReasons.isEmpty)
        #expect(p.recentDelta == 10)
        #expect(p.result?.iobCreditUnits == -1)
        let data = try MealReviewAudit.encoder().encode(entry(p))
        #expect(!String(decoding: data, as: UTF8.self).contains(source))
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        let restored = try decoder.decode(MealReviewAudit.Entry.self, from: data)
        #expect(restored.payload.result == p.result)
        let expectedSettings = try #require(p.settings)
        let savedSettings = try #require(restored.payload.settings)
        // JSON millisecond dates can acquire sub-microsecond floating-point drift.
        #expect(abs(savedSettings.checkedAt.timeIntervalSince(expectedSettings.checkedAt)) < 0.001)
        let comparableSettings = MealReviewSettings(percentage: savedSettings.percentage, maxIOB: savedSettings.maxIOB,
            maxCOB: savedSettings.maxCOB, maxBolus: savedSettings.maxBolus, sourceFingerprint: savedSettings.sourceFingerprint,
            trioVersion: savedSettings.trioVersion, checkedAt: expectedSettings.checkedAt, historicalReference: savedSettings.historicalReference)
        #expect(comparableSettings == expectedSettings)
        #expect(abs(restored.evaluatedAt.timeIntervalSince(now)) < 0.001)
    }

    @Test func recordsHoldsAndRejectsEmptyOrInvalidCarbInput() {
        let p = payload(held: true)
        #expect(p.result == nil)
        #expect(!p.holdReasons.isEmpty)
        for carbs in [Double.nan, .infinity, -1, 0] {
            #expect(MealReviewAudit.Payload.capture(carbs: carbs, source: source, settings: nil, snapshot: nil, glucose: [], newestTreatment: nil, sensorArrow: nil, now: now) == nil)
        }
    }

    @Test func deduplicatesTicksButKeepsChangedComparisonsSessionsAndClosingEvent() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = MealReviewAuditStore(directory: directory)
        let session = UUID()
        store.record(entry(payload(), session: session))
        store.record(entry(payload(), session: session))
        store.record(entry(payload(carbs: 30), session: session))
        store.record(entry(payload(carbs: 30), session: session, kind: .reviewHidden))
        store.record(entry(payload(carbs: 30)))
        store.flush()
        let saved = try records(directory)
        #expect(saved.count == 4)
        #expect(saved.filter { $0.kind == .reviewHidden }.count == 1)
        #expect(saved.first?.payload.carbs == 25)
    }

    @Test func removesOnlyExpiredHistoryFiles() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let old = directory.appendingPathComponent("reviews-expired.jsonl")
        let unrelated = directory.appendingPathComponent("unrelated.txt")
        try Data("old".utf8).write(to: old)
        try Data("keep".utf8).write(to: unrelated)
        try FileManager.default.setAttributes([.modificationDate: now.addingTimeInterval(-15 * 86400)], ofItemAtPath: old.path)
        let store = MealReviewAuditStore(directory: directory)
        store.record(entry(payload()))
        store.flush()
        #expect(!FileManager.default.fileExists(atPath: old.path))
        #expect(FileManager.default.fileExists(atPath: unrelated.path))
        #expect(try records(directory).count == 1)
    }

    @Test func sizeLimitDoesNotPartiallyWriteAnEntry() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = MealReviewAuditStore(directory: directory, maximumBytes: 1)
        store.record(entry(payload()))
        store.flush()
        #expect(try records(directory).isEmpty)
    }
}
