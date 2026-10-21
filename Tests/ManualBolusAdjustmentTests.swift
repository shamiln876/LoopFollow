// LoopFollow
// ManualBolusAdjustmentTests.swift

import Foundation
@testable import LoopFollow
import Testing

struct ManualBolusAdjustmentTests {
    private func adjusted(_ current: Double, _ direction: ManualBolusAdjustment.Direction, increment: Double = 0.05, maximum: Double = 8) -> Double? {
        ManualBolusAdjustment.adjusted(current: current, direction: direction, increment: increment, maximum: maximum)
    }

    @Test func changesExactlyOneTenthIncludingHalfTenthStartingValues() {
        #expect(adjusted(0, .increase) == 0.1)
        #expect(adjusted(0.05, .increase) == 0.15)
        #expect(adjusted(1.05, .increase) == 1.15)
        #expect(adjusted(1.15, .decrease) == 1.05)
        #expect(adjusted(0.1, .decrease) == 0)
        var amount = 0.05
        for _ in 0 ..< 70 {
            amount = adjusted(amount, .increase)!
        }
        #expect(amount == 7.05)
        for _ in 0 ..< 70 {
            amount = adjusted(amount, .decrease)!
        }
        #expect(amount == 0.05)
    }

    @Test func neverCrossesZeroOrMaximumOrSilentlyClamps() {
        #expect(adjusted(0, .decrease) == nil)
        #expect(adjusted(0.05, .decrease) == nil)
        #expect(adjusted(8, .increase) == nil)
        #expect(adjusted(7.95, .increase) == nil)
        #expect(adjusted(7.9, .increase) == 8)
        #expect(adjusted(1.95, .increase, maximum: 2.04) == nil)
        #expect(adjusted(1.95, .increase, maximum: 2.05) == 2.05)
        #expect(adjusted(8.1, .decrease) == nil)
    }

    @Test func requiresCompatiblePumpStepAndSelectedAmount() {
        #expect(adjusted(1.02, .increase, increment: 0.01) == 1.12)
        #expect(adjusted(1, .increase, increment: 0.1) == 1.1)
        #expect(adjusted(1, .increase, increment: 0.2) == nil)
        #expect(adjusted(1.025, .increase) == nil)
        #expect(adjusted(1, .increase, increment: 0) == nil)
        #expect(adjusted(1, .increase, increment: -0.05) == nil)
    }

    @Test func rejectsMalformedNumbers() {
        for number in [Double.nan, .infinity, -.infinity, -1] {
            #expect(adjusted(number, .increase) == nil)
            #expect(adjusted(1, .increase, increment: number) == nil)
            #expect(adjusted(1, .increase, maximum: number) == nil)
        }
        #expect(adjusted(1, .increase, increment: Double.leastNonzeroMagnitude) == nil)
    }
}
