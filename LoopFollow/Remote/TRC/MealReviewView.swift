// LoopFollow
// MealReviewView.swift

import Charts
import Combine
import HealthKit
import SwiftUI

struct MealReviewView: View {
    let initialCarbs: Double
    @Environment(\.dismiss) private var dismiss
    @State private var riceSelected = false
    @State private var upfrontPercent = 100.0
    @State private var customPercent = "100"
    @State private var carbText: String
    @State private var now = Date()
    @State private var settingsPresented = false
    @State private var reviewSession = UUID()
    @State private var pendingAudit: DispatchWorkItem?
    @State private var auditFailed = false
    private let audit: MealReviewAuditStore
    @ObservedObject private var settings: StorageValue<MealReviewSettings?>
    @ObservedObject private var source: StorageValue<String>
    @ObservedObject private var localBolusLimit = Storage.shared.maxBolus
    @FocusState private var carbsFocused: Bool
    @ObservedObject private var snapshot = Observable.shared.mealReview
    @ObservedObject private var history = Observable.shared.mealReviewGlucose
    @ObservedObject private var newestTreatment = Observable.shared.mealReviewNewestTreatment
    @ObservedObject private var trend = Storage.shared.lastTrendCode

    init(initialCarbs: Double, settings: StorageValue<MealReviewSettings?> = Storage.shared.mealReviewSettings, source: StorageValue<String> = Storage.shared.url, audit: MealReviewAuditStore = .shared) {
        self.initialCarbs = initialCarbs
        self.audit = audit
        _settings = ObservedObject(wrappedValue: settings)
        _source = ObservedObject(wrappedValue: source)
        _carbText = State(initialValue: initialCarbs.isFinite && initialCarbs > 0 ? String(format: "%.1f", initialCarbs) : "")
    }

    private var carbs: Double? { Double(carbText.replacingOccurrences(of: ",", with: ".")) }

    private func blockers(now: Date) -> [String] {
        var reasons = MealReviewCalculation.reasons(snapshot: snapshot.value, samples: history.value, newestTreatment: newestTreatment.value, now: now)
        if carbs.map({ $0.isFinite && $0 > 0 }) != true { reasons.insert("Enter a positive carb amount.", at: 0) }
        return reasons
    }

    var body: some View {
        NavigationView {
            Form {
                Section("Live meal review") {
                    Text("Enter carbs to review. Values update automatically. This screen cannot send carbs or insulin.")
                    HStack {
                        Text("Meal carbs (g)")
                        TextField("Amount", text: $carbText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .focused($carbsFocused)
                            .accessibilityLabel("Meal carbs in grams")
                    }
                    if carbsFocused { Button("Hide keyboard") { carbsFocused = false } }
                }
                riceSection
                fullSection(now: now)
                activitySection(now: now)
                contextSection(now: now)
                forecastSection(now: now)
                Section("Comparison limitations") {
                    Text("The comparison applies your copied percentage and limits. Its intermediate arithmetic is under Calculation details. It has not been validated as a dose for your dad and cannot send or prefill insulin.")
                    DisclosureGroup("What the model includes") {
                        Text("New carbs and existing estimated COB are divided by Trio's active carb ratio. Glucose correction and recent glucose change use the reported effective ISF. Remaining net IOB is subtracted once. IOB and activity are relative to scheduled basal; negative values can represent a basal deficit. This review does not model absorption of the new meal, future SMBs, future ISF changes, or delivery that has not yet reached Nightscout. Uploaded predictions can be wrong. Entries here do not change the Meal or Bolus screens.")
                            .font(.footnote)
                    }
                }
                Section("Comparison history") {
                    Text("Displayed comparisons and their inputs are saved on this iPhone for up to 14 days, for review alongside actual Nightscout deliveries. A saved comparison does not confirm insulin was given.").font(.footnote)
                    if auditFailed { warning("Comparison history could not be saved. Keep a screenshot of this review.") }
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("Smart Meal Advisor")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Close") { dismiss() } }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Hide keyboard") { carbsFocused = false }
                }
            }
        }
        .sheet(isPresented: $settingsPresented) { MealReviewSettingsView(saved: settings, source: source) }
        .onAppear { MealReviewSettingsImport.consumePending(); now = Date(); scheduleAudit() }
        .onReceive(Timer.publish(every: 5, on: .main, in: .common).autoconnect()) { now = $0; scheduleAudit() }
        .onChange(of: carbText) { _, _ in scheduleAudit() }
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

    private var selectedPercent: Double? { Double(customPercent.replacingOccurrences(of: ",", with: ".")) }

    @ViewBuilder
    private var riceSection: some View {
        Section("Carbohydrate announcement") {
            Toggle("Rice · 75% now / 25% at +30 min", isOn: $riceSelected)
            if riceSelected {
                Text("Preview only · automatic sending unavailable").font(.headline).foregroundStyle(.orange)
                if let carbs, carbs >= 4, carbs <= 1000, carbs.rounded() == carbs {
                    let later = Int((carbs * 0.25).rounded())
                    Text("Now: \(Int(carbs) - later) g · +30 minutes: \(later) g")
                    Text("Whole-gram entries preserve the total. Small totals may differ from exactly 75/25. The delay would start at confirmation, not when this preview opens.").font(.footnote)
                } else {
                    warning("Rice requires whole-gram carbs from 4–1000 g for this preview; delivery limits still apply separately.")
                }
                Picker("Upfront insulin percentage", selection: $upfrontPercent) {
                    ForEach([50.0, 60, 70, 75, 80, 90, 100], id: \.self) { value in
                        Text(String(format: "%.0f%%", value)).tag(value)
                    }
                }
                .onChange(of: upfrontPercent) { _, value in customPercent = String(format: "%.0f", value) }
                HStack {
                    Text("Custom upfront %")
                    TextField("0–100", text: $customPercent).keyboardType(.decimalPad).multilineTextAlignment(.trailing)
                }
                Text("No second insulin bolus. Unselected insulin is not owed; Trio would reassess subsequent needs.").font(.footnote)
                warning(RiceMealPlan.sendingBlocker)
            }
        }
    }

    private func scheduleAudit() {
        pendingAudit?.cancel()
        let work = DispatchWorkItem { recordAudit(kind: .comparisonDisplayed) }
        pendingAudit = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1, execute: work)
    }

