import Foundation

/// Current configuration comes from the paired Trio's live upload, not defaults/history.
enum SmartMealDelivery {
    static func liveSettings(snapshot: MealReviewSnapshot?, source: String, bundleID: String, now: Date) -> MealReviewSettings? {
        guard !source.isEmpty, !bundleID.isEmpty, let snapshot, let status = snapshot.smartMeal,
              status.isCurrent(now: now, calculationDate: snapshot.date, bundleID: bundleID), snapshot.trioVersion == "1.0.2" else { return nil }
        let c = status.configuration
        var result = MealReviewSettings(percentage: NSDecimalNumber(decimal: c.percentage).doubleValue,
            maxIOB: NSDecimalNumber(decimal: c.maxIOB).doubleValue, maxCOB: NSDecimalNumber(decimal: c.maxCOB).doubleValue,
            maxBolus: NSDecimalNumber(decimal: c.maxBolus).doubleValue, sourceFingerprint: MealReviewSettings.fingerprint(source),
            trioVersion: "1.0.2", checkedAt: Date(timeIntervalSince1970: status.generatedAt))
        result.receiverConfigurationID = c.identifier
        return result.numbersValid ? result : nil
    }

    static func available(snapshot: MealReviewSnapshot?, settings: MealReviewSettings?, bundleID: String, now: Date) -> Bool {
        guard let snapshot, let status = snapshot.smartMeal,
              status.isCurrent(now: now, calculationDate: snapshot.date, bundleID: bundleID),
              settings?.receiverConfigurationID == status.configuration.identifier, settings?.isHistorical == false else { return false }
        return true
    }

    static func request(draft: SmartMealDraft, bolus: Double, protein: Double, fat: Double, snapshot: MealReviewSnapshot?, settings: MealReviewSettings?, bundleID: String, now: Date) -> SmartMealRequest? {
        guard draft.isCurrent(now: now, settings: settings, snapshot: snapshot, source: draft.source),
              available(snapshot: snapshot, settings: settings, bundleID: bundleID, now: now),
              let status = snapshot?.smartMeal,
              [bolus, protein, fat].allSatisfy(\.isFinite),
              bolus <= draft.settings.maxBolus,
              bolus + (snapshot?.iob ?? 0) <= draft.settings.maxIOB,
              [protein, fat].allSatisfy({ $0 >= 0 && $0 <= 1000 && $0.rounded() == $0 }),
              let full = Decimal(string: String(draft.plan.fullRecommendation)),
              let percent = Decimal(string: String(draft.plan.upfrontPercent)),
              let amount = Decimal(string: String(bolus)) else { return nil }
        let request = SmartMealRequest(id: draft.transactionID, confirmedAt: now.timeIntervalSince1970,
            calculationAt: status.calculationAt, configurationID: status.configuration.identifier,
            immediateCarbs: draft.plan.immediateCarbs, delayedCarbs: draft.plan.delayedCarbs,
            delaySeconds: draft.plan.delayedCarbs > 0 ? Int((draft.plan.delayMinutes * 60).rounded()) : 0,
            fullRecommendation: full, upfrontPercent: percent, bolusAmount: amount,
            includeFatProtein: protein > 0 || fat > 0, protein: Int(protein), fat: Int(fat))
        return (try? request.validate(configuration: status.configuration, now: now)) != nil ? request : nil
    }
}
