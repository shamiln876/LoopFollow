// LoopFollow
// MealReviewView.swift

import Charts
import Combine
import HealthKit
import SwiftUI

struct MealReviewView: View {
    let initialCarbs: Double
    @Environment(\.dismiss) private var dismiss
    @State private var carbText: String
    @State private var now = Date()
    @FocusState private var carbsFocused: Bool
    @ObservedObject private var snapshot = Observable.shared.mealReview
    @ObservedObject private var history = Observable.shared.mealReviewGlucose
    @ObservedObject private var newestTreatment = Observable.shared.mealReviewNewestTreatment
    @ObservedObject private var trend = Storage.shared.lastTrendCode

    init(initialCarbs: Double) {
        self.initialCarbs = initialCarbs
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
                balanceSection(now: now)
                activitySection(now: now)
                contextSection(now: now)
                forecastSection(now: now)
                Section("Before this can become a dose") {
                    Text("The balance is before Trio's Recommended Bolus Percentage, maximum COB, maximum bolus, maximum IOB and pump rounding. These settings are not all available through Nightscout. A final meal dose cannot be verified yet.")
                    if let s = snapshot.value, s.trioVersion == "1.0.2", let native = s.nativeRecommendation, MealReviewSnapshot.fresh(s.date, now: now) {
                        row("Trio upload: zero new carbs", units(native))
                        Text("This uploaded recommendation was calculated by Trio without the meal carbs entered above. It is not the recommendation for this meal.").font(.footnote)
                    }
                    DisclosureGroup("What the model includes") {
                        Text("New carbs and existing estimated COB are divided by Trio's active carb ratio. Glucose correction and recent glucose change use the reported effective ISF. Remaining net IOB is subtracted once. IOB and activity are relative to scheduled basal; negative values can represent a basal deficit. This review does not model absorption of the new meal, future SMBs, future ISF changes, or delivery that has not yet reached Nightscout. Uploaded predictions can be wrong. Entries here do not change the Meal or Bolus screens.")
                            .font(.footnote)
                    }
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
        .onAppear { now = Date() }
        .onReceive(Timer.publish(every: 5, on: .main, in: .common).autoconnect()) { now = $0 }
    }

    @ViewBuilder
    private func balanceSection(now: Date) -> some View {
        Section("Meal balance · review only") {
            if blockers(now: now).isEmpty, let carbs,
               let balance = MealReviewCalculation.review(newCarbs: carbs, snapshot: snapshot.value, samples: history.value, newestTreatment: newestTreatment.value, now: now)
            {
                row("Net model balance", units(balance.total)).font(.title3.weight(.semibold))
                Text("Not a dose to deliver. Percentage and limits have not been applied.").font(.footnote.weight(.semibold))
                DisclosureGroup("Calculation breakdown") {
                    row("New meal carbs", signedUnits(balance.newCarbUnits))
                    row("Existing COB", signedUnits(balance.existingCarbUnits))
                    row("Glucose relative to target", signedUnits(balance.correctionUnits))
                    row("Recent glucose change", signedUnits(balance.trendUnits))
                    row("Remaining net IOB", signedUnits(balance.iobCreditUnits))
                }
                if balance.total <= 0 { Text("The model balance is zero or negative before percentage and limits. This does not predict whether the new meal will cause a later rise.").font(.footnote) }
            } else {
                Text("Review on hold").font(.headline)
                ForEach(blockers(now: now), id: \.self) { warning($0) }
            }
            if let arrow = trend.value, ["SingleDown", "DoubleDown", "FortyFiveDown"].contains(arrow) {
                warning("The sensor arrow is downward. Review the glucose trace and insulin activity before making any treatment decision.")
            }
            if snapshot.value?.isfSource == "Trio reason (rounded)" { warning("Effective ISF came from rounded reason text; this balance is approximate.") }
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
