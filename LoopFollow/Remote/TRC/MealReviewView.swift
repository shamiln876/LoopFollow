// LoopFollow
// MealReviewView.swift

import Charts
import HealthKit
import SwiftUI
import UIKit

struct MealReviewView: View {
    let initialCarbs: Double
    @Environment(\.dismiss) private var dismiss
    @State private var preset: SmartMealPreset = .fruit
    @State private var carbsNowText = "100"
    @State private var delayText = "0"
    @State private var proteinText = ""
    @State private var fatText = ""
    @State private var sendFatProtein = false
    private let onUse: (SmartMealDraft) -> Void
    private let onManualMeal: ((Double) -> Void)?
    @State private var pendingForecastDraft: SmartMealDraft?
    @State private var forecastWarningPresented = false
    @State private var forecastReviewError: String?
    @State private var customPercent = "100"
    @State private var linkedPercentages = true
    @State private var bolusOverrideText: String?
    @FocusState private var bolusFocused: Bool
    @State private var carbText: String
    @State private var refreshAnchor = Date()
    @State private var settingsPresented = false
    @State private var foodPresented = false
    @State private var platePresented = false
    @State private var foodMeal: CarnivalMeal?
    @State private var reviewSession = UUID()
    @State private var pendingAudit: DispatchWorkItem?
    @State private var auditFailed = false
    private let audit: MealReviewAuditStore
    @ObservedObject private var settings: StorageValue<MealReviewSettings?>
    @ObservedObject private var source: StorageValue<String>
    @ObservedObject private var localBolusLimit = Storage.shared.maxBolus
    @ObservedObject private var localCarbLimit = Storage.shared.maxCarbs
    @FocusState private var carbsFocused: Bool
    @ObservedObject private var snapshot = Observable.shared.mealReview
    @ObservedObject private var history = Observable.shared.mealReviewGlucose
    @ObservedObject private var newestTreatment = Observable.shared.mealReviewNewestTreatment
    @ObservedObject private var trend = Storage.shared.lastTrendCode

    init(initialCarbs: Double, initialBolus: Double? = nil, initialPlan: RiceMealPlan? = nil, settings: StorageValue<MealReviewSettings?> = Storage.shared.mealReviewSettings, source: StorageValue<String> = Storage.shared.url, audit: MealReviewAuditStore = .shared, onManualMeal: ((Double) -> Void)? = nil, onUse: @escaping (SmartMealDraft) -> Void) {
        self.onUse = onUse
        self.onManualMeal = onManualMeal
        self.initialCarbs = initialCarbs
        _bolusOverrideText = State(initialValue: initialBolus.map { String(format: "%.2f", $0) })
        self.audit = audit
        _settings = ObservedObject(wrappedValue: settings)
        _source = ObservedObject(wrappedValue: source)
        _carbText = State(initialValue: initialCarbs.isFinite && initialCarbs > 0 ? String(format: "%.1f", initialCarbs) : "")
        if let initialPlan {
            _preset = State(initialValue: initialPlan.preset ?? .custom)
            _carbsNowText = State(initialValue: String(format: "%g", initialPlan.carbsNowPercent))
            _delayText = State(initialValue: String(format: "%g", initialPlan.delayMinutes))
            _customPercent = State(initialValue: String(format: "%g", initialPlan.upfrontPercent))
            _linkedPercentages = State(initialValue: initialPlan.carbsNowPercent == initialPlan.upfrontPercent)
        }
    }

    private var carbs: Double? { Double(carbText.replacingOccurrences(of: ",", with: ".")) }

