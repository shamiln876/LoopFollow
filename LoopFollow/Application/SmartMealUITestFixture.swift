// LoopFollow
// SmartMealUITestFixture.swift

#if DEBUG && targetEnvironment(simulator)
    import HealthKit
    import SwiftUI

    /// Compiled only for debug simulators. The fixture has no treatment credentials.
    /// It exercises the real Home card, Advisor and Meal views through UI events.
    struct SmartMealUITestFixture: View {
        static var enabled: Bool { ProcessInfo.processInfo.arguments.contains("--smart-meal-ui-test") }
        private static var configured = false
        @State private var mealPresented = false

        @MainActor static func configure() {
            guard !configured else { return }
            configured = true
            let now = Date()
            let source = "https://example.invalid/smart-meal-ui-test"
            Storage.shared.url.value = source
            Storage.shared.bundleId.value = "test.trio"
            Storage.shared.deviceToken.value = ""
            Storage.shared.sharedSecret.value = ""
            Storage.shared.lfApnsKey.value = ""
            Storage.shared.remoteApnsKey.value = ""
            Storage.shared.maxCarbs.value = HKQuantity(unit: .gram(), doubleValue: 150)
            Storage.shared.maxBolus.value = HKQuantity(unit: .internationalUnit(), doubleValue: 9)
            Storage.shared.mealWithBolus.value = true
            Storage.shared.mealWithFatProtein.value = false
            var s = MealReviewSnapshot(date: now, carbRatio: 10, ratioSource: "Trio reported", iob: 1, iobDate: now, cob: 20)
            s.effectiveISF = 40; s.isfSource = "Trio structured effective ISF"
            s.targetMgdl = 100; s.minPredMgdl = 100; s.minGuardMgdl = 100
            s.activity = 0.01; s.calculationIOB = 1; s.trioVersion = "1.0.2"
            s.reportedBolusIncrement = 0.05; s.pumpDate = now; s.uploadUnitSource = "Trio mg/dL fields"
            let config = SmartMealConfiguration(percentage: 80, maxIOB: 15, maxCOB: 120, maxBolus: 9,
                                                maxCarbs: 150, maxFat: 100, maxProtein: 100, bolusIncrement: 0.05)
            s.smartMeal = .init(protocolVersion: 1, generatedAt: now.timeIntervalSince1970,
                                calculationAt: now.timeIntervalSince1970, bundleIdentifier: "test.trio", enabled: true,
                                configuration: config, receipts: [])
            Observable.shared.mealReview.value = s
            Observable.shared.mealReviewGlucose.value = [.init(date: now.addingTimeInterval(-900), mgdl: 175), .init(date: now, mgdl: 180)]
            Observable.shared.mealReviewNewestTreatment.value = nil
            Storage.shared.mealReviewSettings.value = SmartMealDelivery.liveSettings(snapshot: s, source: source, bundleID: "test.trio", now: now)
            if ProcessInfo.processInfo.arguments.contains("--smart-meal-old-trio") {
                s.smartMeal = nil
                Observable.shared.mealReview.value = s
                Storage.shared.mealReviewSettings.value = .init(percentage: 80, maxIOB: 15, maxCOB: 120, maxBolus: 9,
                                                                sourceFingerprint: MealReviewSettings.fingerprint(source), trioVersion: "1.0.2", checkedAt: now)
            }
        }

        var body: some View {
            VStack(spacing: 24) {
                Text("Synthetic meal workflow test").font(.caption)
                MealDashboardHomeCard()
                Button("Open Meal") { mealPresented = true }.accessibilityIdentifier("fixture-open-meal")
            }
            .padding()
            .sheet(isPresented: $mealPresented) { MealView() }
        }
    }
#endif
