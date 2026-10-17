// LoopFollow
// MealDashboardView.swift

import Charts
import Combine
import HealthKit
import SwiftUI

/// Observes meal data independently of Home's chart pan/zoom updates.
struct MealDashboardHomeCard: View {
    @ObservedObject private var snapshot = Observable.shared.mealReview
    @ObservedObject private var history = Observable.shared.mealReviewGlucose
    @ObservedObject private var newestTreatment = Observable.shared.mealReviewNewestTreatment
    @ObservedObject private var settings = Storage.shared.mealReviewSettings
    @ObservedObject private var source = Storage.shared.url
    @State private var now = Date()
    @State private var presented = false
    @State private var mealPresented = false
    @State private var advisorDraft: SmartMealDraft?

    var body: some View {
        let status = MealDashboardStatus(snapshot: snapshot.value, samples: history.value, newestTreatment: newestTreatment.value, settings: settings.value, source: source.value, now: now)
        Button { advisorDraft = nil; presented = true } label: {
            MealDashboardHomeLabel(status: status, snapshot: snapshot.value, now: now)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("home-meal-dashboard")
        .sheet(isPresented: $presented, onDismiss: {
            if advisorDraft != nil { mealPresented = true }
        }) {
            MealReviewView(initialCarbs: 0, onUse: { advisorDraft = $0 })
        }
        .sheet(isPresented: $mealPresented) { MealView(initialAdvisorDraft: advisorDraft) }
        .onAppear { now = Date() }
        .onReceive(Timer.publish(every: 5, on: .main, in: .common).autoconnect()) { now = $0 }
    }
}

struct MealDashboardHomeLabel: View {
    let status: MealDashboardStatus
    let snapshot: MealReviewSnapshot?
    let now: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Label("Smart Meal Advisor", systemImage: "fork.knife").font(.headline)
                Spacer(minLength: 4)
                Image(systemName: "chevron.right").font(.caption.weight(.semibold))
            }
            Text("IOB \(MealDashboardFormat.number(snapshot?.iob, unit: "U", decimals: 2)) · COB \(MealDashboardFormat.number(snapshot?.cob, unit: "g"))")
                .font(.subheadline).foregroundStyle(.secondary)
            Label(status.inputsAvailable ? "Live inputs available · food & portions" : status.reasons.first ?? status.title,
                  systemImage: status.inputsAvailable ? "waveform.path" : "exclamationmark.triangle")
                .font(.caption).foregroundStyle(status.inputsAvailable ? Color.accentColor : .orange)
                .fixedSize(horizontal: false, vertical: true)
            if !MealReviewSnapshot.fresh(snapshot?.date, now: now) || !MealReviewSnapshot.fresh(snapshot?.iobDate, now: now) {
                Text("Values are last received · food guide works offline").font(.caption2).foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(UIColor.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14))
        .contentShape(RoundedRectangle(cornerRadius: 14))
        .accessibilityElement(children: .combine)
    }
}

/// Keeps meal choices visible while retaining the full existing dashboard details.
struct MealDashboardCompactOverview: View {
    let status: MealDashboardStatus
    let snapshot: MealReviewSnapshot?
    let sensorArrow: String?
    let now: Date
    var hasMeal = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(status.glucose.map { MealDashboardFormat.glucose($0.mgdl) } ?? "Glucose unavailable")
                .font(.title2.weight(.semibold)).monospacedDigit()
            Text("IOB \(MealDashboardFormat.number(snapshot?.iob, unit: "U", decimals: 2)) · COB \(MealDashboardFormat.number(snapshot?.cob, unit: "g"))")
                .font(.subheadline)
            Text("Glucose \(MealDashboardFormat.age(status.glucose?.date, now: now)) · IOB \(MealDashboardFormat.age(snapshot?.iobDate, now: now))")
                .font(.caption).foregroundStyle(.secondary)
            DisclosureGroup(status.title + " · details") {
                MealDashboardOverview(status: status, snapshot: snapshot, sensorArrow: sensorArrow, now: now, hasMeal: hasMeal)
            }
            .font(.subheadline)
        }
    }
}

