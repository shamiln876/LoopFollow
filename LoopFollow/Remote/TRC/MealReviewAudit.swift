// LoopFollow
// MealReviewAudit.swift

import Foundation

/// Local evidence of a displayed comparison, never an acceptance or delivery record.
enum MealReviewAudit {
    struct Payload: Codable, Equatable {
        let carbs: Double
        let sourceFingerprint: String
        let settings: MealReviewSettings?
        let snapshot: MealReviewSnapshot?
        let glucose: [MealReviewCalculation.GlucoseSample]
        let recentDelta: Double?
        let newestTreatment: Date?
        let result: MealReviewFullCalculation.Result?
        let holdReasons: [String]
        let sensorArrow: String?
        let foodMeal: CarnivalMeal?

        static func capture(carbs: Double?, source: String, settings: MealReviewSettings?, snapshot: MealReviewSnapshot?, glucose: [MealReviewCalculation.GlucoseSample], newestTreatment: Date?, sensorArrow: String?, now: Date, foodMeal: CarnivalMeal? = nil) -> Self? {
            guard let carbs, carbs.isFinite, carbs > 0 else { return nil }
            let linkedFood = foodMeal.flatMap { meal -> CarnivalMeal? in
                guard let total = meal.carbsForReview, abs(total - carbs) < 0.000001 || abs(total.rounded() - carbs) < 0.000001 else { return nil }
                return meal
            }
            var reasons = MealReviewCalculation.reasons(snapshot: snapshot, samples: glucose, newestTreatment: newestTreatment, now: now)
                + MealReviewFullCalculation.reasons(settings: settings, snapshot: snapshot, source: source, now: now)
            let result = MealReviewFullCalculation.review(newCarbs: carbs, settings: settings, snapshot: snapshot, source: source, samples: glucose, newestTreatment: newestTreatment, now: now)
            if reasons.isEmpty, result == nil { reasons.append("Calculation could not be completed from these inputs.") }
            return Self(carbs: carbs, sourceFingerprint: MealReviewSettings.fingerprint(source), settings: settings, snapshot: snapshot,
                        glucose: glucose, recentDelta: MealReviewCalculation.recentDelta(samples: glucose, now: now), newestTreatment: newestTreatment,
                        result: result, holdReasons: reasons, sensorArrow: sensorArrow, foodMeal: linkedFood)
        }
    }

    struct Entry: Codable, Equatable {
        enum Kind: String, Codable { case comparisonDisplayed, reviewHidden }
        let schemaVersion: Int
        let id: UUID
        let kind: Kind
        let session: UUID
        let capturedAt: Date
        let evaluatedAt: Date
        let appBuild: String
        let sourceRevision: String?
        let payload: Payload

        init(kind: Kind, session: UUID, capturedAt: Date, evaluatedAt: Date, payload: Payload, appBuild: String = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown", sourceRevision: String? = nil) {
            schemaVersion = 1
            id = UUID()
            self.kind = kind
            self.session = session
            self.capturedAt = capturedAt
            self.evaluatedAt = evaluatedAt
            self.payload = payload
            self.appBuild = appBuild
            self.sourceRevision = sourceRevision
        }
    }

    static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        encoder.outputFormatting = .sortedKeys
        return encoder
    }
}

final class MealReviewAuditStore {
    static let shared = MealReviewAuditStore(directory: FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("MealReviewHistory"))
    private let directory: URL
    private let maximumBytes: Int
    private let queue = DispatchQueue(label: "com.loopfollow.meal-review-history", qos: .utility)
    private var lastEntry: MealReviewAudit.Entry?

    init(directory: URL, maximumBytes: Int = 20_000_000) {
        self.directory = directory
        self.maximumBytes = maximumBytes
    }

    func record(_ entry: MealReviewAudit.Entry, completion: ((Bool) -> Void)? = nil) {
        queue.async {
            do {
                try self.append(entry)
                completion?(true)
            } catch {
                completion?(false)
            }
        }
    }

    func flush() { queue.sync {} }

    private func append(_ entry: MealReviewAudit.Entry) throws {
        if let last = lastEntry, last.session == entry.session, last.kind == entry.kind, last.payload == entry.payload { return }
        var data = try MealReviewAudit.encoder().encode(entry)
        guard data.count <= 65536 else { throw CocoaError(.fileWriteOutOfSpace) }
        data.append(0x0A)
        let manager = FileManager.default
        try manager.createDirectory(at: directory, withIntermediateDirectories: true)
        var resourceValues = URLResourceValues()
        resourceValues.isExcludedFromBackup = true
        var folder = directory
        try? folder.setResourceValues(resourceValues)
        let files = try manager.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey, .isRegularFileKey])
        let cutoff = entry.capturedAt.addingTimeInterval(-14 * 24 * 60 * 60)
        var bytes = 0
        for file in files where file.lastPathComponent.hasPrefix("reviews-") && file.pathExtension == "jsonl" {
            let values = try file.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey, .isRegularFileKey])
            guard values.isRegularFile == true else { continue }
            if let modified = values.contentModificationDate, modified < cutoff {
                try manager.removeItem(at: file)
            } else { bytes += values.fileSize ?? 0 }
        }
        guard bytes + data.count <= maximumBytes else { throw CocoaError(.fileWriteOutOfSpace) }
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        let file = directory.appendingPathComponent("reviews-\(formatter.string(from: entry.capturedAt)).jsonl")
        if !manager.fileExists(atPath: file.path) {
            #if os(iOS)
                let attributes: [FileAttributeKey: Any] = [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication]
            #else
                let attributes: [FileAttributeKey: Any] = [:]
            #endif
            guard manager.createFile(atPath: file.path, contents: nil, attributes: attributes) else { throw CocoaError(.fileWriteUnknown) }
        }
        let handle = try FileHandle(forWritingTo: file)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: data)
        try handle.synchronize()
        lastEntry = entry
    }
}
