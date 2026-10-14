// LoopFollow
// MealReviewView.swift

import HealthKit
import SwiftUI

struct MealReviewView: View {
    let initialCarbs: Double
    @Environment(\.dismiss) private var dismiss
    @State private var carbText = ""
    @FocusState private var carbsFocused: Bool
    @ObservedObject private var snapshot = Observable.shared.mealReview
    @ObservedObject private var glucose = Observable.shared.bg
    @ObservedObject private var glucoseTime = Storage.shared.lastBgReadingTimeSeconds
    @ObservedObject private var delta = Storage.shared.lastDeltaMgdl
    @ObservedObject private var trend = Storage.shared.lastTrendCode

    private var glucoseDate: Date? { glucoseTime.value.map { Date(timeIntervalSince1970: $0) } }
    private var carbs: Double? { Double(carbText.replacingOccurrences(of: ",", with: ".")) }
    private var trendHold: MealReviewSnapshot.TrendHold? { MealReviewSnapshot.trendHold(delta: delta.value, trend: trend.value) }
    private var changeText: String {
        guard let change = delta.value, change.isFinite else { return "Unavailable" }
        return (change > 0 ? "+" : change < 0 ? "−" : "") + displayGlucose(abs(change))
    }

    private var trendHoldMessage: String? {
        switch trendHold {
        case .downwardArrow: return "The sensor reports a downward arrow. The prototype keeps its arithmetic hidden."
        case .negativeChange: return "Latest glucose change is \(changeText), despite the \(trend.value ?? "unavailable") arrow. The prototype holds arithmetic on any decline; this does not measure how quickly glucose is falling."
        case .unavailable: return "Glucose trend is unavailable."
        case nil: return nil
        }
    }

    private func blockers(now: Date) -> [String] {
        var reasons: [String] = []
        if carbs.map({ $0.isFinite && $0 > 0 }) != true { reasons.append("Enter a positive carb amount.") }
        if glucose.value == nil { reasons.append("Glucose is unavailable.") }
        if !MealReviewSnapshot.fresh(glucoseDate, now: now) { reasons.append("Glucose timestamp is missing, over 10 minutes old, or in the future.") }
        if let bg = glucose.value, bg < 70 { reasons.append("Glucose is below \(displayGlucose(70)). Follow the established hypoglycemia treatment plan before meal review.") }
        if let snapshot = snapshot.value {
            if !MealReviewSnapshot.fresh(snapshot.date, now: now) { reasons.append("Trio calculation timestamp is missing, over 10 minutes old, or in the future.") }
            if snapshot.carbRatio == nil { reasons.append("Carb ratio is unavailable.") }
            if snapshot.iob == nil { reasons.append("IOB is unavailable; missing IOB is not zero.") }
            if !MealReviewSnapshot.fresh(snapshot.iobDate, now: now) { reasons.append("IOB timestamp is missing, over 10 minutes old, or in the future.") }
            if snapshot.cob == nil { reasons.append("COB is unavailable; missing COB is not zero.") }
        } else { reasons.append("A successful Trio calculation is unavailable.") }
        if let message = trendHoldMessage { reasons.append(message) }
        return reasons
    }

    var body: some View {
        NavigationView {
            TimelineView(.periodic(from: .now, by: 5)) { context in
                Form {
                    Section("Review only") {
                        Text("Enter carbs to review. This screen cannot send carbs or insulin.")
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
                    Section("Carb-ratio arithmetic") {
                        if let carbs,
                           let units = snapshot.value?.reviewEquivalent(carbs: carbs, glucose: glucose.value.map(Double.init), glucoseDate: glucoseDate, delta: delta.value, trend: trend.value, now: context.date)
                        {
                            row("Carbs ÷ ratio", String(format: "%.2f U", units))
                        } else {
                            Text("Arithmetic on hold").font(.headline)
                            ForEach(blockers(now: context.date), id: \.self) { reason in warning(reason) }
                        }
                        Text("Carb-only insulin equivalent. Not a bolus recommendation.").font(.footnote)
                    }
                    Section("Live context") {
                        row("Glucose", glucose.value.map { displayGlucose(Double($0)) } ?? "Unavailable")
                        row("Glucose age", age(glucoseDate, now: context.date))
                        row("Sensor arrow", trend.value ?? "Unavailable")
                        row("Change since previous reading", changeText)
                        row("Carb ratio", snapshot.value?.carbRatio.map { String(format: "%.2f g/U", $0) } ?? "Unavailable")
                        row("Ratio source", snapshot.value?.ratioSource ?? "Unavailable")
                        row("Trio calculation age", age(snapshot.value?.date, now: context.date))
                        row("IOB", snapshot.value?.iob.map { String(format: "%.2f U", $0) } ?? "Unavailable")
                        row("IOB age", age(snapshot.value?.iobDate, now: context.date))
                        row("COB", snapshot.value?.cob.map { String(format: "%.1f g", $0) } ?? "Unavailable")
                    }
                    Section("Notes") {
                        if snapshot.value?.ratioSource == "Scheduled profile fallback" { warning("Trio did not report a valid ratio. The scheduled profile fallback may not reflect an active override.") }
                        if let iob = snapshot.value?.iob, iob > 0 { warning("Trio reports \(String(format: "%.2f", iob)) U IOB. The carb-only arithmetic does not subtract it or account for additional SMBs.") }
                        DisclosureGroup("What this review includes") {
                            Text("This is a carb-only insulin equivalent, not a bolus recommendation. No correction or IOB subtraction is applied. Trio IOB is modeled active insulin above or below scheduled basal; COB is estimated unabsorbed carbohydrate. Future SMBs and delayed meal absorption are not modeled. Entries here do not change the Meal or Bolus screens.")
                                .font(.footnote)
                        }
                    }
                }
                .scrollDismissesKeyboard(.interactively)
            }
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
        .onAppear { carbText = initialCarbs > 0 ? String(format: "%.1f", initialCarbs) : "" }
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack { Text(label); Spacer(); Text(value).foregroundStyle(.secondary).multilineTextAlignment(.trailing) }
    }

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