struct MealDashboardOverview: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let status: MealDashboardStatus
    let snapshot: MealReviewSnapshot?
    let sensorArrow: String?
    let now: Date
    var hasMeal = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 6) {
                    glucoseHeading
                    Text(sensorArrow ?? "Arrow unavailable").font(.subheadline).foregroundStyle(.secondary)
                }
            } else {
                HStack(alignment: .firstTextBaseline) {
                    glucoseHeading
                    Spacer(minLength: 8)
                    Text(sensorArrow ?? "Arrow unavailable").font(.subheadline).foregroundStyle(.secondary)
                }
            }
            VStack(alignment: .leading, spacing: 5) {
                Label(status.title, systemImage: status.inputsAvailable ? "waveform.path" : "exclamationmark.triangle")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(status.inputsAvailable ? Color.accentColor : .orange)
                if let reason = status.reasons.first {
                    Text(reason).font(.footnote)
                    if status.reasons.count > 1 { Text("All \(status.reasons.count) checks are listed under Meal comparison.").font(.caption).foregroundStyle(.secondary) }
                } else { Text(hasMeal ? "Comparison updates from the latest received data." : "Enter meal carbs or choose foods below.").font(.footnote).foregroundStyle(.secondary) }
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: dynamicTypeSize.isAccessibilitySize ? 260 : 135), alignment: .leading)], alignment: .leading, spacing: 14) {
                metric("Remaining net IOB", MealDashboardFormat.number(snapshot?.iob, unit: "U", decimals: 2), date: snapshot?.iobDate)
                metric("Existing COB", MealDashboardFormat.number(snapshot?.cob, unit: "g"), date: snapshot?.date)
                metric("Insulin activity", MealDashboardFormat.number(snapshot?.activity, unit: "U/min", decimals: 4), date: snapshot?.iobDate)
                metric("Active carb ratio", MealDashboardFormat.number(snapshot?.carbRatio, unit: "g/U", decimals: 2), date: snapshot?.date)
                metric("Effective ISF", snapshot?.effectiveISF.map { MealDashboardFormat.glucose($0) + "/U" } ?? "Unavailable", date: snapshot?.date)
                metric("Trio target", snapshot?.targetMgdl.map(MealDashboardFormat.glucose) ?? "Unavailable", date: snapshot?.date)
            }
            Text("Trio · \(MealDashboardFormat.age(snapshot?.date, now: now))  |  IOB · \(MealDashboardFormat.age(snapshot?.iobDate, now: now))")
                .font(.caption).foregroundStyle(.secondary)
        }.padding(.vertical, 5)
    }

    private var glucoseHeading: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(status.glucose.map { MealDashboardFormat.glucose($0.mgdl) } ?? "Glucose unavailable")
                .font(.title.weight(.semibold)).monospacedDigit()
                .fixedSize(horizontal: false, vertical: true)
            Text("Glucose · \(MealDashboardFormat.age(status.glucose?.date, now: now))")
                .font(.caption).foregroundStyle(MealReviewSnapshot.fresh(status.glucose?.date, now: now) ? Color.secondary : .orange)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func metric(_ title: String, _ value: String, date: Date?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.headline).monospacedDigit().fixedSize(horizontal: false, vertical: true)
            if value != "Unavailable", !MealReviewSnapshot.fresh(date, now: now) {
                Text(date == nil ? "Age unavailable" : "Last received · stale").font(.caption2).foregroundStyle(.orange)
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct MealDashboardGlucoseChart: View {
    let samples: [MealReviewCalculation.GlucoseSample]
    let now: Date

    var body: some View {
        let recent = samples.filter { $0.date <= now && $0.date > now.addingTimeInterval(-2 * 60 * 60) && $0.mgdl.isFinite && $0.mgdl > 0 }.sorted { $0.date < $1.date }
        if recent.isEmpty {
            Text("Recent glucose readings are unavailable.").foregroundStyle(.secondary)
        } else {
            Chart {
                ForEach(Array(recent.enumerated()), id: \.offset) { entry in
                    LineMark(x: .value("Time", entry.element.date), y: .value("Glucose", UnitSettingsStore.shared.convertMgdlToDisplay(entry.element.mgdl)))
                    PointMark(x: .value("Time", entry.element.date), y: .value("Glucose", UnitSettingsStore.shared.convertMgdlToDisplay(entry.element.mgdl)))
                        .symbolSize(12)
                }
            }
            .chartYAxisLabel(UnitSettingsStore.shared.glucoseUnit.rawValue)
            .chartYScale(domain: .automatic(includesZero: false))
            .frame(height: 160)
            .accessibilityLabel("Recent received glucose readings")
            Text("Received CGM readings · last 2 hours. Latest: \(MealDashboardFormat.age(recent.last?.date, now: now)).")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}

enum MealDashboardFormat {
    static func number(_ value: Double?, unit: String, decimals: Int = 1) -> String {
        guard let value, value.isFinite else { return "Unavailable" }
        return String(format: "%.*f %@", decimals, value, unit)
    }

    static func glucose(_ mgdl: Double) -> String {
        Localizer.formatQuantity(HKQuantity(unit: .milligramsPerDeciliter, doubleValue: mgdl)) + " " + UnitSettingsStore.shared.glucoseUnit.rawValue
    }

    static func age(_ date: Date?, now: Date) -> String {
        guard let date else { return "unavailable" }
        let seconds = now.timeIntervalSince(date)
        guard seconds >= -60 else { return "clock mismatch" }
        let age = "\(Int(max(0, seconds) / 60)) min ago"
        return MealReviewSnapshot.fresh(date, now: now) ? age : age + " · stale"
    }
}
