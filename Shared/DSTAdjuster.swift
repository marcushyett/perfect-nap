import Foundation

/// Fully automatic daylight-saving easing: in the few days before the device's DST change, nudge the
/// schedule so the 1-hour jump isn't a jolt. Spring-forward (lose an hour, a phase *advance* — the
/// harder direction) shifts the schedule earlier; fall-back shifts it later. The shift ramps to a
/// full hour by the transition, after which the local clock itself changes and the schedule realigns.
struct DSTAdjustment: Equatable {
    /// Signed minutes to shift the schedule now: negative = earlier (spring forward), positive = later.
    let shiftMinutes: Int
    let transitionDate: Date
    let springsForward: Bool
}

enum DSTAdjuster {
    static let windowDays = 3
    static let totalShiftMinutes = 60.0

    static func current(now: Date = .now, timeZone: TimeZone = .current, calendar: Calendar = .current) -> DSTAdjustment? {
        guard let transition = timeZone.nextDaylightSavingTimeTransition(after: now), transition > now else { return nil }
        let secondsUntil = transition.timeIntervalSince(now)
        guard secondsUntil <= Double(windowDays) * 86_400 else { return nil }

        let before = timeZone.daylightSavingTimeOffset(for: transition.addingTimeInterval(-3600))
        let after = timeZone.daylightSavingTimeOffset(for: transition.addingTimeInterval(3600))
        let springsForward = after > before
        guard before != after else { return nil }

        // Ramp from 0 (full window out) to the full hour at the transition.
        let daysUntil = secondsUntil / 86_400
        let progressed = totalShiftMinutes * (Double(windowDays) - daysUntil) / Double(windowDays)
        let magnitude = min(totalShiftMinutes, max(0, progressed))
        let shift = springsForward ? -magnitude : magnitude
        return DSTAdjustment(shiftMinutes: Int(shift.rounded()), transitionDate: transition, springsForward: springsForward)
    }
}
