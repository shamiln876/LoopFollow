import Foundation

/// Preview only. This type has no transport, credentials, timers, or delivery side effects.
struct RiceMealPlan: Equatable {
    let immediateCarbs: Int
    let delayedCarbs: Int
    let delayedDate: Date
    let fullRecommendation: Double
    let upfrontPercent: Double
    let upfrontInsulin: Double
    let delayedInsulin: Double = 0

    static let sendingBlocker = "Automatic Rice sending is unavailable: two-entry acceptance and receiver replay protection have not been verified. Nothing has been sent or scheduled."

    init?(carbs: Double, fullRecommendation: Double, upfrontPercent: Double, confirmedAt: Date) {
        // The existing remote protocol accepts whole grams. Never truncate two fractions independently.
        guard carbs.isFinite, carbs >= 4, carbs <= 1000, carbs.rounded() == carbs,
              fullRecommendation.isFinite, fullRecommendation >= 0, fullRecommendation <= 100,
              upfrontPercent.isFinite, (0 ... 100).contains(upfrontPercent),
              confirmedAt.timeIntervalSince1970.isFinite else { return nil }
        let total = Int(carbs)
        delayedCarbs = Int((carbs * 0.25).rounded())
        immediateCarbs = total - delayedCarbs
        delayedDate = confirmedAt.addingTimeInterval(30 * 60)
        self.fullRecommendation = fullRecommendation
        self.upfrontPercent = upfrontPercent
        // DASH step: round down once, after applying the independently selected percentage.
        let raw = Decimal(string: String(fullRecommendation))! * Decimal(string: String(upfrontPercent))! / 100
        var steps = raw * 20
        var rounded = Decimal()
        NSDecimalRound(&rounded, &steps, 0, .down)
        upfrontInsulin = NSDecimalNumber(decimal: rounded / 20).doubleValue
    }
}
