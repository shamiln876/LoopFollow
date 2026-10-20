// LoopFollow
// MealReviewSettingsImport.swift

import Foundation

/// A local, one-use import for historical comparison values only. No delivery settings.
enum MealReviewSettingsImport {
    static let filename = "meal-review-historical-settings.json"

    static func candidate(data: Data, source: String, existing: MealReviewSettings?, now: Date) -> MealReviewSettings? {
        guard existing == nil, data.count <= 16384,
              let settings = try? JSONDecoder().decode(MealReviewSettings.self, from: data),
              settings.isHistorical,
              settings.matches(source: source, version: "1.0.2", now: now) else { return nil }
        return settings
    }

    @discardableResult
    static func consume(file: URL, source: String, saved: StorageValue<MealReviewSettings?>, now: Date) -> Bool {
        guard !StorageReadiness.isSuppressingWrites,
              FileManager.default.fileExists(atPath: file.path) else { return false }
        // Never leave a pending import to overwrite values the user saves later.
        defer { try? FileManager.default.removeItem(at: file) }
        guard let size = try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize,
              size <= 16384, let data = try? Data(contentsOf: file),
              let settings = candidate(data: data, source: source, existing: saved.value, now: now) else { return false }
        saved.value = settings
        return true
    }

    static func consumePending() {
        guard let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
        consume(file: documents.appendingPathComponent(filename), source: Storage.shared.url.value, saved: Storage.shared.mealReviewSettings, now: Date())
    }
}
