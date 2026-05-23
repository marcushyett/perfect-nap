import Foundation

/// Past ~4 months the circadian rhythm (Process C) matures and sleep consolidates, so care shifts
/// from purely reactive wake windows toward a fairly fixed daily clock schedule (Weissbluth;
/// Taking Cara Babies move to "by the clock" naps around 4–6 months). We model the
/// schedule as clock targets anchored to the morning wake, and blend the reactive wake-window
/// prediction toward them with a weight that ramps up with (corrected) age.
enum DaySchedule {
    /// Clock time for the Nth nap (0-based) of the day: morning wake + accumulated ideal wake windows
    /// and nap lengths. A fixed daily rhythm that the prediction is pulled toward.
    static func scheduledNapStart(napIndex: Int, morningWake: Date, profile: AgeProfile, adaptationFactor: Double = 1.0) -> Date {
        let adapt = min(max(adaptationFactor, 0.75), 1.25)
        let typicalWW = Double(profile.window.typicalMinutes) * adapt
        let napLen = BedtimePlanner.typicalNapMinutes(profile)
        var offset = 0.0
        for i in 0...max(0, napIndex) {
            offset += typicalWW * (i == 0 ? profile.firstWindowFactor : 1.0)
            if i < napIndex { offset += napLen }
        }
        return morningWake.addingTimeInterval(offset * 60)
    }
}

enum ScheduleBlend {
    static let startDays = 120.0   // ~4 months — schedule influence begins
    static let fullDays = 270.0    // ~9 months — schedule influence reaches its cap
    static let maxWeight = 0.7     // never fully overrides the reactive signal (the "not ready" guard)

    /// 0 below ~4 months (pure wake windows), ramping smoothly to `maxWeight` by ~9 months.
    static func weight(adjustedAgeDays: Int) -> Double {
        guard Double(adjustedAgeDays) > startDays else { return 0 }
        let t = min(1.0, (Double(adjustedAgeDays) - startDays) / (fullDays - startDays))
        return maxWeight * t
    }

    /// Weighted blend of two times.
    static func blend(reactive: Date, scheduled: Date, weight: Double) -> Date {
        let r = reactive.timeIntervalSinceReferenceDate
        let s = scheduled.timeIntervalSinceReferenceDate
        return Date(timeIntervalSinceReferenceDate: r * (1 - weight) + s * weight)
    }
}
