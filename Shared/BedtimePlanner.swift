import Foundation

/// Backward nap planner: given a target bedtime, works out when the *next* nap should start so the
/// day lands at the bedtime "sweet spot" — late enough that sleep pressure (Process S) has built for
/// an easy bedtime, early enough to avoid the overtired second wind.
///
/// Why backward from bedtime: across the practitioner programs (Huckleberry SweetSpot, Taking Cara
/// Babies, Weissbluth) the last wake window before bed is the longest and most circadian-gated, so
/// bedtime is anchored to the final nap's end + that window. Fixing bedtime therefore fixes the last
/// nap's end; earlier naps space back from it by typical wake windows. Day-sleep is implicitly
/// capped by the AAP/AASM 24-hour total (over-napping would erode the pre-bed pressure).
struct BedtimePlan: Equatable {
    let recommendedNapStart: Date
    let recommendedNapEnd: Date
    /// Sweet-spot bedtime window — aim for the centre, tolerate the edges.
    let bedtimeSweetSpot: ClosedRange<Date>
    let napsRemaining: Int
    let isLastNapBeforeBed: Bool
    /// True when physiological wake-window limits forced the nap off the ideal backward slot
    /// (e.g. target bedtime isn't reachable without an over-long or too-short wake window).
    let clampedToLimits: Bool
}

enum BedtimePlanner {
    /// Estimated single-nap length for the age: total day sleep midpoint split across typical naps.
    static func typicalNapMinutes(_ profile: AgeProfile) -> Double {
        let dayMid = (profile.totalDaySleepHours.lowerBound + profile.totalDaySleepHours.upperBound) / 2 * 60
        let naps = max(1, (profile.napsPerDay.lowerBound + profile.napsPerDay.upperBound) / 2)
        return dayMid / Double(naps)
    }

    static func plan(
        targetBedtime: Date,
        now: Date,
        lastWake: Date,
        profile: AgeProfile,
        adaptationFactor: Double,
        completedNapsToday: Int,
        sweetSpotToleranceMinutes: Double = 20
    ) -> BedtimePlan? {
        let adapt = min(max(adaptationFactor, 0.75), 1.25)
        let typical = Double(profile.window.typicalMinutes)
        let preBedWW = typical * profile.preBedtimeFactor * adapt
        let interNapWW = typical * adapt
        let napLen = typicalNapMinutes(profile)

        let typicalNaps = max(profile.napsPerDay.lowerBound,
                              (profile.napsPerDay.lowerBound + profile.napsPerDay.upperBound) / 2)
        let napsRemaining = max(0, typicalNaps - completedNapsToday)
        guard napsRemaining > 0 else { return nil }

        // Anchor: last nap ends one pre-bed window before target bedtime.
        let lastNapEnd = targetBedtime.addingTimeInterval(-preBedWW * 60)
        let lastNapStart = lastNapEnd.addingTimeInterval(-napLen * 60)

        // Next nap is the earliest of the remaining naps; step back from the last nap by (window+nap).
        let stepsBack = Double(napsRemaining - 1) * (interNapWW + napLen)
        let idealNextStart = lastNapStart.addingTimeInterval(-stepsBack * 60)

        // Clamp to physiological wake-window limits measured from the last wake. We deliberately do
        // NOT floor at `now`: when the ideal nap time has already passed, the recommended time must
        // be allowed to sit in the past so the app can report how *overdue* the nap is, rather than
        // dragging the recommendation forward with the clock (which read as "overdue by 0").
        let minStart = lastWake.addingTimeInterval(Double(profile.window.lowMinutes) * adapt * 60)
        let maxStart = lastWake.addingTimeInterval(Double(profile.window.highMinutes) * adapt * 60)
        var nextStart = min(max(idealNextStart, minStart), maxStart)
        let clamped = abs(nextStart.timeIntervalSince(idealNextStart)) > 60

        // If clamping pushed the only remaining nap, recompute bedtime from the achievable nap end.
        let isLast = napsRemaining == 1
        let nextEnd = nextStart.addingTimeInterval(napLen * 60)
        let achievableBedtime = isLast ? nextEnd.addingTimeInterval(preBedWW * 60) : targetBedtime
        let center = clamped && isLast ? achievableBedtime : targetBedtime

        let tol = sweetSpotToleranceMinutes * 60
        let sweetSpot = center.addingTimeInterval(-tol)...center.addingTimeInterval(tol)

        // Guard against degenerate ordering after clamping.
        if nextStart < minStart { nextStart = minStart }

        return BedtimePlan(
            recommendedNapStart: nextStart,
            recommendedNapEnd: nextStart.addingTimeInterval(napLen * 60),
            bedtimeSweetSpot: sweetSpot,
            napsRemaining: napsRemaining,
            isLastNapBeforeBed: isLast,
            clampedToLimits: clamped
        )
    }
}
