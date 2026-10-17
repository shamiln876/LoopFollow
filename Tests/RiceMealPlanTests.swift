import Foundation
@testable import LoopFollow
import Testing
struct RiceMealPlanTests {
    @Test func previewInvariants() {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        func plan(_ carbs: Double, _ full: Double = 5.8, _ percent: Double = 75) -> RiceMealPlan? {
            RiceMealPlan(carbs: carbs, fullRecommendation: full, upfrontPercent: percent, confirmedAt: date)
        }
        let rice = plan(80)!
        #expect(rice.immediateCarbs == 60 && rice.delayedCarbs == 20)
        #expect(rice.delayedDate.timeIntervalSince(date) == 1800)
        #expect(rice.fullRecommendation == 5.8 && rice.upfrontInsulin == 4.35)
        #expect(plan(80, 5.8, 60)!.upfrontInsulin == 3.45)
        #expect(plan(80, 5.8, 0)!.upfrontInsulin == 0)
        #expect(plan(80, 5.8, 100)!.upfrontInsulin == 5.8)
        for total in 4...1000 {
            let p = plan(Double(total))!
            #expect(p.immediateCarbs + p.delayedCarbs == total)
            #expect(p.delayedCarbs > 0 && p.delayedInsulin == 0)
            #expect(abs(Double(p.delayedCarbs) - Double(total) * 0.25) <= 0.5)
        }
        for invalid in [Double.nan, .infinity, -.infinity, -1, 0, 3, 4.5, 1001] { #expect(plan(invalid) == nil) }
        for invalid in [Double.nan, .infinity, -.infinity, -1, 101] {
            #expect(plan(80, invalid) == nil)
            #expect(plan(80, 5.8, invalid) == nil)
        }
        #expect(RiceMealPlan.sendingBlocker.contains("Nothing has been sent or scheduled"))

    }
}
