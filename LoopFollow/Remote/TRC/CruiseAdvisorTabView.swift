// LoopFollow
// CruiseAdvisorTabView.swift
//
// Food-first caregiver support. No bolus or pump action occurs in this view.
// The actual command remains in MealView with authentication and confirmation.

import SwiftUI
import HealthKit

struct CruiseAdvisorTabView: View {
    @State private var carbText = ""
    @State private var editedInsulin = ""
    @State private var selectedMeal: CarnivalMeal?
    @State private var showFoodGuide = false
    @State private var guideTab = 0
    @State private var showDetails = false

    @ObservedObject private var snapshot = Observable.shared.mealReview
    @ObservedObject private var samples = Observable.shared.mealReviewGlucose
    @ObservedObject private var newestTreatment = Observable.shared.mealReviewNewestTreatment
    @ObservedObject private var savedSettings = Storage.shared.mealReviewSettings
    @ObservedObject private var source = Storage.shared.url
    @ObservedObject private var maximumBolus = Storage.shared.maxBolus
    @FocusState private var editingField: Bool

    private var carbs: Double? {
        guard let amount = Double(carbText.replacingOccurrences(of: ",", with: ".")),
              amount.isFinite, amount > 0, amount <= 1000, amount.rounded() == amount
        else { return nil }
        return amount
    }

    private var coverage: Double? {
        guard let carbs, let ratio = snapshot.value?.carbRatio,
              ratio.isFinite, ratio > 0,
              MealReviewSnapshot.fresh(snapshot.value?.date, now: Date()),
              snapshot.value?.ratioSource == "Trio reported"
        else { return nil }
        return carbs / ratio
    }

    /// A candidate is shown only with a current Trio calculation, effective ISF,
    /// consistent IOB and settings. Food category never silently changes insulin.
    private var calculatedBolus: Double? {
        let now = Date()
        guard let carbs,
              SmartMealDraft.prefillReasons(settings: savedSettings.value,
                                            snapshot: snapshot.value,
                                            source: source.value,
                                            samples: samples.value,
                                            newestTreatment: newestTreatment.value,
                                            now: now).isEmpty,
              let result = MealReviewFullCalculation.review(
                newCarbs: carbs, settings: savedSettings.value,
                snapshot: snapshot.value, source: source.value,
                samples: samples.value, newestTreatment: newestTreatment.value, now: now)
        else { return nil }
        return result.rounded
    }

    private var chosenBolus: Double? {
        if !editedInsulin.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            guard let entered = Double(editedInsulin.replacingOccurrences(of: ",", with: ".")),
                  entered.isFinite, entered >= 0 else { return nil }
            return entered
        }
        return calculatedBolus
    }

    private var canPrefill: Bool {
        guard let dose = chosenBolus, let carbs,
              dose.isFinite, dose >= 0,
              dose <= maximumBolus.value.doubleValue(for: .internationalUnit()),
              abs(dose * 20 - (dose * 20).rounded()) < 0.00001,
              carbs <= Storage.shared.maxCarbs.value.doubleValue(for: .gram())
        else { return false }
        return true
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 8) {
                        Button("Portions") { editingField = false; guideTab = 0; showFoodGuide = true }
                        Button("Search") { editingField = false; guideTab = 1; showFoodGuide = true }
                        Button("Photo") { editingField = false; guideTab = 2; showFoodGuide = true }
                    }
                    .buttonStyle(.bordered)
                    if let selectedMeal {
                        Text("Selected foods: \(selectedMeal.items.count)")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    HStack {
                        Text("Total carbs").font(.headline)
                        Spacer()
                        TextField("g", text: $carbText)
                            .keyboardType(.decimalPad)
                            .focused($editingField)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 96)
                            .accessibilityIdentifier("cruise-total-carbs")
                        Text("g").foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Meal")
                }

                Section("Insulin estimate") {
                    if let coverage {
                        HStack {
                            Text("Carbs ÷ active CR")
                            Spacer()
                            Text(String(format: "%.2f U", coverage))
                                .monospacedDigit()
                        }
                    }
                    HStack {
                        Text("Trio-adjusted estimate")
                        Spacer()
                        if let calculatedBolus {
                            Text(String(format: "%.2f U", calculatedBolus))
                                .font(.title2.weight(.semibold))
                                .monospacedDigit()
                        } else {
                            Text("Unavailable").foregroundStyle(.secondary)
                        }
                    }
                    HStack {
                        Text("Upfront insulin").font(.headline)
                        Spacer()
                        TextField(calculatedBolus.map { String(format: "%.2f", $0) } ?? "Enter U",
                                  text: $editedInsulin)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .focused($editingField)
                            .frame(width: 115)
                            .accessibilityIdentifier("cruise-upfront-insulin")
                        Text("U").foregroundStyle(.secondary)
                    }
                    if let proposed = chosenBolus,
                       let max = savedSettings.value?.maxBolus, proposed >= max {
                        Text("The Trio estimate may be capped at the current maximum bolus. Carb coverage is not the same as insulin actually delivered.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    if calculatedBolus == nil {
                        Text("Live calculation unavailable. You can enter an amount manually and review it in Meal. No automatic dose was guessed.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }

                Section {
                    if canPrefill, let carbs, let dose = chosenBolus {
                        NavigationLink {
                            MealView(initialCarbs: carbs, initialBolus: dose)
                        } label: {
                            Label("Review \(String(format: "%.2f", dose)) U in Meal", systemImage: "arrow.right.circle.fill")
                                .font(.headline)
                        }
                        .accessibilityIdentifier("cruise-review-dose")
                    } else if let carbs {
                        NavigationLink {
                            MealView(initialCarbs: carbs)
                        } label: {
                            Label("Enter insulin in Meal", systemImage: "arrow.right.circle")
                        }
                        Text("Check the carb entry, insulin amount or local pump limits.")
                            .font(.caption).foregroundStyle(.secondary)
                    } else {
                        Text("Select food or enter meal carbs to begin.")
                            .foregroundStyle(.secondary)
                    }
                } footer: {
                    Text("This screen never sends insulin. Meal requires your confirmation. Pump delivery must be verified separately.")
                }

                Section {
                    DisclosureGroup("How this is calculated", isExpanded: $showDetails) {
                        Text("The current carb ratio estimates carb coverage. A separate Trio-style calculation uses glucose, trend, effective ISF, COB, IOB, bolus percentage and pump limits. It cannot reliably forecast the extra insulin needed for delayed absorption. Food selection supplies a carb estimate, not an unvalidated insulin multiplier.")
                            .font(.footnote)
                        Text("Later carbs are not automatically a second bolus. SMB/UAM delivery is not guaranteed. Avoid duplicate carb announcements.")
                            .font(.footnote)
                    }
                }
            }
            .navigationTitle("Cruise Meal Advisor")
            .navigationBarTitleDisplayMode(.inline)
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: carbText) { _, newValue in
                if let selectedMeal,
                   let total = selectedMeal.carbsForReview,
                   Double(newValue) != total.rounded() {
                    self.selectedMeal = nil
                }
                editedInsulin = ""
            }
            .sheet(isPresented: $showFoodGuide) {
                CarnivalFoodGuideView(initialMeal: selectedMeal, initialTab: guideTab) { meal in
                    selectedMeal = meal
                    if let total = meal.carbsForReview { carbText = String(Int(total.rounded())) }
                    editedInsulin = ""
                    showFoodGuide = false
                }
            }
        }
    }
}