    private func recordAudit(kind: MealReviewAudit.Entry.Kind) {
        guard let payload = MealReviewAudit.Payload.capture(carbs: carbs, source: source.value, settings: settings.value, snapshot: snapshot.value, glucose: history.value, newestTreatment: newestTreatment.value, sensorArrow: trend.value, now: now) else { return }
        let details = Bundle.main.url(forResource: "BuildDetails", withExtension: "plist").flatMap { NSDictionary(contentsOf: $0) }
        let entry = MealReviewAudit.Entry(kind: kind, session: reviewSession, capturedAt: Date(), evaluatedAt: now, payload: payload, sourceRevision: details?["com-LoopFollow-commit-sha"] as? String)
        audit.record(entry) { saved in DispatchQueue.main.async { auditFailed = !saved } }
    }

    @ViewBuilder
    private func fullSection(now: Date) -> some View {
        Section("Full calculation · comparison only") {
            if let s = settings.value, let reference = s.historicalReference {
                warning("Historical settings — not verified current. Comparison for testing only.")
                Text(reference).font(.footnote)
            }
            if let s = settings.value {
                DisclosureGroup("Saved comparison settings") {
                    row("Bolus percentage", String(format: "%.0f%%", s.percentage))
                    row("Max IOB", units(s.maxIOB))
                    row("Max COB", String(format: "%.0f g", s.maxCOB))
                    row("Maximum bolus", units(s.maxBolus))
                }
            }
            let issues = MealReviewFullCalculation.reasons(settings: settings.value, snapshot: snapshot.value, source: source.value, now: now) + blockers(now: now)
            if !issues.isEmpty {
                Text("Review on hold").font(.headline)
                ForEach(issues, id: \.self) { warning($0) }
            } else if let carbs, carbs > 0,
                      let result = MealReviewFullCalculation.review(newCarbs: carbs, settings: settings.value, snapshot: snapshot.value, source: source.value, samples: history.value, newestTreatment: newestTreatment.value, now: now)
            {
                row("Trio-style comparison", units(result.rounded)).font(.title3.weight(.semibold))
                if riceSelected {
                    row("Full comparison before upfront selection", units(result.rounded))
                    if let percent = selectedPercent,
                       let plan = RiceMealPlan(carbs: carbs, fullRecommendation: result.rounded, upfrontPercent: percent, confirmedAt: now) {
                        row("Selected upfront · preview only", units(plan.upfrontInsulin))
                        row("Second insulin bolus", "None")
                        Text("Upfront percentage applies to the displayed comparison, which already includes the saved comparison percentage and limits.").font(.footnote)
                    } else { warning("Enter valid whole-gram carbs and an upfront percentage from 0–100.") }
                }

                Text("For comparison in Trio only. Not a validated dose to deliver.").font(.footnote.weight(.semibold))
                if result.rounded > localBolusLimit.value.doubleValue(for: .internationalUnit()) {
                    warning("This exceeds LoopFollow's separate local bolus limit. No amount is transferred or sent.")
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
            } else { Text("Waiting for complete calculation inputs.") }
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
        Section("How strongly IOB is acting now") {
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

    @ViewBuilder
    private func contextSection(now: Date) -> some View {
        Section("Live context") {
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
        Section("Trio forecasts · before this new meal") {
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
