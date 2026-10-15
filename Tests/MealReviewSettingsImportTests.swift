// LoopFollow
// MealReviewSettingsImportTests.swift

import Foundation
@testable import LoopFollow
import Testing

struct MealReviewSettingsImportTests {
    private let source = "https://example.invalid/nightscout"
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    private func settings(historical: Bool = true, source: String? = nil, date: Date? = nil) -> MealReviewSettings {
        .init(percentage: 81, maxIOB: 6, maxCOB: 90, maxBolus: 4,
              sourceFingerprint: MealReviewSettings.fingerprint(source ?? self.source), trioVersion: "1.0.2", checkedAt: date ?? now,
              historicalReference: historical ? "Synthetic historical fixture; not verified current." : nil)
    }

    @Test func importsOnlyExplicitHistoricalValuesForMatchingConnection() throws {
        let original = settings()
        let data = try JSONEncoder().encode(original)
        let verifiedData = try JSONEncoder().encode(settings(historical: false))
        let futureData = try JSONEncoder().encode(settings(date: now.addingTimeInterval(61)))
        #expect(MealReviewSettingsImport.candidate(data: data, source: source, existing: nil, now: now) == original)
        #expect(MealReviewSettingsImport.candidate(data: data, source: "https://other.invalid", existing: nil, now: now) == nil)
        #expect(MealReviewSettingsImport.candidate(data: data, source: source, existing: settings(historical: false), now: now) == nil)
        #expect(MealReviewSettingsImport.candidate(data: verifiedData, source: source, existing: nil, now: now) == nil)
        #expect(MealReviewSettingsImport.candidate(data: futureData, source: source, existing: nil, now: now) == nil)
        #expect(MealReviewSettingsImport.candidate(data: Data("{}".utf8), source: source, existing: nil, now: now) == nil)
        #expect(MealReviewSettingsImport.candidate(data: Data(repeating: 0, count: 16385), source: source, existing: nil, now: now) == nil)
    }

    @Test func preservesLegacySettingsAndExplicitHistoricalProvenance() throws {
        let old = settings(historical: false)
        let decoded = try JSONDecoder().decode(MealReviewSettings.self, from: JSONEncoder().encode(old))
        #expect(decoded == old)
        #expect(!decoded.isHistorical)
        let historical = settings()
        #expect(historical.isHistorical)
        #expect(historical.matches(source: source, version: "1.0.2", now: now))
        let parameters: (MealReviewSettings) -> MealReviewFullCalculation.Result? = {
            MealReviewFullCalculation.calculate(newCarbs: 30, cob: 10, ratio: 12, glucose: 150, target: 100, isf: 50, iob: 1, delta: 0, settings: $0)
        }
        #expect(parameters(old)?.rounded == parameters(historical)?.rounded)
    }

    @Test @MainActor func consumesOnceAndNeverReplacesExistingSettings() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent(MealReviewSettingsImport.filename)
        let store = StorageValue<MealReviewSettings?>(key: "test_historical_import_\(UUID().uuidString)", defaultValue: nil)
        defer { store.remove() }
        try JSONEncoder().encode(settings()).write(to: file)
        #expect(MealReviewSettingsImport.consume(file: file, source: source, saved: store, now: now))
        #expect(store.value == settings())
        #expect(!FileManager.default.fileExists(atPath: file.path))
        let verified = settings(historical: false)
        store.value = verified
        try JSONEncoder().encode(settings()).write(to: file)
        #expect(!MealReviewSettingsImport.consume(file: file, source: source, saved: store, now: now))
        #expect(store.value == verified)
        #expect(!FileManager.default.fileExists(atPath: file.path))
    }
}
