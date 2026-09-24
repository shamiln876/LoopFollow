// LoopFollow
// BoardTimeEstimate.swift

// Display-only estimates. These values must never be used to dose insulin.
import Foundation

enum BoardTimeEstimate {
    struct Dose {
        let units: Double
        let date: Date
    }

    struct CarbSample {
        let grams: Double
        let date: Date
    }

    // This is a local configuration for the Trio user. Match these values to
    // the active Trio profile before relying on the insulin tail display.
    static let insulinDurationMinutes = 360.0
    static let insulinPeakMinutes = 70.0
    static let meaningfulInsulinUnits = 0.05

    /// Time until the modeled *bolus + SMB* remainder falls below 0.05 U.
    /// Basal deviations are part of Trio's IOB but are not available as doses here.
    static func insulinEnd(doses: [Dose], now: Date) -> Date? {
        let active = doses.filter { $0.units > 0 && $0.units.isFinite &&
            now.timeIntervalSince($0.date) >= -60 &&
            now.timeIntervalSince($0.date) < insulinDurationMinutes * 60 }
        guard !active.isEmpty else { return nil }
        for minutes in stride(from: 0, through: Int(insulinDurationMinutes), by: 1) {
            let date = now.addingTimeInterval(Double(minutes) * 60)
            let remaining = active.reduce(0.0) { sum, dose in
                sum + dose.units * fractionRemaining(minutes: date.timeIntervalSince(dose.date) / 60)
            }
            if remaining < meaningfulInsulinUnits { return date }
        }
        return now.addingTimeInterval(insulinDurationMinutes * 60)
    }

    // OpenAPS exponential insulin-action curve, integrated analytically.
    // t and DIA are in minutes. Peak must be less than half of DIA.
    static func fractionRemaining(minutes t: Double) -> Double {
        let dia = insulinDurationMinutes
        let peak = insulinPeakMinutes
        if t <= 0 { return 1 }
        if t >= dia { return 0 }
        let tau = peak * (1 - peak / dia) / (1 - 2 * peak / dia)
        let a = 2 * tau / dia
        let scale = 1 / (1 - a + (1 + a) * exp(-dia / tau))
        let remaining = 1 - scale * (1 - a) *
            ((t * t / (tau * dia * (1 - a)) - t / tau - 1) * exp(-t / tau) + 1)
        return min(1, max(0, remaining))
    }

    /// Extrapolate the observed *COB* decline only when there are at least
    /// three fresh, falling Trio samples after the most recent carb entry.
    /// A plateau or new food makes the estimate unavailable, not a false timer.
    static func carbEnd(samples: [CarbSample], mostRecentCarb: Date?, now: Date) -> Date? {
        let recent = samples.filter { sample in
            sample.grams > 0 && sample.grams.isFinite &&
                now.timeIntervalSince(sample.date) >= 0 &&
                now.timeIntervalSince(sample.date) <= 45 * 60 &&
                (mostRecentCarb.map { sample.date >= $0 } ?? true)
        }.sorted { $0.date < $1.date }
        guard recent.count >= 3, let first = recent.first, let last = recent.last,
              now.timeIntervalSince(last.date) <= 15 * 60,
              last.date.timeIntervalSince(first.date) >= 15 * 60,
              last.grams < first.grams - 2,
              last.grams < recent[recent.count - 2].grams - 0.5 else { return nil }

        let rates = zip(recent, recent.dropFirst()).compactMap { earlier, later -> Double? in
            let minutes = later.date.timeIntervalSince(earlier.date) / 60
            guard minutes >= 2, later.grams < earlier.grams else { return nil }
            return (earlier.grams - later.grams) / minutes
        }.sorted()
        guard rates.count >= 2 else { return nil }
        let rate = rates[rates.count / 2]
        let minutesLeft = last.grams / rate
        guard minutesLeft >= 0, minutesLeft <= 240 else { return nil }
        return last.date.addingTimeInterval(minutesLeft * 60)
    }
}
