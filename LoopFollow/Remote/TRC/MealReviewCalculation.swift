// LoopFollow
// MealReviewCalculation.swift

import Foundation

/// Mirrors the component arithmetic in the user's Trio BolusCalculationManager.
/// This is the balance BEFORE max COB, percentage, max bolus, max IOB and rounding.
/// It is not a deliverable dose and deliberately has no remote-command dependency.
enum MealReviewCalculation {
    struct GlucoseSample: Codable, Equatable {
        let date: Date
        let mgdl: Double
    }

    struct Balance {
        let newCarbUnits: Double
        let existingCarbUnits: Double
        let correctionUnits: Double
        let trendUnits: Double
        let iobCreditUnits: Double
        var total: Double { newCarbUnits + existingCarbUnits + correctionUnits + trendUnits + iobCreditUnits }
    }

    static func latestGlucose(samples: [GlucoseSample], now: Date) -> GlucoseSample? {
        samples.filter { $0.date <= now && $0.mgdl.isFinite && $0.mgdl > 0 }.max { $0.date < $1.date }
    }

    /// Net insulin activity relative to scheduled basal, using the uploaded
    /// activity and current effective ISF. This is a model, not observed change.
    static func insulinEffect(activity: Double?, isf: Double?) -> Double? {
        guard let activity, let isf, activity.isFinite, isf.isFinite, isf > 0 else { return nil }
        let effect = -activity * isf * 5
        return effect.isFinite ? effect : nil
    }

    /// Trio uses newest minus oldest CGM in the preceding 20 minutes.
    /// Require at least two valid readings; never turn missing trend data into zero.
    static func recentDelta(samples: [GlucoseSample], now: Date) -> Double? {
        let valid = samples.filter { $0.date <= now && $0.date > now.addingTimeInterval(-20 * 60) && $0.mgdl.isFinite && $0.mgdl > 0 }
            .sorted { $0.date < $1.date }
        guard let first = valid.first, let last = valid.last, last.date > first.date else { return nil }
        return last.mgdl - first.mgdl
    }

    static func balance(newCarbs: Double, cob: Double, carbRatio: Double, glucose: Double, target: Double, isf: Double, iob: Double, delta: Double) -> Balance? {
        guard [newCarbs, cob, carbRatio, glucose, target, isf, iob, delta].allSatisfy(\.isFinite),
              newCarbs >= 0, cob >= 0, carbRatio > 0, glucose > 0, target > 0, isf > 0 else { return nil }
        // Trio stores existing COB as Int16 for its bolus calculator.
        let result = Balance(newCarbUnits: newCarbs / carbRatio, existingCarbUnits: cob.rounded(.towardZero) / carbRatio,
                             correctionUnits: (glucose - target) / isf, trendUnits: delta / isf, iobCreditUnits: -iob)
        return result.total.isFinite ? result : nil
    }

    static func reasons(snapshot: MealReviewSnapshot?, samples: [GlucoseSample], newestTreatment: Date?, now: Date, includeSafetyHolds: Bool = true, allowReviewedLowForecast: Bool = false) -> [String] {
        guard let snapshot else { return ["Waiting for a successful Trio calculation."] }
        var reasons: [String] = []
        if !MealReviewSnapshot.fresh(snapshot.date, now: now) { reasons.append("Trio calculation is missing or stale.") }
        if !MealReviewSnapshot.fresh(snapshot.iobDate, now: now) { reasons.append("IOB is missing or stale.") }
        if snapshot.carbRatio == nil { reasons.append("Carb ratio is unavailable.") }
        if snapshot.ratioSource == "Scheduled profile fallback" { reasons.append("Trio's active carb ratio is missing. A scheduled ratio may not include an override.") }
        if snapshot.cob == nil { reasons.append("COB is unavailable; missing COB is not zero.") }
        if snapshot.iob == nil { reasons.append("IOB is unavailable; missing IOB is not zero.") }
        if snapshot.calculationIOB == nil { reasons.append("IOB used by Trio's calculation is unavailable.") }
        if let current = snapshot.iob, let calculated = snapshot.calculationIOB, abs(current - calculated) > 0.01 {
            reasons.append("Current IOB differs from the IOB used by Trio. Waiting for a matching calculation.")
        }
        if snapshot.effectiveISF == nil { reasons.append("Trio's effective ISF is unavailable.") }
        if snapshot.targetMgdl == nil { reasons.append("Trio target or its source units are unavailable.") }
        if snapshot.trioVersion != "1.0.2" { reasons.append("This Trio version has not been checked against the meal calculation.") }
        if let cycle = snapshot.date, let insulin = snapshot.iobDate, abs(cycle.timeIntervalSince(insulin)) > 90 {
            reasons.append("IOB and Trio calculation timestamps do not match closely enough.")
        }
        let latest = latestGlucose(samples: samples, now: now)
        if !MealReviewSnapshot.fresh(latest?.date, now: now) { reasons.append("Glucose is missing or stale.") }
        if samples.contains(where: { $0.date > now.addingTimeInterval(60) }) { reasons.append("Glucose has a future timestamp. Check the device clock.") }
        if includeSafetyHolds, let latest, latest.mgdl < 70 { reasons.append("Low glucose: follow the established hypoglycemia treatment plan before meal review.") }
        if snapshot.minPredMgdl == nil || snapshot.minGuardMgdl == nil { reasons.append("Trio's selected prediction or guard value is unavailable.") }
        // Receiver-supported caregiver review can waive a mild *predicted* low; never
        // waive an actual low or a minimum below 54 mg/dL (3.0 mmol/L).
        let forecastReviewSupported = allowReviewedLowForecast && snapshot.smartMeal?.allowsLowPredictionReview == true
        if includeSafetyHolds, let predicted = snapshot.minPredMgdl, predicted < 70, !forecastReviewSupported || predicted < 54 {
            reasons.append(predicted < 54 ? "Severe low forecast (below 3.0 mmol/L): dose prefill held." : "Low forecast requires an updated Trio receiver with caregiver acknowledgment.")
        }
        if includeSafetyHolds, let guardBG = snapshot.minGuardMgdl, guardBG < 70, !forecastReviewSupported {
            reasons.append("Low guard forecast requires an updated Trio receiver with caregiver acknowledgment.")
        }
        if recentDelta(samples: samples, now: now) == nil { reasons.append("At least two recent glucose readings are required for the trend adjustment.") }
        if let treatment = newestTreatment, let cycle = snapshot.date, let insulin = snapshot.iobDate,
           treatment > min(cycle, insulin).addingTimeInterval(5)
        {
            reasons.append("New insulin or carbs were logged after this snapshot. Waiting for Trio to include them.")
        }
        return reasons
    }

    static func review(newCarbs: Double, snapshot: MealReviewSnapshot?, samples: [GlucoseSample], newestTreatment: Date?, now: Date) -> Balance? {
        guard reasons(snapshot: snapshot, samples: samples, newestTreatment: newestTreatment, now: now).isEmpty,
              let snapshot, let ratio = snapshot.carbRatio, let cob = snapshot.cob, let iob = snapshot.iob,
              let isf = snapshot.effectiveISF, let target = snapshot.targetMgdl,
              let bg = latestGlucose(samples: samples, now: now)?.mgdl,
              let delta = recentDelta(samples: samples, now: now) else { return nil }
        return balance(newCarbs: newCarbs, cob: cob, carbRatio: ratio, glucose: bg, target: target, isf: isf, iob: iob, delta: delta)
    }
}
