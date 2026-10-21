// LoopFollow
// SmartMealUITestFixture.swift

#if DEBUG && targetEnvironment(simulator)
    import ActivityKit
    import HealthKit
    import SwiftUI

    /// Compiled only for debug simulators. The fixture has no treatment credentials.
    /// It exercises the real Home card, Advisor and Meal views through UI events.
    struct SmartMealUITestFixture: View {
        static var enabled: Bool { ProcessInfo.processInfo.arguments.contains("--smart-meal-ui-test") }
        private static var configured = false
        @State private var liveActivityResult = "Not started"
        @State private var route: FixtureRoute?
        @State private var percentageDraft: SmartMealDraft?

        private enum FixtureRoute: Identifiable {
            case meal, percentageAdvisor, percentageMeal(SmartMealDraft)
            var id: String {
                switch self {
                case .meal: return "meal"
                case .percentageAdvisor: return "advisor"
                case let .percentageMeal(draft): return "meal-" + draft.transactionID.uuidString
                }
            }
        }

        @MainActor static func configure() {
            guard !configured else { return }
            configured = true
            UserDefaults.standard.set("onDevice", forKey: "plateScannerProvider")
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
            if ProcessInfo.processInfo.arguments.contains("--post-meal-smb-ui-test") {
                s.smartMeal?.postMealSMB = .init(enabled: !ProcessInfo.processInfo.arguments.contains("--post-meal-smb-disabled"),
                                                 revision: "initial", durationMinutes: 30,
                                                 blockedUntil: ProcessInfo.processInfo.arguments.contains("--post-meal-smb-disabled") ? nil : now.addingTimeInterval(1800).timeIntervalSince1970)
            }
            if ProcessInfo.processInfo.arguments.contains("--smart-meal-low-forecast") {
                s.minPredMgdl = 65; s.minGuardMgdl = 29; s.eventualMgdl = 107
                s.smartMeal?.allowsLowPredictionReview = true
            }
            if ProcessInfo.processInfo.arguments.contains("--smart-meal-very-low-forecast") {
                s.minPredMgdl = 53; s.minGuardMgdl = 29; s.eventualMgdl = 107
                s.smartMeal?.allowsLowPredictionReview = true
            }
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

        @MainActor private func checkForegroundLiveActivity() {
            Storage.shared.laEnabled.value = true
            Storage.shared.lfKeyId.value = ""
            Storage.shared.lfApnsKey.value = ""
            Storage.shared.laLastPushToStartAt.value = Date().timeIntervalSince1970
            Storage.shared.laPushToStartBackoff.value = 3600
            let readingDate = Date().addingTimeInterval(-600)
            let snapshot = GlucoseSnapshot(glucose: 123, delta: 0, trend: .unknown,
                                           updatedAt: readingDate, iob: nil, cob: nil, projected: nil,
                                           unit: .mgdl, isNotLooping: false)
            GlucoseSnapshotStore.shared.save(snapshot)
            let manager = LiveActivityManager.shared
            manager.startIfNeeded()
            guard let first = manager.current else {
                liveActivityResult = "Failed to create activity"
                return
            }
            manager.startIfNeeded()
            let preserved = first.content.state.snapshot.updatedAt == readingDate
            let reused = manager.current?.id == first.id
            liveActivityResult = preserved && reused ? "Created; timestamp preserved; reused" : "State mismatch"
        }

        var body: some View {
            VStack(spacing: 24) {
                Text("Synthetic meal workflow test").font(.caption)
                if ProcessInfo.processInfo.arguments.contains("--live-activity-ui-test") {
                    Button("Start Live Activity") { checkForegroundLiveActivity() }
                        .accessibilityIdentifier("fixture-start-live-activity")
                    Text(liveActivityResult).accessibilityIdentifier("fixture-live-activity-result")
                }
                MealDashboardHomeCard()
                if ProcessInfo.processInfo.arguments.contains("--smart-meal-percentage-test") {
                    Button("Review synthetic 80 g meal") { route = .percentageAdvisor }
                        .accessibilityIdentifier("fixture-percentage-advisor")
                }
                Button("Open Meal") { route = .meal }.accessibilityIdentifier("fixture-open-meal")
            }
            .padding()
            .sheet(item: $route, onDismiss: {
                if let draft = percentageDraft {
                    percentageDraft = nil
                    route = .percentageMeal(draft)
                }
            }) { selected in
                switch selected {
                case .meal: MealView()
                case .percentageAdvisor:
                    MealReviewView(initialCarbs: 80) { percentageDraft = $0 }
                case let .percentageMeal(draft): MealView(initialAdvisorDraft: draft)
                }
            }
        }
    }
#endif
