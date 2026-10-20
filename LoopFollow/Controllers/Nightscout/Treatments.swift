// LoopFollow
// Treatments.swift

import Foundation

extension MainViewController {
    private struct TreatmentOccurrence: Hashable {
        let id: String
        let eventType: String?
        let date: Date?
    }

    /// Nightscout duplicates can have different MongoDB `_id` values. Trio FPU siblings share an `id` but have distinct
    /// times, so deduplicate by logical occurrence rather than `id`.
    static func deduplicatedTreatmentEntries(_ entries: [[String: AnyObject]]) -> [[String: AnyObject]] {
        var seenOccurrences = Set<TreatmentOccurrence>()
        return entries.filter { entry in
            guard let id = entry["id"] as? String, !id.isEmpty else { return true }
            let eventType = entry["eventType"] as? String
            let occurrence = TreatmentOccurrence(
                id: id,
                eventType: eventType,
                date: treatmentOccurrenceDate(entry, eventType: eventType)
            )
            return seenOccurrences.insert(occurrence).inserted
        }
    }

    private static func treatmentOccurrenceDate(_ entry: [String: AnyObject], eventType: String?) -> Date? {
        let rawDate: String?
        switch eventType {
        case "Pump Site Change", "Site Change", "Sensor Start", "Insulin Change":
            rawDate = entry["created_at"] as? String
        default:
            rawDate = (entry["timestamp"] as? String) ?? (entry["created_at"] as? String)
        }
        return rawDate.flatMap(NightscoutUtils.parseDate)
    }

    // NS Treatments Web Call
    // Downloads Basal, Bolus, Carbs, BG Check, Notes, Overrides
    func WebLoadNSTreatments() {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { self.WebLoadNSTreatments() }
            return
        }
        if !Storage.shared.downloadTreatments.value { return }
        guard !isFetchingNSTreatments else { return }
        isFetchingNSTreatments = true
        let requestedSource = Storage.shared.url.value

