// LoopFollow
// MealReviewSnapshot.swift

import CoreFoundation
import Foundation

/// A single OpenAPS record, never a mixture of cached values from different cycles.
struct MealReviewSnapshot: Codable, Equatable {
    let date: Date?
    let carbRatio: Double?
    let ratioSource: String
    let iob: Double?
    let iobDate: Date?
    let cob: Double?
    var effectiveISF: Double? = nil // Canonical mg/dL/U; never silently use scheduled ISF.
    var isfSource = "Unavailable"
    var targetMgdl: Double? = nil
    var activity: Double? = nil // U/min, already computed using Trio's insulin curve.
    var nativeRecommendation: Double? = nil // Trio calculates this with ZERO new carbs.
    var minPredMgdl: Double? = nil
    var minGuardMgdl: Double? = nil
    var eventualMgdl: Double? = nil
    var predictions: [String: [Double]] = [:]
    var trioVersion: String? = nil
    var uploadUnitSource = "Unavailable"
    var calculationIOB: Double? = nil
    var reportedBolusIncrement: Double? = nil
    var pumpDate: Date? = nil
    var smartMeal: SmartMealReceiverStatus? = nil

    enum TrendNotice {
        case downwardArrow
        case negativeChange
        case unavailable
    }

    /// Describe glucose trajectory separately from carb-ratio arithmetic.
    /// A Flat arrow can coexist with a small decline.
    static func trendNotice(delta: Double?, trend: String?) -> TrendNotice? {
        if ["SingleDown", "DoubleDown", "FortyFiveDown"].contains(trend ?? "") { return .downwardArrow }
        if let delta, delta < 0 { return .negativeChange }
        if delta?.isFinite == true || ["Flat", "FortyFiveUp", "SingleUp", "DoubleUp"].contains(trend ?? "") { return nil }
        return .unavailable
    }

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

    static func parse(_ record: [String: AnyObject], profileRatio: Double?, profileUnits: String? = nil, pumpRecord: [String: AnyObject]? = nil) -> MealReviewSnapshot? {
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
        var snapshot = MealReviewSnapshot(date: cycleDate, carbRatio: ratio,
                                          ratioSource: reported == nil ? "Scheduled profile fallback" : "Trio reported",
                                          iob: number(insulin?["iob"]), iobDate: date(insulin?["time"]) ?? date(insulin?["timestamp"]),
                                          cob: cob.flatMap { $0 >= 0 ? $0 : nil })
        let sourceVersion = record["version"] as? String
        let factor: Double? = {
            guard sourceVersion == "1.0.2" else { return nil }
            // NightscoutManager stores lastSuggestedDetermination BEFORE its
            // display-unit conversion and timestamp injection. On an enacted
            // upload the cached suggestion therefore remains in mg/dL. Require
            // its original deliverAt, rather than guessing units from magnitude.
            if record["suggested"] as? [String: AnyObject] != nil, calculation["timestamp"] == nil, date(calculation["deliverAt"]) != nil { return 1 }
            switch profileUnits?.lowercased() {
            case "mg/dl": return 1
            case "mmol", "mmol/l": return 18.01559
            default: return nil
            }
        }()
        func glucoseField(_ name: String, positiveOnly: Bool = true) -> Double? {
            guard let factor, let raw = number(calculation[name]), !positiveOnly || raw > 0 else { return nil }
            return raw * factor
        }
        func reasonGlucose(_ name: String, positiveOnly: Bool = true) -> Double? {
            guard let factor, let reason = calculation["reason"] as? String,
                  let regex = try? NSRegularExpression(pattern: "\\b" + name + ":?\\s+(-?[0-9]+(?:\\.[0-9]+)?(?:→-?[0-9]+(?:\\.[0-9]+)?)*)"),
                  let match = regex.firstMatch(in: reason, range: NSRange(location: 0, length: reason.utf16.count)),
                  let raw = Double((reason as NSString).substring(with: match.range(at: 1)).split(separator: "→").last ?? ""), !positiveOnly || raw > 0 else { return nil }
            if name == "ISF", factor != 1, !(reason as NSString).substring(with: match.range(at: 1)).contains("→") { return nil }
            return raw * factor
        }
        // Trio only converts target, min-prediction fields and reason to display
        // units during upload; structured ISF and prediction arrays stay in mg/dL.
        snapshot.effectiveISF = number(calculation["ISF"]).flatMap { $0 > 0 ? $0 : nil }
        if snapshot.effectiveISF != nil { snapshot.isfSource = "Trio structured effective ISF" }
        else if let parsed = reasonGlucose("ISF") {
            snapshot.effectiveISF = parsed
            snapshot.isfSource = "Trio reason (rounded)"
        }
        snapshot.targetMgdl = glucoseField("current_target") ?? reasonGlucose("Target")
        snapshot.minPredMgdl = glucoseField("minPredBG", positiveOnly: false) ?? reasonGlucose("minPredBG", positiveOnly: false)
        snapshot.minGuardMgdl = glucoseField("minGuardBG", positiveOnly: false) ?? reasonGlucose("minGuardBG", positiveOnly: false)
        // Trio leaves this structured field in mg/dL in both upload variants.
        snapshot.eventualMgdl = sourceVersion == "1.0.2" ? number(calculation["eventualBG"]) : nil
        snapshot.reportedBolusIncrement = number(pumpRecord?["bolusIncrement"])
        snapshot.pumpDate = date(pumpRecord?["clock"])
        snapshot.activity = number(insulin?["activity"])
        snapshot.calculationIOB = number(calculation["IOB"])
        snapshot.nativeRecommendation = number(record["recommendedBolus"]).flatMap { $0 >= 0 ? $0 : nil }
        snapshot.trioVersion = record["version"] as? String
        if let status = record["smartMeal"], let data = try? JSONSerialization.data(withJSONObject: Self.exactReceiverJSON(status)) {
            snapshot.smartMeal = try? JSONDecoder().decode(SmartMealReceiverStatus.self, from: data)
        }
        if let factor { snapshot.uploadUnitSource = factor == 1 ? "Trio mg/dL fields" : "Trio mmol/L fields" }
        if let predictions = calculation["predBGs"] as? [String: Any] {
            for name in ["IOB", "COB", "UAM", "ZT"] {
                if let rawValues = predictions[name] as? [Any], !rawValues.isEmpty {
                    let values = rawValues.compactMap(Self.number)
                    guard values.count == rawValues.count, values.allSatisfy({ $0 > 0 }) else { continue }
                    snapshot.predictions[name] = Array(values.prefix(288))
                }
            }
        }
        return snapshot
    }

    /// Re-encoding binary NSNumbers can turn 0.05 into 0.050000000000000003.
    /// Keep decimal text exact for configuration IDs and echoed request digests.
    private static func exactReceiverJSON(_ value: Any) -> Any {
        if let dictionary = value as? [String: Any] { return dictionary.mapValues(exactReceiverJSON) }
        if let array = value as? [Any] { return array.map(Self.exactReceiverJSON) }
        if let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() {
            return NSDecimalNumber(string: number.stringValue, locale: Locale(identifier: "en_US_POSIX"))
        }
        return value
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

    func reviewEquivalent(carbs: Double, glucose: Double?, glucoseDate: Date?, delta _: Double?, trend _: String?, now: Date) -> Double? {
        // Trend is review context, not an input to the carb-only reference.
        // Low glucose, missing fields and stale timestamps still suppress it.
        return carbEquivalent(carbs: carbs, glucose: glucose, glucoseDate: glucoseDate, now: now)
    }
}
