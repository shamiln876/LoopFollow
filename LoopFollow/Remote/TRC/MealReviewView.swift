// LoopFollow
// MealReviewView.swift

import HealthKit
import SwiftUI

struct MealReviewView: View {
    let initialCarbs: Double
    @Environment(\.dismiss) private var dismiss
    @State private var carbText = ""
    @ObservedObject private var snapshot = Observable.shared.mealReview
    @ObservedObject private var glucose = Observable.shared.bg
    @ObservedObject private var glucoseTime = Storage.shared.lastBgReadingTimeSeconds
    @ObservedObject private var delta = Storage.shared.lastDeltaMgdl
    @ObservedObject private var trend = Storage.shared.lastTrendCode

    private var glucoseDate: Date? { glucoseTime.value.map { Date(timeIntervalSince1970: $0) } }
    private var falling: Bool {
        (delta.value.map { $0 < 0 } ?? false) || ["SingleDown", "DoubleDown", "FortyFiveDown"].contains(trend.value ?? "")
    }

    private var trendAvailable: Bool {
        delta.value.map { $0.isFinite } == true || ["Flat", "FortyFiveUp", "SingleUp", "DoubleUp", "FortyFiveDown", "SingleDown", "DoubleDown"].contains(trend.value ?? "")
    }

    var body: some View {
        NavigationView {
            TimelineView(.periodic(from: .now, by: 5)) { context in
                Form {
                    Section("Review only") {
                        Text("This screen cannot send carbs or insulin. Values entered here do not change the Meal or Bolus screens.")
                        TextField("Meal carbs (g)", text: $carbText).keyboardType(.decimalPad)
                    }
                    Section("Live context") {
                        row("Glucose", glucose.value.map { Localizer.formatQuantity(HKQuantity(unit: .milligramsPerDeciliter, doubleValue: Double($0))) } ?? "Unavailable")
                        row("Glucose age", age(glucoseDate, now: context.date))
                        row("Trend", trend.value ?? "Unavailable")
                        row("Carb ratio", snapshot.value?.carbRatio.map { String(format: "%.2f g/U", $0) } ?? "Unavailable")
                        row("Ratio source", snapshot.value?.ratioSource ?? "Unavailable")
                        row("Trio calculation age", age(snapshot.value?.date, now: context.date))
                        row("IOB", snapshot.value?.iob.map { String(format: "%.2f U", $0) } ?? "Unavailable")
                        row("IOB age", age(snapshot.value?.iobDate, now: context.date))
                        row("COB", snapshot.value?.cob.map { String(format: "%.1f g", $0) } ?? "Unavailable")
                    }
                    Section("Carb-ratio arithmetic") {
                        if let carbs = Double(carbText.replacingOccurrences(of: ",", with: ".")),
                           let units = snapshot.value?.carbEquivalent(carbs: carbs, glucose: glucose.value.map(Double.init), glucoseDate: glucoseDate, now: context.date), trendAvailable, !falling
                        {
                            row("Carbs ÷ ratio", String(format: "%.2f U", units))
                        } else {
                            Text("Arithmetic unavailable: enter positive carbs and wait for complete, fresh data with glucose at least 70 mg/dL and no falling trend.")
                        }
                        Text("This is a carb-only insulin equivalent, not a bolus recommendation. No correction or IOB subtraction is applied. Trio IOB is modeled active insulin above or below scheduled basal; COB is estimated unabsorbed carbohydrate. Future SMBs and delayed meal absorption are not modeled.")
                            .font(.footnote)
                    }
                    Section("Warnings") {
                        if snapshot.value?.ratioSource == "Scheduled profile fallback" { warning("Trio did not report a valid ratio. The scheduled profile fallback may not reflect an active override.") }
                        if !MealReviewSnapshot.fresh(glucoseDate, now: context.date) { warning("Glucose is missing, over 10 minutes old, or has an invalid timestamp.") }
                        if !MealReviewSnapshot.fresh(snapshot.value?.date, now: context.date) { warning("Trio calculation is missing, over 10 minutes old, or has an invalid timestamp.") }
                        if !MealReviewSnapshot.fresh(snapshot.value?.iobDate, now: context.date) { warning("IOB timestamp is missing or stale; do not assume no active insulin.") }
                        if snapshot.value?.iob == nil || snapshot.value?.cob == nil { warning("IOB or COB is unavailable. Missing values are not zero.") }
                        if let bg = glucose.value, bg < 70 { warning("Low glucose: prioritize your established hypoglycemia treatment plan before meal review.") }
                        if !trendAvailable { warning("Glucose trend is unavailable.") }
                        if falling { warning("Glucose is falling. Active insulin can continue lowering glucose.") }
                        if let iob = snapshot.value?.iob, iob > 0 { warning("Active insulin is present; additional insulin can stack with boluses and SMBs.") }
                        Text("Trio predictions and absorption estimates can be wrong. Review the glucose trace and recent delivery in Trio before using the existing bolus controls.").font(.footnote)
                    }
                }
            }
            .navigationTitle("Smart Meal Advisor")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .onAppear { carbText = initialCarbs > 0 ? String(format: "%.1f", initialCarbs) : "" }
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack { Text(label); Spacer(); Text(value).foregroundStyle(.secondary).multilineTextAlignment(.trailing) }
    }

    private func warning(_ text: String) -> some View { Label(text, systemImage: "exclamationmark.triangle").foregroundStyle(.orange) }
    private func age(_ date: Date?, now: Date) -> String {
        guard let date else { return "Unavailable" }
        let seconds = now.timeIntervalSince(date)
        guard seconds >= -60 else { return "Future timestamp" }
        return String(format: "%.0f min", max(0, seconds) / 60)
    }
}
