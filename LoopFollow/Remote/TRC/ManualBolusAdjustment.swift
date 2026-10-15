// LoopFollow
// ManualBolusAdjustment.swift

import Foundation

/// Changes an explicitly selected manual amount only. It never calculates or sends a bolus.
enum ManualBolusAdjustment {
    enum Direction { case decrease, increase }

    static func adjusted(current: Double, direction: Direction, increment: Double, maximum: Double) -> Double? {
        guard [current, increment, maximum].allSatisfy(\.isFinite),
              current >= 0, increment > 0, maximum >= 0, current <= maximum else { return nil }
        // A 0.1 U adjustment must be compatible with the configured pump increment.
        let steps = 0.1 / increment
        let currentSteps = current / increment
        guard steps.isFinite, currentSteps.isFinite, steps >= 1,
              abs(steps - steps.rounded()) < 1e-8,
              abs(currentSteps - currentSteps.rounded()) < 1e-8,
              let base = Decimal(string: String(current), locale: Locale(identifier: "en_US_POSIX")),
              let limit = Decimal(string: String(maximum), locale: Locale(identifier: "en_US_POSIX")) else { return nil }
        let change = Decimal(1) / 10
        let target = direction == .increase ? base + change : base - change
        guard target >= 0, target <= limit else { return nil }
        let result = NSDecimalNumber(decimal: target).doubleValue
        guard result.isFinite, result >= 0, result <= maximum,
              abs(abs(result - current) - 0.1) < 1e-8 else { return nil }
        return result
    }
}
