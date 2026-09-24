// LoopFollow
// BoardTimeDisplay.swift

import Foundation

enum BoardTimeDisplay {
    static func cobSamples(from statuses: [[String: AnyObject]]) -> [BoardTimeEstimate.CarbSample] {
        statuses.compactMap { status in
            guard let openaps = status["openaps"] as? [String: AnyObject],
                  let cycle = (openaps["suggested"] as? [String: AnyObject]) ??
                    (openaps["enacted"] as? [String: AnyObject]),
                  let grams = (cycle["COB"] as? Double) ?? (cycle["cob"] as? Double),
                  let timestamp = (cycle["deliverAt"] as? String) ??
                    (cycle["timestamp"] as? String),
                  let date = NightscoutUtils.parseDate(timestamp) else { return nil }
            return BoardTimeEstimate.CarbSample(grams: grams, date: date)
        }
    }
}

extension MainViewController {
    func refreshBoardTimeEstimates() {
        let now = Date()
        let lastLoopTime = max(
            Observable.shared.enactedOrSuggested.value ?? 0,
            Storage.shared.lastLoopTime.value,
            recentCOBSamples.map { $0.date.timeIntervalSince1970 }.max() ?? 0
        )
        // Don't show timers on a stale loop or for Loop's different insulin model.
        guard Storage.shared.device.value != "Loop",
              lastLoopTime > 0, now.timeIntervalSince1970 - lastLoopTime < 15 * 60 else {
            infoManager.updateEstimatedEnd(type: .iob, end: nil, updatedAt: now)
            infoManager.updateEstimatedEnd(type: .cob, end: nil, updatedAt: now)
            return
        }

        let doses = (bolusData + smbData).map {
            BoardTimeEstimate.Dose(units: $0.value, date: Date(timeIntervalSince1970: $0.date))
        }
        let modeledIOB = doses.reduce(0.0) { sum, dose in
            sum + dose.units * BoardTimeEstimate.fractionRemaining(
                minutes: now.timeIntervalSince(dose.date) / 60)
        }
        let reportedIOB = latestIOB?.value ?? 0
        let historyAgrees = abs(modeledIOB - reportedIOB) <= max(0.25, reportedIOB * 0.25)
        let insulinEnd = reportedIOB > BoardTimeEstimate.meaningfulInsulinUnits && historyAgrees
            ? BoardTimeEstimate.insulinEnd(doses: doses, now: now) : nil
        infoManager.updateEstimatedEnd(type: .iob, end: insulinEnd, updatedAt: now)

        let mostRecentCarb = carbData.filter { $0.date <= now.timeIntervalSince1970 }
            .map { Date(timeIntervalSince1970: $0.date) }.max()
        let samples = recentCOBSamples.sorted { $0.date < $1.date }
        // Require the observed COB to agree with the main display. A lagging
        // status response must not produce a countdown for a different meal.
        let currentMatches = samples.last.map { abs($0.grams - (latestCOB?.value ?? -100)) <= 2 } ?? false
        let carbEnd = (latestCOB?.value ?? 0) > 0 && mostRecentCarb != nil && currentMatches
            ? BoardTimeEstimate.carbEnd(samples: samples, mostRecentCarb: mostRecentCarb, now: now) : nil
        infoManager.updateEstimatedEnd(type: .cob, end: carbEnd, updatedAt: now)
    }
}
