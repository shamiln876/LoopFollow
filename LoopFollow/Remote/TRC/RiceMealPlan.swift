import Foundation

/// Preview only. This type has no transport, credentials, timers, or delivery side effects.
enum SmartMealPreset: String, CaseIterable, Identifiable {
    case rice = "Rice", pizza = "Pizza", fruit = "Fruit & Dessert", custom = "Custom"
    var id: String { rawValue }
    var carbsNowPercent: Double { switch self { case .rice: 75; case .pizza: 70; default: 100 } }
    var insulinPercent: Double { switch self { case .rice: 75; case .pizza: 70; default: 100 } }
    var delayMinutes: Double { switch self { case .rice: 30; case .pizza: 60; default: 0 } }
}

struct RiceMealPlan: Equatable {
    let immediateCarbs: Int
    let delayedCarbs: Int
    let delayedDate: Date
    let fullRecommendation: Double
    let upfrontPercent: Double
    let upfrontInsulin: Double
    let delayedInsulin: Double = 0

    static let sendingBlocker = "Split-meal sending is unavailable: Trio does not support atomic two-entry acceptance or durable receiver replay protection. Nothing has been sent or scheduled."

    init?(carbs: Double, fullRecommendation: Double, upfrontPercent: Double, confirmedAt: Date, carbsNowPercent: Double = 75, delayMinutes: Double = 30) {
        // The existing remote protocol accepts whole grams. Never truncate two fractions independently.
        guard carbs.isFinite, carbs >= 1, carbs <= 1000, carbs.rounded() == carbs,
              fullRecommendation.isFinite, fullRecommendation >= 0, fullRecommendation <= 100,
              upfrontPercent.isFinite, (0 ... 100).contains(upfrontPercent),
              carbsNowPercent.isFinite, (0 ... 100).contains(carbsNowPercent),
              delayMinutes.isFinite, (0 ... 1440).contains(delayMinutes),
              (carbsNowPercent == 100 || delayMinutes > 0),
              confirmedAt.timeIntervalSince1970.isFinite else { return nil }
        let total = Int(carbs)
        delayedCarbs = Int((carbs * (100 - carbsNowPercent) / 100).rounded())
        immediateCarbs = total - delayedCarbs
        delayedDate = confirmedAt.addingTimeInterval(delayMinutes * 60)
        self.fullRecommendation = fullRecommendation
        self.upfrontPercent = upfrontPercent
        // DASH step: round down once, after applying the independently selected percentage.
        guard let full = Decimal(string: String(fullRecommendation)),
              let percent = Decimal(string: String(upfrontPercent)) else { return nil }
        let raw = full * percent / 100
        var steps = raw * 20
        var rounded = Decimal()
        NSDecimalRound(&rounded, &steps, 0, .down)
        upfrontInsulin = NSDecimalNumber(decimal: rounded / 20).doubleValue
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

    static func prefillReasons(settings: MealReviewSettings?, snapshot: MealReviewSnapshot?, source: String, samples: [MealReviewCalculation.GlucoseSample], newestTreatment: Date?, now: Date) -> [String] {
        var reasons = MealReviewFullCalculation.reasons(settings: settings, snapshot: snapshot, source: source, now: now)
            + MealReviewCalculation.reasons(snapshot: snapshot, samples: samples, newestTreatment: newestTreatment, now: now)
        if let settings {
            if settings.isHistorical { reasons.append("Saved Trio settings are historical. Check the current percentage and limits in calculator settings before dose prefill.") }
            else if now.timeIntervalSince(settings.checkedAt) < 0 || now.timeIntervalSince(settings.checkedAt) > 86400 {
                reasons.append("Current Trio settings have not been checked within 24 hours. Recheck calculator settings before dose prefill.")
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
              [protein, fat].allSatisfy({ $0.isFinite && $0 >= 0 && $0 <= 1000 && $0.rounded() == $0 }),
              let result = MealReviewFullCalculation.review(newCarbs: Double(plan.immediateCarbs + plan.delayedCarbs), settings: settings, snapshot: snapshot, source: source, samples: samples, newestTreatment: newestTreatment, now: now),
              result.rounded == plan.fullRecommendation else { return nil }
        let draft = Self(plan: plan, protein: protein, fat: fat, settings: settings, snapshot: snapshot, source: source, createdAt: now)
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
    func reconcile(source: String) -> Bool {
        lock.lock(); defer { lock.unlock() }
        do { try FileManager.default.removeItem(at: file(source: source)); return true }
        catch { return false }
    }
}