    var body: some View {
        NavigationView {
            TimelineView(.periodic(from: refreshAnchor, by: 5)) { context in
                // A retained/paused screen must not compare a new upload with
                // its old timer value. Always evaluate against wall-clock time.
                let now = Date()
                Form {
                    Section("Your meal") {
                        HStack {
                            Text("Meal carbs (g)")
                            TextField("Amount", text: $carbText)
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                                .focused($carbsFocused)
                                .accessibilityLabel("Meal carbs in grams")
                                .accessibilityIdentifier("advisor-meal-carbs")
                        }
                        presetSection
                        if carbsFocused { Button("Hide keyboard") { carbsFocused = false; bolusFocused = false } }
                        Button("Carnival food & portions") { carbsFocused = false; foodPresented = true }
                        Button { carbsFocused = false; platePresented = true } label: {
                            Label("Scan plate photo", systemImage: "camera")
                        }.accessibilityIdentifier("advisor-scan-plate")
                        if let foodMeal {
                            DisclosureGroup("Selected foods · \(foodMeal.items.count)") {
                                ForEach(foodMeal.items) { item in
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(item.food.name).font(.subheadline.weight(.semibold))
                                        Text("\(CarnivalNumber.text(item.portions)) × \(item.food.portion)").font(.caption)
                                    }
                                }
                                Text("Estimated nutrition from the Carnival guide, rounded to whole grams for meal entry. Protein and fat are included only if explicitly selected. Changing carbs manually clears this food record.")
                                    .font(.footnote).foregroundStyle(.secondary)
                            }
                            if let low = foodMeal.total(\.low), let high = foodMeal.total(\.high) {
                                Text("Food planning range: \(CarnivalNumber.text(low))–\(CarnivalNumber.text(high)) g carbs. Not guaranteed bounds.").font(.footnote)
                            }
                        }
                    }
                    fullSection(now: now)
                    Section("Live data") {
                        MealDashboardCompactOverview(status: MealDashboardStatus(snapshot: snapshot.value, samples: history.value, newestTreatment: newestTreatment.value, settings: settings.value, source: source.value, now: now), snapshot: snapshot.value, sensorArrow: trend.value, now: now, hasMeal: carbs.map { $0.isFinite && $0 > 0 } == true)
                    }
                    nutrientsSection
                    Section("Recent glucose") { MealDashboardGlucoseChart(samples: history.value, now: now) }
                    activitySection(now: now)
                    contextSection(now: now)
                    forecastSection(now: now)
                    Section("Comparison limitations") {
                        Text("The calculation uses all meal carbs, then applies your saved Trio percentage and limits, followed by the selected upfront percentage. Low forecasts can be reviewed before transfer. When a calculated dose cannot be verified, manual Meal entry remains available.")
                        DisclosureGroup("What the model includes") {
                            Text("New carbs and existing estimated COB are divided by Trio's active carb ratio. Glucose correction and recent glucose change use the reported effective ISF. Remaining net IOB is subtracted once. IOB and activity are relative to scheduled basal; negative values can represent a basal deficit. This review does not model absorption of the new meal, future SMBs, future ISF changes, or delivery that has not yet reached Nightscout. Uploaded predictions can be wrong. Use Prefill to transfer a local draft; confirmation and authentication occur on the Meal screen.")
                                .font(.footnote)
                        }
                    }
                    Section("Comparison history") {
                        Text("Displayed comparisons and their inputs are saved on this iPhone for up to 14 days, for review alongside actual Nightscout deliveries. A saved comparison does not confirm insulin was given.").font(.footnote)
                        if auditFailed { warning("Comparison history could not be saved. Keep a screenshot of this review.") }
                    }
                }
                .safeAreaInset(edge: .bottom) { transferBar(now: now) }
                .scrollDismissesKeyboard(.interactively)
                .navigationTitle("Smart Meal Advisor")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) { Button("Close") { dismiss() } }
                    ToolbarItemGroup(placement: .keyboard) {
                        Spacer()
                        Button("Hide keyboard") { carbsFocused = false; bolusFocused = false }
                    }
                }
                .onChange(of: context.date) { _, _ in scheduleAudit() }
            }
        }
        .sheet(isPresented: $settingsPresented) { MealReviewSettingsView(saved: settings, source: source) }
        .alert("Review low forecast", isPresented: $forecastWarningPresented, presenting: pendingForecastDraft) { reviewed in
            Button("Accept and continue") { acceptForecastReview(reviewed) }
            Button("Cancel", role: .cancel) { pendingForecastDraft = nil }
        } message: { reviewed in
            Text(forecastWarningMessage(reviewed))
        }
        .sheet(isPresented: $foodPresented) {
            CarnivalFoodGuideView(initialMeal: foodMeal) { meal in
                applyFoodMeal(meal)
            }
        }
        .sheet(isPresented: $platePresented) {
            switch CarnivalFoodCatalog.bundled {
            case let .success(catalog): PlateScannerView(catalog: catalog, accept: applyFoodMeal)
            case .failure: Text("The food guide could not be verified. Use manual carb entry until the guide is restored.").padding()
            }
        }
        .onAppear { MealReviewSettingsImport.consumePending(); scheduleAudit() }
        .onChange(of: carbText) { _, _ in
            if let total = foodMeal?.carbsForReview, carbs.map({ abs($0 - total.rounded()) < 0.000001 }) != true { foodMeal = nil }
            bolusOverrideText = nil
            scheduleAudit()
        }
        .onChange(of: customPercent) { _, _ in
            bolusOverrideText = nil
            synchronizeCarbSplit()
        }
        .onChange(of: bolusFocused) { _, focused in
            if focused {
                // A tap should let the caregiver replace the suggested amount immediately.
                DispatchQueue.main.async {
                    UIApplication.shared.sendAction(#selector(UITextField.selectAll(_:)), to: nil, from: nil, for: nil)
                }
            }
        }
        .onChange(of: snapshot.value) { _, _ in scheduleAudit() }
        .onChange(of: history.value) { _, _ in scheduleAudit() }
        .onChange(of: settings.value) { _, _ in scheduleAudit() }
        .onChange(of: source.value) { _, _ in scheduleAudit() }
        .onChange(of: newestTreatment.value) { _, _ in scheduleAudit() }
        .onChange(of: trend.value) { _, _ in scheduleAudit() }
        .onDisappear {
            pendingAudit?.cancel()
            recordAudit(kind: .reviewHidden)
            audit.flush()
        }
    }

    private func applyFoodMeal(_ meal: CarnivalMeal) {
        guard let total = meal.carbsForReview else { return }
        foodMeal = meal
        carbText = CarnivalNumber.text(total.rounded())
        proteinText = meal.total(\.protein).map { CarnivalNumber.text($0.rounded()) } ?? ""
        fatText = meal.total(\.fat).map { CarnivalNumber.text($0.rounded()) } ?? ""
        sendFatProtein = false
    }

    private var selectedPercent: Double? { Double(customPercent.replacingOccurrences(of: ",", with: ".")) }

    private func makePlan(full: Double) -> RiceMealPlan? {
        guard let carbs, let percent = selectedPercent,
              let split = selectedCarbSplit else { return nil }
        let override: Double?
        if let text = bolusOverrideText {
            guard let value = Double(text.replacingOccurrences(of: ",", with: ".")) else { return nil }
            override = value
        } else { override = nil }
        return RiceMealPlan(carbs: carbs, fullRecommendation: full, upfrontPercent: percent, confirmedAt: Date(), carbsNowPercent: split.percent, delayMinutes: split.delay, upfrontInsulinOverride: override, preset: preset)
    }

    private var selectedCarbSplit: (percent: Double, delay: Double)? {
        guard let percent = selectedPercent, let now = Double(carbsNowText), let delay = Double(delayText) else { return nil }
        return linkedPercentages ? (percent, preset.linkedCarbDelay(percent: percent, selectedDelay: delay)) : (now, delay)
    }

    private func synchronizeCarbSplit() {
        guard linkedPercentages, let percent = selectedPercent, percent.isFinite else { return }
        carbsNowText = customPercent
        delayText = String(format: "%g", preset.linkedCarbDelay(percent: percent, selectedDelay: Double(delayText) ?? 0))
    }

    @ViewBuilder
    private var presetSection: some View {
        Group {
            Picker("Meal", selection: $preset) {
                ForEach(SmartMealPreset.allCases) { Text($0.rawValue).tag($0) }
            }
            .accessibilityIdentifier("advisor-preset")
            .onChange(of: preset) { _, value in
                carbsNowText = String(Int(value.carbsNowPercent))
                delayText = String(Int(value.delayMinutes))
                customPercent = String(Int(value.insulinPercent))
                linkedPercentages = value != .custom
                bolusOverrideText = nil
            }
            DisclosureGroup("Custom percentages and timing") {
                Toggle("Link insulin % and carbs-now %", isOn: $linkedPercentages)
                    .accessibilityIdentifier("advisor-link-percentages")
                    .onChange(of: linkedPercentages) { _, _ in synchronizeCarbSplit() }
                if !linkedPercentages {
                    HStack { Text("Carbs announced now (%)"); TextField("0–100", text: $carbsNowText).keyboardType(.decimalPad).multilineTextAlignment(.trailing) }
                }
                HStack { Text("Remaining carbs after (min)"); TextField("Minutes", text: $delayText).keyboardType(.numberPad).multilineTextAlignment(.trailing) }
                HStack { Text("Upfront insulin (%)"); TextField("0–100", text: $customPercent).keyboardType(.decimalPad).multilineTextAlignment(.trailing) }
                Text("Linked by default: the same percentage of insulin and carbs is selected now. Turn linking off to customize them separately. No later insulin bolus is scheduled.").font(.footnote)
            }
        }
    }

    private var nutrientsSection: some View {
        Section("Optional protein and fat") {
            HStack { Text("Protein (g), optional"); TextField("0", text: $proteinText).keyboardType(.numberPad) }
            HStack { Text("Fat (g), optional"); TextField("0", text: $fatText).keyboardType(.numberPad) }
            Toggle("Include protein/fat in Meal draft", isOn: $sendFatProtein)
            if sendFatProtein { warning("Trio may convert these values to FPU equivalents. Check before confirming.") }
        }
    }

    private func draft(full: Double, lowPredictionAcknowledged: Bool = false) -> SmartMealDraft? {
        let current = Date()
        guard let plan = makePlan(full: full),
              let protein = Double(sendFatProtein && !proteinText.isEmpty ? proteinText : "0"),
              let fat = Double(sendFatProtein && !fatText.isEmpty ? fatText : "0"),
              plan.upfrontInsulin <= localBolusLimit.value.doubleValue(for: .internationalUnit()),
              Double(plan.immediateCarbs + plan.delayedCarbs) <= localCarbLimit.value.doubleValue(for: .gram()) else { return nil }
        return SmartMealDraft.make(plan: plan, protein: sendFatProtein ? protein : 0, fat: sendFatProtein ? fat : 0,
                                   settings: settings.value, snapshot: snapshot.value, source: source.value,
                                   samples: history.value, newestTreatment: newestTreatment.value, now: current,
                                   lowPredictionAcknowledged: lowPredictionAcknowledged)
    }

    private func scheduleAudit() {
        pendingAudit?.cancel()
        let work = DispatchWorkItem { recordAudit(kind: .comparisonDisplayed) }
        pendingAudit = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1, execute: work)
    }

    private func recordAudit(kind: MealReviewAudit.Entry.Kind) {
        let now = Date()
        guard let payload = MealReviewAudit.Payload.capture(carbs: carbs, source: source.value, settings: settings.value, snapshot: snapshot.value, glucose: history.value, newestTreatment: newestTreatment.value, sensorArrow: trend.value, now: now, foodMeal: foodMeal) else { return }
        let details = Bundle.main.url(forResource: "BuildDetails", withExtension: "plist").flatMap { NSDictionary(contentsOf: $0) }
        let entry = MealReviewAudit.Entry(kind: kind, session: reviewSession, capturedAt: Date(), evaluatedAt: now, payload: payload, sourceRevision: details?["com-LoopFollow-commit-sha"] as? String)
        audit.record(entry) { saved in DispatchQueue.main.async { auditFailed = !saved } }
    }

    @ViewBuilder
    private func selectionSection(full: Double, comparisonOnly: Bool) -> some View {
        Group {
            if let carbs, let percent = selectedPercent,
               let split = selectedCarbSplit,
               let suggestion = RiceMealPlan(carbs: carbs, fullRecommendation: full, upfrontPercent: percent, confirmedAt: Date(), carbsNowPercent: split.percent, delayMinutes: split.delay, preset: preset)
            {
                let plan = makePlan(full: full) ?? suggestion
                row(comparisonOnly ? "Suggested comparison" : "Suggested upfront (\(customPercent)%)", units(suggestion.suggestedUpfrontInsulin))
                HStack {
                    Text("Your upfront bolus (U)")
                    TextField("Units", text: Binding(get: {
                        bolusOverrideText ?? String(format: "%.2f", suggestion.upfrontInsulin)
                    }, set: { bolusOverrideText = $0 }))
                        .keyboardType(.decimalPad).multilineTextAlignment(.trailing)
                        .focused($bolusFocused)
                        .accessibilityLabel("Your upfront bolus in units")
                        .accessibilityIdentifier("advisor-edit-bolus")
                }
                HStack {
                    Text(linkedPercentages ? "Insulin & carbs now" : "Upfront insulin")
                    Spacer()
                    Button { adjustUpfrontPercent(by: -5) } label: {
                        Image(systemName: "minus.circle.fill").font(.title2).frame(width: 44, height: 44)
                    }
                    .buttonStyle(.borderless).disabled(percent <= 0)
                    .accessibilityLabel("Reduce upfront insulin by 5 percent")
                    .accessibilityIdentifier("advisor-percent-decrease")
                    Text("\(customPercent)%").monospacedDigit().frame(minWidth: 48)
                        .accessibilityIdentifier("advisor-percent-value")
                    Button { adjustUpfrontPercent(by: 5) } label: {
                        Image(systemName: "plus.circle.fill").font(.title2).frame(width: 44, height: 44)
                    }
                    .buttonStyle(.borderless).disabled(percent >= 100)
                    .accessibilityLabel("Increase upfront insulin by 5 percent")
                    .accessibilityIdentifier("advisor-percent-increase")
                }
                Text(linkedPercentages ? "5% steps · insulin and carbs-now change together" : "5% steps · custom carb split stays unchanged").font(.caption).foregroundStyle(.secondary)
                if bolusOverrideText != nil {
                    Button("Use suggested insulin") { bolusOverrideText = nil; bolusFocused = false }
                    Text("Your edited units are copied as entered; the insulin percentage is not applied again. Carbs keep the displayed split.").font(.caption)
                }
                if makePlan(full: full) == nil {
                    warning("Enter a valid insulin amount in 0.05 U steps.")
                }
                if let actual = makePlan(full: full), let settings = settings.value, let iob = snapshot.value?.iob {
                    let limit = min(localBolusLimit.value.doubleValue(for: .internationalUnit()), settings.maxBolus, max(0, settings.maxIOB - iob))
                    if actual.upfrontInsulin > limit { warning("This amount exceeds the current limit of \(units(limit)).") }
                }
                let maximumCarbs = min(localCarbLimit.value.doubleValue(for: .gram()), snapshot.value?.smartMeal.map { NSDecimalNumber(decimal: $0.configuration.maxCarbs).doubleValue } ?? 1000)
                if carbs > maximumCarbs { warning("The current meal-carb limit is \(Int(maximumCarbs)) g.") }
                row("Carbs now", "\(plan.immediateCarbs) g")
                row("Carbs later", plan.delayedCarbs > 0 ? "\(plan.delayedCarbs) g at +\(String(format: "%g", plan.delayMinutes)) min" : "None")
                if plan.delayedCarbs > 0 && !SmartMealDelivery.available(snapshot: snapshot.value, settings: settings.value, bundleID: Storage.shared.bundleId.value, now: Date()) {
                    warning(RiceMealPlan.sendingBlocker)
                }
                Text("No later insulin bolus. Use these values copies your choice into Meal for final confirmation.").font(.caption)
            } else { warning("Enter whole-gram carbs (1–1000), percentages from 0–100, and a positive delay for split carbs.") }
        }
    }

    private func adjustUpfrontPercent(by change: Double) {
        guard let current = selectedPercent, current.isFinite else { return }
        customPercent = String(format: "%g", min(100, max(0, current + change)))
        bolusOverrideText = nil
        bolusFocused = false
        carbsFocused = false
    }

    func useRecommendation(full: Double) {
        // Revalidate at the tap, not just at the last display refresh.
        guard let draft = draft(full: full, lowPredictionAcknowledged: true) else { return }
        carbsFocused = false
        bolusFocused = false
        if draft.lowPredictionAcknowledged, draft.plan.upfrontInsulin > 0 {
            pendingForecastDraft = draft
            forecastWarningPresented = true
            return
        }
        onUse(draft)
        dismiss()
    }

    private func acceptForecastReview(_ reviewed: SmartMealDraft) {
        let now = Date()
        guard reviewed.isCurrent(now: now, settings: settings.value, snapshot: snapshot.value, source: source.value),
              SmartMealDraft.prefillReasons(settings: settings.value, snapshot: snapshot.value, source: source.value,
                                            samples: history.value, newestTreatment: newestTreatment.value, now: now,
                                            allowLowPredictionReview: true).isEmpty
        else {
            pendingForecastDraft = nil
            forecastReviewError = "The live inputs changed while this warning was open. Review the updated values, or open manual Meal."
            return
        }
        onUse(reviewed)
        pendingForecastDraft = nil
        dismiss()
    }

    private func forecastWarningMessage(_ reviewed: SmartMealDraft) -> String {
        let s = reviewed.snapshot
        let minimum = s.minPredMgdl.map(displayGlucose) ?? "Unavailable"
        let guardMinimum = s.minGuardMgdl.map(displayGlucose) ?? "Unavailable"
        let eventual = s.eventualMgdl.map(displayGlucose) ?? "Unavailable"
        return "Selected minimum: \(minimum). Guard minimum: \(guardMinimum). Eventual endpoint: \(eventual). These forecasts do not include this new meal and may be wrong. You selected \(units(reviewed.plan.upfrontInsulin)), with \(reviewed.plan.immediateCarbs) g now and \(reviewed.plan.delayedCarbs) g later. Accept opens editable Meal; it does not send anything."
    }

    @ViewBuilder
    private func transferBar(now: Date) -> some View {
        let result = carbs.flatMap {
            MealReviewFullCalculation.comparison(newCarbs: $0, settings: settings.value, snapshot: snapshot.value,
                                                 source: source.value, samples: history.value, newestTreatment: newestTreatment.value, now: now)
        }
        let selected = result.flatMap { draft(full: $0.rounded, lowPredictionAcknowledged: true) }
        let needsSettings = settings.value.map {
            $0.isHistorical || !$0.matches(source: source.value, version: snapshot.value?.trioVersion, now: now)
                || !(0 ... 86400).contains(now.timeIntervalSince($0.checkedAt))
        } ?? true
        VStack(spacing: 6) {
            if let selected, let result {
                Button {
                    useRecommendation(full: result.rounded)
                } label: {
                    Text("Use these values · \(selected.plan.immediateCarbs) g + \(units(selected.plan.upfrontInsulin))")
                        .frame(maxWidth: .infinity)
                }
                .accessibilityIdentifier("advisor-review-meal")
                Text("Opens editable Meal. Nothing is sent until you confirm.").font(.caption)
            } else if needsSettings {
                Text("Insulin transfer needs current Trio settings. The Trio receiver update uploads them automatically; older Trio builds need a manual check.")
                    .font(.caption).fixedSize(horizontal: false, vertical: true)
                Button("Check Trio settings to enable transfer") {
                    carbsFocused = false
                    settingsPresented = true
                }
                .frame(maxWidth: .infinity)
                .accessibilityIdentifier("advisor-check-settings")
            } else {
                Button("Use these values") {}.frame(maxWidth: .infinity).disabled(true)
                Text(carbs.map { $0 > 0 } == true
                    ? "Transfer held. See the calculation checks above and correct any invalid meal values."
                    : "Enter meal carbs above to continue.")
                    .font(.caption).fixedSize(horizontal: false, vertical: true)
            }
            if let onManualMeal {
                Button("Enter Meal manually") {
                    let amount = carbs.flatMap { $0.isFinite && (0 ... 1000).contains($0) && $0.rounded() == $0 ? $0 : nil } ?? 0
                    carbsFocused = false
                    bolusFocused = false
                    onManualMeal(amount)
                    dismiss()
                }
                .buttonStyle(.bordered)
                .frame(maxWidth: .infinity)
                .accessibilityIdentifier("advisor-manual-meal")
                Text("Copies full meal carbs with no calculated insulin or delayed entry. Meal stays editable.").font(.caption)
            }
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(.bar)
    }

    @ViewBuilder
    private func fullSection(now: Date) -> some View {
        Section("Insulin") {
            let prefillHolds = SmartMealDraft.prefillReasons(settings: settings.value, snapshot: snapshot.value, source: source.value, samples: history.value, newestTreatment: newestTreatment.value, now: now, allowLowPredictionReview: snapshot.value?.smartMeal?.allowsLowPredictionReview == true)
            let issues = MealReviewFullCalculation.reasons(settings: settings.value, snapshot: snapshot.value, source: source.value, now: now)
                + MealReviewCalculation.reasons(snapshot: snapshot.value, samples: history.value, newestTreatment: newestTreatment.value, now: now, includeSafetyHolds: false)
            if !issues.isEmpty {
                Text("Calculation unavailable").font(.headline)
                ForEach(issues, id: \.self) { warning($0) }
            } else if let carbs, carbs > 0,
                      let result = MealReviewFullCalculation.comparison(newCarbs: carbs, settings: settings.value, snapshot: snapshot.value, source: source.value, samples: history.value, newestTreatment: newestTreatment.value, now: now)
            {
                if prefillHolds.isEmpty {
                    row("Full recommendation", units(result.rounded)).font(.headline)
                } else {
                    Text("Comparison only — dose prefill held").font(.headline)
                    row("Calculated comparison, not a dose", units(result.rounded)).font(.title2.weight(.semibold))
                }
                selectionSection(full: result.rounded, comparisonOnly: !prefillHolds.isEmpty)
                if MealReviewCalculation.lowPredictionNeedsReview(snapshot.value) {
                    warning("Low forecast before this new meal. Review the values before accepting a calculated dose.")
                    if let minimum = snapshot.value?.minPredMgdl { row("Selected minimum", displayGlucose(minimum)) }
                    if let minimum = snapshot.value?.minGuardMgdl { row("Guard minimum", displayGlucose(minimum)) }
                    if let eventual = snapshot.value?.eventualMgdl { row("Eventual endpoint", displayGlucose(eventual)) }
                    Text("The eventual value is not the minimum. These forecasts do not include the new meal above.").font(.caption)
                    if snapshot.value?.smartMeal?.allowsLowPredictionReview != true {
                        Text("The matching Trio warning-review update enables calculated transfer here. Manual Meal is available now.").font(.caption)
                    }
                }
                ForEach(prefillHolds, id: \.self) { warning($0) }
                if let forecastReviewError { warning(forecastReviewError) }
                Text("Full meal calculation updates automatically. Your selected amount stays editable before sending.").font(.caption)
                if result.rounded > localBolusLimit.value.doubleValue(for: .internationalUnit()) {
                    warning("The full comparison exceeds LoopFollow's local bolus limit. The selected upfront amount must fit that limit before prefill.")
                }
                DisclosureGroup("Calculation details") {
                    row("Carbs after Max COB", String(format: "%.1f g", result.cappedCarbs))
                    row("Carb contribution", signedUnits(result.carbUnits))
                    row("Glucose relative to target", signedUnits(result.correctionUnits))
                    row("Recent glucose change", signedUnits(result.trendUnits))
                    row("Remaining net IOB", signedUnits(result.iobCreditUnits))
                    row("Balance before percentage", signedUnits(result.balance))
                    row("After copied percentage", units(result.afterPercentage))
                    row("After maximum bolus", units(result.afterBolusLimit))
                    row("After maximum IOB", units(result.afterIOBLimit))
                    row("DASH rounding down", units(result.rounded))
                }
                if let baseline = MealReviewFullCalculation.review(newCarbs: 0, settings: settings.value, snapshot: snapshot.value, source: source.value, samples: history.value, newestTreatment: newestTreatment.value, now: now),
                   let native = snapshot.value?.nativeRecommendation
                {
                    DisclosureGroup("Check against Trio's upload") {
                        row("Our zero-new-carb comparison", units(baseline.rounded))
                        row("Trio's zero-new-carb upload", units(native))
                        Text("These checks exclude the new meal. Agreement alone does not validate the meal calculation or prove the copied settings are correct.").font(.footnote)
                    }
                    if abs(baseline.rounded - native) > 0.0001 { warning("The zero-new-carb calculations differ. Recheck settings and wait for a fresh Trio cycle. This comparison is not verified.") }
                }
            } else if carbs.map({ $0.isFinite && $0 > 0 }) != true {
                Text("Enter meal carbs above to calculate automatically. No insulin amount is required.")
            } else { warning("Calculation could not be completed from these inputs. Check the saved settings and live data.") }
            if let s = settings.value {
                DisclosureGroup("Saved calculator settings") {
                    row("Bolus percentage", String(format: "%.0f%%", s.percentage))
                    row("Max IOB", units(s.maxIOB))
                    row("Max COB", String(format: "%.0f g", s.maxCOB))
                    row("Maximum bolus", units(s.maxBolus))
                    if let reference = s.historicalReference { Text(reference).font(.footnote) }
                }
            }
            Button(settings.value == nil ? "Enter current Trio settings" : "Check copied Trio settings") { settingsPresented = true }
            if let s = settings.value {
                Text("\(s.isHistorical ? "Historical values entered" : "Values last checked") \(s.checkedAt.formatted(date: .abbreviated, time: .shortened)). Standard calculation; reduced and super bolus excluded.").font(.footnote)
            }
            if let arrow = trend.value, ["SingleDown", "DoubleDown", "FortyFiveDown"].contains(arrow) {
                warning("The sensor arrow is downward. Review the glucose trace and insulin activity before making any treatment decision.")
            }
            if snapshot.value?.isfSource == "Trio reason (rounded)" { warning("Effective ISF came from rounded reason text; this comparison is approximate.") }
        }
    }

    @ViewBuilder
    private func activitySection(now: Date) -> some View {
        Section {
            DisclosureGroup("Insulin activity details") {
                if let s = snapshot.value, MealReviewSnapshot.fresh(s.iobDate, now: now), MealReviewSnapshot.fresh(s.date, now: now) {
                    row("Remaining net IOB", s.iob.map(units) ?? "Unavailable")
                    row("Net insulin activity", s.activity.map { String(format: "%.4f U/min", $0) } ?? "Unavailable")
                    if let effect = MealReviewCalculation.insulinEffect(activity: s.activity, isf: s.effectiveISF) {
                        row("Modeled effect over 5 min", signedGlucose(effect))
                        Text("Activity × effective ISF × 5 minutes. This is the modeled insulin effect relative to scheduled basal, before food and other influences; it is not a forecast of the actual glucose change.").font(.footnote)
                    }
                } else { Text("Waiting for fresh Trio insulin activity.") }
                Text("IOB already includes Trio's insulin curve and elapsed time. Activity describes its current rate of action. The review does not discount IOB a second time.").font(.footnote)
            }
        }
    }

    @ViewBuilder
    private func contextSection(now: Date) -> some View {
        Section {
            DisclosureGroup("All live inputs & timestamps") {
                let latest = MealReviewCalculation.latestGlucose(samples: history.value, now: now)
                row("Glucose", latest.map { displayGlucose($0.mgdl) } ?? "Unavailable")
                row("Glucose age", age(latest?.date, now: now))
                row("Sensor arrow", trend.value ?? "Unavailable")
                row("Change in recent 20 min window", MealReviewCalculation.recentDelta(samples: history.value, now: now).map(signedGlucose) ?? "Unavailable")
                row("Carb ratio", snapshot.value?.carbRatio.map { String(format: "%.2f g/U", $0) } ?? "Unavailable")
                row("Ratio source", snapshot.value?.ratioSource ?? "Unavailable")
                row("Effective ISF", snapshot.value?.effectiveISF.map { displayGlucose($0) + "/U" } ?? "Unavailable")
                row("ISF source", snapshot.value?.isfSource ?? "Unavailable")
                row("Trio target", snapshot.value?.targetMgdl.map(displayGlucose) ?? "Unavailable")
                row("Upload glucose units", snapshot.value?.uploadUnitSource ?? "Unavailable")
                row("Trio calculation age", age(snapshot.value?.date, now: now))
                row("IOB age", age(snapshot.value?.iobDate, now: now))
                row("COB", snapshot.value?.cob.map { String(format: "%.1f g", $0) } ?? "Unavailable")
                row("Selected minimum prediction", snapshot.value?.minPredMgdl.map(displayGlucose) ?? "Unavailable")
                row("Guard prediction", snapshot.value?.minGuardMgdl.map(displayGlucose) ?? "Unavailable")
            }
        }
    }

    private struct ForecastPoint: Identifiable {
        let model: String
        let index: Int
        let date: Date
        let glucose: Double
        var id: String { model + String(index) }
    }

    private func forecastPoints(_ s: MealReviewSnapshot) -> [ForecastPoint] {
        guard let date = s.date else { return [] }
        return ["IOB", "COB", "UAM", "ZT"].flatMap { name in
            (s.predictions[name] ?? []).enumerated().map {
                ForecastPoint(model: name, index: $0.offset, date: date.addingTimeInterval(Double($0.offset) * 300), glucose: displayValue($0.element))
            }
        }
    }

    @ViewBuilder
    private func forecastSection(now: Date) -> some View {
        Section {
            DisclosureGroup("Trio forecasts · before this new meal") {
                if let s = snapshot.value, MealReviewSnapshot.fresh(s.date, now: now), !s.predictions.isEmpty {
                    Chart(forecastPoints(s)) { point in
                        LineMark(x: .value("Time", point.date), y: .value("Glucose", point.glucose))
                            .foregroundStyle(by: .value("Model", point.model))
                    }
                    .chartYAxisLabel(UnitSettingsStore.shared.glucoseUnit.rawValue)
                    .frame(height: 210)
                    Text("IOB: insulin without new food. COB: existing carb absorption. UAM: estimated unannounced food. ZT: zero-temp scenario. These uploaded curves do not include the meal carbs entered above. An IOB-only low is not the same as Trio's selected minimum prediction.").font(.footnote)
                } else { Text("Fresh forecast curves are unavailable.") }
            }
        }
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack { Text(label); Spacer(); Text(value).foregroundStyle(.secondary).multilineTextAlignment(.trailing).monospacedDigit() }
    }

    private func units(_ value: Double) -> String { String(format: "%.2f U", value) }
    private func signedUnits(_ value: Double) -> String { (value > 0 ? "+" : value < 0 ? "−" : "") + units(abs(value)) }
    private func signedGlucose(_ value: Double) -> String { (value > 0 ? "+" : value < 0 ? "−" : "") + displayGlucose(abs(value)) }
    private func displayValue(_ mgdl: Double) -> Double { UnitSettingsStore.shared.convertMgdlToDisplay(mgdl) }
    private func displayGlucose(_ mgdl: Double) -> String {
        Localizer.formatQuantity(HKQuantity(unit: .milligramsPerDeciliter, doubleValue: mgdl)) + " " + UnitSettingsStore.shared.glucoseUnit.rawValue
    }

    private func warning(_ text: String) -> some View { Label(text, systemImage: "exclamationmark.triangle").foregroundStyle(.orange) }
    private func age(_ date: Date?, now: Date) -> String {
        guard let date else { return "Unavailable" }
        let seconds = now.timeIntervalSince(date)
        guard seconds >= -60 else { return "Future timestamp" }
        return String(format: "%.0f min", max(0, seconds) / 60)
    }
}
