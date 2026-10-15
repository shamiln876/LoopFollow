// LoopFollow
// MealReviewSettingsView.swift

import SwiftUI

struct MealReviewSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var saved: StorageValue<MealReviewSettings?>
    @ObservedObject private var source: StorageValue<String>
    @ObservedObject private var snapshot = Observable.shared.mealReview
    @State private var percentage = ""
    @State private var maxIOB = ""
    @State private var maxCOB = ""
    @State private var maxBolus = ""
    @State private var checked = false
    @State private var historical = false

    init(saved: StorageValue<MealReviewSettings?> = Storage.shared.mealReviewSettings, source: StorageValue<String> = Storage.shared.url) {
        _saved = ObservedObject(wrappedValue: saved)
        _source = ObservedObject(wrappedValue: source)
    }

    private func number(_ text: String) -> Double? { Double(text.replacingOccurrences(of: ",", with: ".")) }
    private var proposed: MealReviewSettings? {
        guard historical || checked, !source.value.isEmpty, snapshot.value?.trioVersion == "1.0.2",
              let percentage = number(percentage), let iob = number(maxIOB), let cob = number(maxCOB), let bolus = number(maxBolus) else { return nil }
        let settings = MealReviewSettings(percentage: percentage, maxIOB: iob, maxCOB: cob, maxBolus: bolus,
                                          sourceFingerprint: MealReviewSettings.fingerprint(source.value), trioVersion: "1.0.2", checkedAt: Date(),
                                          historicalReference: historical ? (saved.value?.historicalReference ?? "Historical values entered by user; not verified current in Trio.") : nil)
        return settings.numbersValid ? settings : nil
    }

    var body: some View {
        NavigationView {
            Form {
                Section("Copy values; do not change Trio") {
                    Text("Copy values from Trio or use historical values for testing. These entries are only used for comparison in LoopFollow and cannot change his settings or send insulin.")
                    numberRow("Recommended Bolus Percentage (%)", $percentage)
                    numberRow("Trio Max IOB (U)", $maxIOB)
                    numberRow("Trio Max COB (g)", $maxCOB)
                    numberRow("Trio Maximum Bolus (U)", $maxBolus)
                    Toggle("Use historical values for comparison only", isOn: $historical)
                    if historical {
                        Text("These values are not confirmed current. The comparison remains for testing only.").foregroundStyle(.orange)
                    } else {
                        Toggle("I checked these current values in Trio, using Omnipod DASH", isOn: $checked)
                    }
                }
                Section("Where to find them in Trio") {
                    Text("Percentage: Settings → Features → Bolus Calculator. Limits: Settings → Therapy → Units and Limits.")
                    Text("LoopFollow's own bolus limit is separate. Do not copy it as Trio's limit unless you have checked that they match.")
                    if snapshot.value?.trioVersion != "1.0.2" { Text("Waiting for the supported Trio version's live upload.").foregroundStyle(.orange) }
                }
                Section {
                    Button("Save comparison values") {
                        guard let proposed else { return }
                        saved.value = proposed
                        dismiss()
                    }
                    .disabled(proposed == nil)
                    if saved.value != nil {
                        Button("Clear saved comparison values", role: .destructive) { saved.value = nil; dismiss() }
                    }
                    Text("Recheck these entries whenever the Trio settings, app version or pump change. Reduced and super bolus options are not included.").font(.footnote)
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("Trio comparison settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
        .onAppear {
            guard let s = saved.value, s.matches(source: source.value, version: snapshot.value?.trioVersion, now: Date()) else { return }
            percentage = String(s.percentage)
            maxIOB = String(s.maxIOB)
            maxCOB = String(s.maxCOB)
            maxBolus = String(s.maxBolus)
            historical = s.isHistorical
        }
        .onChange(of: percentage) { _, _ in checked = false }
        .onChange(of: maxIOB) { _, _ in checked = false }
        .onChange(of: maxCOB) { _, _ in checked = false }
        .onChange(of: maxBolus) { _, _ in checked = false }
        .onChange(of: source.value) { _, _ in checked = false }
        .onChange(of: snapshot.value?.trioVersion) { _, _ in checked = false }
        .onChange(of: historical) { _, _ in checked = false }
    }

    private func numberRow(_ label: String, _ binding: Binding<String>) -> some View {
        HStack {
            Text(label)
            Spacer()
            TextField("Required", text: binding).keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(minWidth: 70)
                .accessibilityLabel(label)
        }
    }
}
