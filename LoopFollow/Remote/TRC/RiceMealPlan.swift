// LoopFollow
// RiceMealPlan.swift

import Foundation

/// Preview only. This type has no transport, credentials, timers, or delivery side effects.
enum SmartMealPreset: String, CaseIterable, Identifiable {
    case fruit = "Full Meal Bolus", rice = "Rice · 75/25 split", pizza = "Pizza", custom = "Custom"
    var id: String { rawValue }
    var carbsNowPercent: Double { switch self { case .rice: 75; case .pizza: 70; default: 100 } }
    var insulinPercent: Double { switch self { case .rice: 75; case .pizza: 70; default: 100 } }
    var delayMinutes: Double { switch self { case .rice: 30; case .pizza: 60; default: 0 } }

    /// A reduced linked percentage announces the same fraction of carbs now.
    /// Preserve an explicitly chosen positive delay; otherwise use the preset delay.
    func linkedCarbDelay(percent: Double, selectedDelay: Double) -> Double {
        guard percent < 100 else { return 0 }
        return selectedDelay == 0 ? (self == .pizza ? 60 : 30) : selectedDelay
    }
}

struct RiceMealPlan: Equatable {
    let immediateCarbs: Int
    let delayedCarbs: Int
    let delayedDate: Date
    let fullRecommendation: Double
    let upfrontPercent: Double
    let upfrontInsulin: Double
    let suggestedUpfrontInsulin: Double
    let usesManualBolus: Bool
    let delayedInsulin: Double = 0
    let delayMinutes: Double
    let carbsNowPercent: Double
    let preset: SmartMealPreset?

    static let sendingBlocker = "Split carbs need the matching Trio update and its latest connection. Nothing has been sent or scheduled."

    init?(carbs: Double, fullRecommendation: Double, upfrontPercent: Double, confirmedAt: Date, carbsNowPercent: Double = 75, delayMinutes: Double = 30, upfrontInsulinOverride: Double? = nil, preset: SmartMealPreset? = nil) {
        // The existing remote protocol accepts whole grams. Never truncate two fractions independently.
        guard carbs.isFinite, carbs >= 1, carbs <= 1000, carbs.rounded() == carbs,
              fullRecommendation.isFinite, fullRecommendation >= 0, fullRecommendation <= 100,
              upfrontPercent.isFinite, (0 ... 100).contains(upfrontPercent),
              carbsNowPercent.isFinite, (0 ... 100).contains(carbsNowPercent),
              delayMinutes.isFinite, (0 ... 1440).contains(delayMinutes),
              carbsNowPercent == 100 || delayMinutes > 0,
              confirmedAt.timeIntervalSince1970.isFinite else { return nil }
        let total = Int(carbs)
        delayedCarbs = Int((carbs * (100 - carbsNowPercent) / 100).rounded())
        immediateCarbs = total - delayedCarbs
        delayedDate = confirmedAt.addingTimeInterval(delayMinutes * 60)
        self.delayMinutes = delayMinutes
        self.carbsNowPercent = carbsNowPercent
        self.preset = preset
        self.fullRecommendation = fullRecommendation
        self.upfrontPercent = upfrontPercent
        // DASH step: round down once, after applying the independently selected percentage.
        guard let full = Decimal(string: String(fullRecommendation)),
              let percent = Decimal(string: String(upfrontPercent)) else { return nil }
        let raw = full * percent / 100
        var steps = raw * 20
        var rounded = Decimal()
        NSDecimalRound(&rounded, &steps, 0, .down)
        suggestedUpfrontInsulin = NSDecimalNumber(decimal: rounded / 20).doubleValue
        if let override = upfrontInsulinOverride {
            guard override.isFinite, override >= 0, override <= 30,
                  let amount = Decimal(string: String(override)),
                  SmartMealWire.roundDown(amount) == amount else { return nil }
            upfrontInsulin = override
            usesManualBolus = true
        } else {
            upfrontInsulin = suggestedUpfrontInsulin
            usesManualBolus = false
        }
    }
}

/// A local draft only. It carries the exact calculation context to the standard Meal screen.
struct SmartMealDraft {
    let plan: RiceMealPlan
    let protein: Double
    let fat: Double
    let settings: MealReviewSettings
    let snapshot: MealReviewSnapshot
    let source: String
    let createdAt: Date
    let transactionID = UUID()

    static func prefillReasons(settings: MealReviewSettings?, snapshot: MealReviewSnapshot?, source: String, samples: [MealReviewCalculation.GlucoseSample], newestTreatment: Date?, now: Date) -> [String] {
        var reasons = MealReviewFullCalculation.reasons(settings: settings, snapshot: snapshot, source: source, now: now)
            + MealReviewCalculation.reasons(snapshot: snapshot, samples: samples, newestTreatment: newestTreatment, now: now, allowReviewedLowForecast: true)
        if let settings {
            if settings.isHistorical { reasons.append("Saved Trio settings are historical. Check the current percentage and limits in calculator settings before dose prefill.") }
            else if now.timeIntervalSince(settings.checkedAt) < 0 || now.timeIntervalSince(settings.checkedAt) > 86400 {
                reasons.append("Current Trio settings have not been checked within 24 hours. Recheck calculator settings before dose prefill.")
            }
        }
        if let identifier = settings?.receiverConfigurationID {
            guard let status = snapshot?.smartMeal,
                  status.isCurrent(now: now, calculationDate: snapshot?.date, bundleID: status.bundleIdentifier),
                  status.configuration.identifier == identifier
            else {
                return reasons + ["Waiting for current Trio calculator settings and smart-meal capability."]
            }
        }
        if snapshot?.isfSource != "Trio structured effective ISF" {
            reasons.append("Dose prefill requires Trio's structured effective ISF; rounded reason text is for comparison only.")
        }
        return reasons
    }

