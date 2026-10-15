// LoopFollow
// MealReviewSettings.swift

import CryptoKit
import Foundation

/// User-copied settings for read-only comparison, never remote delivery authority.
struct MealReviewSettings: Codable, Equatable {
    let percentage: Double
    let maxIOB: Double
    let maxCOB: Double
    let maxBolus: Double
    let sourceFingerprint: String
    let trioVersion: String
    let checkedAt: Date

    static func fingerprint(_ source: String) -> String {
        SHA256.hash(data: Data(source.trimmingCharacters(in: .whitespacesAndNewlines).utf8)).map { String(format: "%02x", $0) }.joined()
    }

    var numbersValid: Bool {
        [percentage, maxIOB, maxCOB, maxBolus].allSatisfy(\.isFinite)
            && (5 ... 150).contains(percentage) && maxIOB >= 0
            && (0 ... 32767).contains(maxCOB) && (0 ... 30).contains(maxBolus)
    }

    func matches(source: String, version: String?, now: Date) -> Bool {
        numbersValid && !source.isEmpty && sourceFingerprint == Self.fingerprint(source)
            && trioVersion == "1.0.2" && version == trioVersion && checkedAt <= now.addingTimeInterval(60)
    }
}