        let startTimeString = dateTimeUtils.getDateTimeString(addingDays: -1 * Storage.shared.downloadDays.value)
        let endTimeString = dateTimeUtils.getDateTimeString(addingHours: 6)
        let estimatedCount = max(Storage.shared.downloadDays.value * 100, 5000)
        let parameters: [String: String] = [
            "find[created_at][$gte]": startTimeString,
            "find[created_at][$lte]": endTimeString,
            "count": "\(estimatedCount)",
        ]
        NightscoutUtils.executeDynamicRequest(eventType: .treatments, parameters: parameters) { (result: Result<Any, Error>) in
            DispatchQueue.main.async {
                self.isFetchingNSTreatments = false
                guard Storage.shared.url.value == requestedSource else { return }
                switch result {
                case let .success(data):
                    if let entries = data as? [[String: AnyObject]] {
                        self.updateTreatments(entries: entries)
                    } else {
                        LogManager.shared.log(category: .nightscout, message: "WebLoadNSTreatments, Unexpected data structure")
                    }
                case let .failure(error):
                    LogManager.shared.log(category: .nightscout, message: "WebLoadNSTreatments, error \(error.localizedDescription)")
                }
            }
        }
    }

    // Process and split out treatments to individual tasks
    func updateTreatments(entries: [[String: AnyObject]]) {
        let uniqueEntries = Self.deduplicatedTreatmentEntries(entries)
        // Keep the review from using an IOB/COB snapshot predating a new treatment.
        Observable.shared.mealReviewNewestTreatment.value = uniqueEntries.compactMap { entry -> Date? in
            let insulin = (entry["insulin"] as? NSNumber)?.doubleValue ?? 0
            let carbs = (entry["carbs"] as? NSNumber)?.doubleValue ?? 0
            guard insulin > 0 || carbs > 0,
                  let time = (entry["timestamp"] as? String) ?? (entry["created_at"] as? String),
                  let date = NightscoutUtils.parseDate(time), date <= Date() else { return nil }
            return date
        }.max()

        var tempBasal: [[String: AnyObject]] = []
        var bolus: [[String: AnyObject]] = []
        var smb: [[String: AnyObject]] = []
        var carbs: [[String: AnyObject]] = []
        var temporaryOverride: [[String: AnyObject]] = []
        var temporaryTarget: [[String: AnyObject]] = []
        var note: [[String: AnyObject]] = []
        var bgCheck: [[String: AnyObject]] = []
        var suspendPump: [[String: AnyObject]] = []
        var resumePump: [[String: AnyObject]] = []
        var pumpSiteChange: [cageData] = []
        var cgmSensorStart: [sageData] = []
        var insulinCartridge: [iageData] = []

        for entry in uniqueEntries {
            guard let eventType = entry["eventType"] as? String else {
                continue
            }

            switch eventType {
            case "Temp Basal":
                tempBasal.append(entry)
            case "Correction Bolus", "Bolus", "External Insulin":
                if let automatic = entry["automatic"] as? Bool, automatic {
                    smb.append(entry)
                } else {
                    bolus.append(entry)
                }
            case "SMB":
                smb.append(entry)
            case "Meal Bolus":
                carbs.append(entry)
                bolus.append(entry)
            case "Carb Correction":
                carbs.append(entry)
            case "Temporary Override", "Exercise":
                temporaryOverride.append(entry)
            case "Temporary Target":
                temporaryTarget.append(entry)
            case "Note":
                note.append(entry)
            case "BG Check":
                bgCheck.append(entry)
            case "Suspend Pump":
                suspendPump.append(entry)
            case "Resume Pump":
                resumePump.append(entry)
            case "Pump Site Change", "Site Change":
                if let createdAt = entry["created_at"] as? String {
                    let newEntry = cageData(created_at: createdAt)
                    pumpSiteChange.append(newEntry)
                }
            case "Sensor Start":
                if let createdAt = entry["created_at"] as? String {
                    let newEntry = sageData(created_at: createdAt)
                    cgmSensorStart.append(newEntry)
                }
            case "Insulin Change":
                if let createdAt = entry["created_at"] as? String {
                    let newEntry = iageData(created_at: createdAt)
                    insulinCartridge.append(newEntry)
                }
            default:
                print("No Match: \(String(describing: entry))")
            }
        }

        if tempBasal.count > 0 {
            processNSBasals(entries: tempBasal)
        } else {
            if basalData.count > 0 {
                clearOldTempBasal()
            }
        }
        if bolus.count > 0 {
            processNSBolus(entries: bolus)
        } else {
            if bolusData.count > 0 {
                clearOldBolus()
            }
        }
        if smb.count > 0 {
            processNSSmb(entries: smb)
        } else {
            if smbData.count > 0 {
                clearOldSmb()
            }
        }
        updateTodaysCarbsFromEntries(entries: carbs)
        if carbs.count > 0 {
            processNSCarbs(entries: carbs)
        } else {
            if carbData.count > 0 {
                clearOldCarb()
            }
        }
        if bgCheck.count > 0 {
            processNSBGCheck(entries: bgCheck)
        } else {
            if bgCheckData.count > 0 {
                clearOldBGCheck()
            }
        }
        if temporaryOverride.count == 0, overrideGraphData.count > 0 {
            clearOldOverride()
        }
        if temporaryOverride.count > 0 {
            processNSOverrides(entries: temporaryOverride)
        }

        if temporaryTarget.count == 0, tempTargetGraphData.count > 0 {
            clearOldTempTarget()
        }
        if temporaryTarget.count > 0 {
            processNSTemporaryTarget(entries: temporaryTarget)
        }
        if suspendPump.count > 0 {
            processSuspendPump(entries: suspendPump)
        } else {
            if suspendGraphData.count > 0 {
                clearOldSuspend()
            }
        }
        if resumePump.count > 0 {
            processResumePump(entries: resumePump)
        } else {
            if resumeGraphData.count > 0 {
                clearOldResume()
            }
        }
        processSage(entries: cgmSensorStart)
        if cgmSensorStart.count > 0 {
            processSensorStart(entries: cgmSensorStart)
        } else {
            if sensorStartGraphData.count > 0 {
                clearOldSensor()
            }
        }

        processIage(entries: insulinCartridge)

        if note.count > 0 {
            processNotes(entries: note)
        } else {
            if noteGraphData.count > 0 {
                clearOldNotes()
            }
        }
        processCage(entries: pumpSiteChange)
        refreshBoardTimeEstimates()
    }
}