    /// Build directly from the automatic full-meal calculation, never a typed
    /// copy of Trio's answer. Confirmation/authentication remain in MealView.
    static func make(plan: RiceMealPlan, protein: Double, fat: Double, settings: MealReviewSettings?, snapshot: MealReviewSnapshot?, source: String, samples: [MealReviewCalculation.GlucoseSample], newestTreatment: Date?, now: Date) -> Self? {
        guard prefillReasons(settings: settings, snapshot: snapshot, source: source, samples: samples, newestTreatment: newestTreatment, now: now).isEmpty,
              let settings, let snapshot,
              plan.upfrontInsulin <= settings.maxBolus,
              plan.upfrontInsulin + (snapshot.iob ?? 0) <= settings.maxIOB,
              [protein, fat].allSatisfy({ $0.isFinite && $0 >= 0 && $0 <= 1000 && $0.rounded() == $0 }),
              let result = MealReviewFullCalculation.review(newCarbs: Double(plan.immediateCarbs + plan.delayedCarbs), settings: settings, snapshot: snapshot, source: source, samples: samples, newestTreatment: newestTreatment, now: now),
              result.rounded == plan.fullRecommendation else { return nil }
        let draft = Self(plan: plan, protein: protein, fat: fat, settings: settings, snapshot: snapshot, source: source, createdAt: now)
        if settings.receiverConfigurationID != nil {
            guard let status = snapshot.smartMeal,
                  SmartMealDelivery.request(draft: draft, bolus: plan.upfrontInsulin, protein: protein, fat: fat,
                                            snapshot: snapshot, settings: settings, bundleID: status.bundleIdentifier, now: now) != nil else { return nil }
        }
        return draft.isCurrent(now: now, settings: settings, snapshot: snapshot, source: source) ? draft : nil
    }

    func isCurrent(now: Date, settings current: MealReviewSettings?, snapshot live: MealReviewSnapshot?, source currentSource: String) -> Bool {
        guard !settings.isHistorical, current == settings, live == snapshot, source == currentSource,
              now.timeIntervalSince(createdAt) >= 0, now.timeIntervalSince(createdAt) <= 120,
              now.timeIntervalSince(settings.checkedAt) >= 0,
              now.timeIntervalSince(settings.checkedAt) <= 86400 else { return false }
        return MealReviewFullCalculation.reasons(settings: current, snapshot: live, source: currentSource, now: now).isEmpty
    }
}

/// Write-before-send journal. Transport success is not evidence of Trio processing.
/// An unresolved attempt blocks another advisor send until the caregiver checks Trio.
final class SmartMealSendJournal {
    static let shared = SmartMealSendJournal(directory: FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("SmartMealPending", isDirectory: true))
    private let directory: URL
    private let lock = NSLock()
    init(directory: URL) { self.directory = directory }
    private func file(source: String) -> URL { directory.appendingPathComponent(MealReviewSettings.fingerprint(source) + ".pending") }
    func hasPending(source: String) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return FileManager.default.fileExists(atPath: file(source: source).path)
    }

    func claim(source: String) -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard !FileManager.default.fileExists(atPath: file(source: source).path) else { return false }
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            var location = directory
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            try location.setResourceValues(values)
            try Data(UUID().uuidString.utf8).write(to: file(source: source), options: .atomic)
            return true
        } catch { return false } // Failure to persist prevents sending.
    }

    func claim(request: SmartMealRequest, source: String) -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard !FileManager.default.fileExists(atPath: file(source: source).path) else { return false }
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try JSONEncoder().encode(request).write(to: file(source: source), options: .atomic)
            return true
        } catch { return false }
    }

    func pendingRequest(source: String) -> SmartMealRequest? {
        lock.lock(); defer { lock.unlock() }
        return try? JSONDecoder().decode(SmartMealRequest.self, from: Data(contentsOf: file(source: source)))
    }

    func lastReceipt(source: String) -> SmartMealReceipt? {
        lock.lock(); defer { lock.unlock() }
        return try? JSONDecoder().decode(SmartMealReceipt.self, from: Data(contentsOf: file(source: source).appendingPathExtension("receipt.json")))
    }

    @discardableResult
    func receive(_ status: SmartMealReceiverStatus, source: String, bundleID: String, now: Date) -> SmartMealReceipt? {
        lock.lock(); defer { lock.unlock() }
        guard status.protocolVersion == 1, status.configuration.valid, status.bundleIdentifier == bundleID,
              (0 ... 600).contains(now.timeIntervalSince1970 - status.generatedAt),
              let data = try? Data(contentsOf: file(source: source)),
              let request = try? JSONDecoder().decode(SmartMealRequest.self, from: data),
              let receipt = status.receipts.first(where: { $0.request == request }) else { return nil }
        do {
            try JSONEncoder().encode(receipt).write(to: file(source: source).appendingPathExtension("receipt.json"), options: .atomic)
            if [.accepted, .rejected, .reconciled].contains(receipt.phase) {
                try FileManager.default.removeItem(at: file(source: source))
            }
            return receipt
        } catch { return nil }
    }

    func reconcile(source: String, now: Date = Date()) -> Bool {
        lock.lock(); defer { lock.unlock() }
        // A caregiver can clear an expired, checked sender attempt, but never cancel
        // an in-flight command. Trio independently blocks any uncertain receiver transaction.
        if let data = try? Data(contentsOf: file(source: source)),
           let request = try? JSONDecoder().decode(SmartMealRequest.self, from: data),
           now.timeIntervalSince1970 - request.confirmedAt <= 120 { return false }
        do { try FileManager.default.removeItem(at: file(source: source)); return true }
        catch { return false }
    }
}
