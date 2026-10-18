// LoopFollow
// MealReviewFullCalculation.swift

import Foundation

/// Standard Trio calculation only: no reduced or super bolus. No delivery API.
enum MealReviewFullCalculation {
    struct Result: Codable, Equatable {
        let cappedCarbs: Double
        let carbUnits: Double
        let correctionUnits: Double
        let trendUnits: Double
        let iobCreditUnits: Double
        let balance: Double
        let afterPercentage: Double
        let afterBolusLimit: Double
        let afterIOBLimit: Double
        let rounded: Double
    }

    static func calculate(newCarbs: Double, cob: Double, ratio: Double, glucose: Double, target: Double, isf: Double, iob: Double, delta: Double, settings: MealReviewSettings) -> Result? {
        guard settings.numbersValid,
              [newCarbs, cob, ratio, glucose, target, isf, iob, delta].allSatisfy(\.isFinite),
              newCarbs >= 0, (0 ... 32767).contains(cob), ratio > 0, glucose > 0, target > 0, isf > 0 else { return nil }
        // Decimal arithmetic follows Trio's calculator. Omnipod rounds down by
        // choosing the last supported n/20 volume <= the requested Double.
        func d(_ n: Double) -> Decimal? { Decimal(string: String(n), locale: Locale(identifier: "en_US_POSIX")) }
        func value(_ n: Decimal) -> Double { NSDecimalNumber(decimal: n).doubleValue }
        guard let meal = d(newCarbs), let oldCarbs = d(cob.rounded(.towardZero)),
              let cr = d(ratio), let bg = d(glucose), let goal = d(target), let sensitivity = d(isf),
              let active = d(iob), let change = d(delta), let percentage = d(settings.percentage),
              let maxCOB = d(settings.maxCOB), let maxBolus = d(settings.maxBolus), let maxIOB = d(settings.maxIOB) else { return nil }
        let wholeCarbs = min(meal + oldCarbs, maxCOB)
        let carbUnits = wholeCarbs / cr
        let correction = (bg - goal) / sensitivity
        let trend = change / sensitivity
        let credit = -active
        let balance = carbUnits + correction + trend + credit
        let factored = balance > 0 ? balance * percentage / 100 : balance
        let bolusLimited = min(max(factored, 0), maxBolus)
        let iobLimited = max(0, min(bolusLimited, maxIOB - active))
        let limited = value(iobLimited)
        let rounded = (1 ... 600).map { Double($0) / 20 }.last { $0 <= limited } ?? 0
        let fields = [wholeCarbs, carbUnits, correction, trend, credit, balance, factored, bolusLimited, iobLimited].map(value)
        guard fields.allSatisfy(\.isFinite) else { return nil }
        return Result(cappedCarbs: fields[0], carbUnits: fields[1], correctionUnits: fields[2], trendUnits: fields[3], iobCreditUnits: fields[4], balance: fields[5], afterPercentage: fields[6], afterBolusLimit: fields[7], afterIOBLimit: fields[8], rounded: rounded)
    }

    static func reasons(settings: MealReviewSettings?, snapshot: MealReviewSnapshot?, source: String, now: Date) -> [String] {
        guard let settings else { return ["Copy the current percentage and limits from Trio to complete the comparison."] }
        var reasons: [String] = []
        if !settings.matches(source: source, version: snapshot?.trioVersion, now: now) {
            reasons.append("Recheck the saved values for this Nightscout connection and Trio version.")
        }
        if snapshot?.reportedBolusIncrement != 0.05 { reasons.append("Waiting for Trio's reported 0.05 U pump increment. Other pump rounding has not been verified.") }
        if !MealReviewSnapshot.fresh(snapshot?.pumpDate, now: now) { reasons.append("Pump metadata is missing or stale.") }
        return reasons
    }

    static func review(newCarbs: Double, settings: MealReviewSettings?, snapshot: MealReviewSnapshot?, source: String, samples: [MealReviewCalculation.GlucoseSample], newestTreatment: Date?, now: Date) -> Result? {
        evaluate(newCarbs: newCarbs, settings: settings, snapshot: snapshot, source: source, samples: samples, newestTreatment: newestTreatment, now: now, includeSafetyHolds: true)
    }

    /// Read-only arithmetic can remain visible during a low-forecast hold.
    /// This result never authorizes prefill; review() and draft checks stay strict.
    static func comparison(newCarbs: Double, settings: MealReviewSettings?, snapshot: MealReviewSnapshot?, source: String, samples: [MealReviewCalculation.GlucoseSample], newestTreatment: Date?, now: Date) -> Result? {
        evaluate(newCarbs: newCarbs, settings: settings, snapshot: snapshot, source: source, samples: samples, newestTreatment: newestTreatment, now: now, includeSafetyHolds: false)
    }

    private static func evaluate(newCarbs: Double, settings: MealReviewSettings?, snapshot: MealReviewSnapshot?, source: String, samples: [MealReviewCalculation.GlucoseSample], newestTreatment: Date?, now: Date, includeSafetyHolds: Bool) -> Result? {
        guard reasons(settings: settings, snapshot: snapshot, source: source, now: now).isEmpty,
              MealReviewCalculation.reasons(snapshot: snapshot, samples: samples, newestTreatment: newestTreatment, now: now, includeSafetyHolds: includeSafetyHolds).isEmpty,
              let settings, let s = snapshot, let cob = s.cob, let ratio = s.carbRatio,
              let target = s.targetMgdl, let isf = s.effectiveISF, let iob = s.iob,
              let bg = MealReviewCalculation.latestGlucose(samples: samples, now: now)?.mgdl,
              let delta = MealReviewCalculation.recentDelta(samples: samples, now: now) else { return nil }
        return calculate(newCarbs: newCarbs, cob: cob, ratio: ratio, glucose: bg, target: target, isf: isf, iob: iob, delta: delta, settings: settings)
    }
}
