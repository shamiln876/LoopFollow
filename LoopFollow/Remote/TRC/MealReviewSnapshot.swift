// LoopFollow
// MealReviewSnapshot.swift

import CoreFoundation
import Foundation

/// A single OpenAPS record, never a mixture of cached values from different cycles.
struct MealReviewSnapshot {
    let date: Date?
    let carbRatio: Double?
    let ratioSource: String
    let iob: Double?
    let iobDate: Date?
    let cob: Double?

    static func fresh(_ date: Date?, now: Date) -> Bool {
        guard let date else { return false }
        let age = now.timeIntervalSince(date)
        return age >= -60 && age <= 10 * 60
    }

    static func number(_ value: Any?) -> Double? {
        guard let value = value as? NSNumber,
              CFGetTypeID(value) != CFBooleanGetTypeID(), value.doubleValue.isFinite else { return nil }
        return value.doubleValue
    }

    static func parse(_ record: [String: AnyObject], profileRatio: Double?) -> MealReviewSnapshot? {
        guard record["failureReason"] == nil,
              let calculation = record["suggested"] as? [String: AnyObject]
              ?? record["enacted"] as? [String: AnyObject] else { return nil }
        func date(_ raw: Any?) -> Date? {
            guard let raw = raw as? String else { return nil }
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            return formatter.date(from: raw) ?? ISO8601DateFormatter().date(from: raw)
        }
        func reasonNumber(_ name: String) -> Double? {
            guard let reason = calculation["reason"] as? String,
                  let range = reason.range(of: "\\b" + name + ":\\s*([0-9]+(?:\\.[0-9]+)?)", options: .regularExpression) else { return nil }
            return Double(reason[range].split(separator: ":").last?.trimmingCharacters(in: .whitespaces) ?? "")
        }
        let reported = number(calculation["CR"]).flatMap { $0 > 0 ? $0 : nil } ?? reasonNumber("CR").flatMap { $0 > 0 ? $0 : nil }
        let ratio = reported ?? profileRatio.flatMap { $0.isFinite && $0 > 0 ? $0 : nil }
        let insulin = record["iob"] as? [String: AnyObject]
        let cycleDate = date(calculation["timestamp"]) ?? date(calculation["deliverAt"])
        let cob = number(calculation["COB"]) ?? reasonNumber("COB")
        return MealReviewSnapshot(date: cycleDate, carbRatio: ratio,
                                  ratioSource: reported == nil ? "Scheduled profile fallback" : "Trio reported",
                                  iob: number(insulin?["iob"]), iobDate: date(insulin?["time"]) ?? date(insulin?["timestamp"]),
                                  cob: cob.flatMap { $0 >= 0 ? $0 : nil })
    }

    /// Educational carb/ratio arithmetic only. Never a deliverable bolus recommendation.
    func carbEquivalent(carbs: Double, glucose: Double?, glucoseDate: Date?, now: Date) -> Double? {
        guard Self.fresh(date, now: now), Self.fresh(iobDate, now: now),
              Self.fresh(glucoseDate, now: now), let glucose, glucose.isFinite, glucose >= 70,
              iob != nil, cob != nil, let carbRatio, carbRatio.isFinite, carbRatio > 0,
              carbs.isFinite, carbs > 0 else { return nil }
        let result = carbs / carbRatio
        return result.isFinite ? result : nil
    }
}
