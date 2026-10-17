// LoopFollow
// MealDashboardStatus.swift

import Foundation

/// Input readiness only. Uses the same checks as the comparison, without
/// treating an empty meal as a data failure or implying a validated dose.
struct MealDashboardStatus {
    let glucose: MealReviewCalculation.GlucoseSample?
    let reasons: [String]

    var inputsAvailable: Bool { reasons.isEmpty }
    var title: String { inputsAvailable ? "Live inputs available" : "Check live data" }

    init(snapshot: MealReviewSnapshot?, samples: [MealReviewCalculation.GlucoseSample], newestTreatment: Date?, settings: MealReviewSettings?, source: String, now: Date) {
        glucose = MealReviewCalculation.latestGlucose(samples: samples, now: now)
        reasons = MealReviewCalculation.reasons(snapshot: snapshot, samples: samples, newestTreatment: newestTreatment, now: now)
            + MealReviewFullCalculation.reasons(settings: settings, snapshot: snapshot, source: source, now: now)
    }
}
