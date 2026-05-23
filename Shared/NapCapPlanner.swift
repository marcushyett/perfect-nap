import Foundation

/// Suggests when to wake a baby from an over-long nap. Two research-backed constraints, whichever
/// binds first:
///  • **Protect bedtime** (primary): the last nap must end at least one pre-bed wake window before
///    the target bedtime, or the built-up sleep pressure (Process S) discharges and bedtime slips
///    late with a harder settle (Weissbluth; Taking Cara Babies; Huckleberry SweetSpot).
///  • **Balance day sleep**: total daytime sleep shouldn't exceed the age band (AAP/AASM 24-hour
///    totals) — over-napping borrows from the night.
struct WakeSuggestion: Equatable {
    let wakeBy: Date
    let reason: Reason
    enum Reason: Equatable { case protectBedtime, balanceDaySleep }
}

enum NapCapPlanner {
    /// `completedNapMinutesToday` / `completedNapsToday` exclude the in-progress nap.
    static func suggest(
        napStart: Date,
        bedtime: Date?,
        profile: AgeProfile,
        adaptationFactor: Double,
        completedNapMinutesToday: Double,
        completedNapsToday: Int
    ) -> WakeSuggestion? {
        guard profile.totalDaySleepHours.upperBound > 0 else { return nil }
        let adapt = min(max(adaptationFactor, 0.75), 1.25)

        let dayBudgetMin = profile.totalDaySleepHours.upperBound * 60
        let typicalNaps = max(1, (profile.napsPerDay.lowerBound + profile.napsPerDay.upperBound) / 2)
        let perNapShare = dayBudgetMin / Double(typicalNaps)

        // A *single* nap shouldn't exceed a realistic length: ~1.5× the per-nap share of the budget,
        // never more than what's left of the day budget, hard-capped at 3h. (The old code capped at
        // the WHOLE remaining budget, which suggested a 7-hour nap.)
        let remainingBudget = max(30, dayBudgetMin - completedNapMinutesToday)
        let maxSingleNap = min(180, min(remainingBudget, perNapShare * 1.5))
        var candidates: [(Date, WakeSuggestion.Reason)] = [(napStart.addingTimeInterval(maxSingleNap * 60), .balanceDaySleep)]

        // A daytime nap must never run past bedtime; the last nap ends one pre-bed window before it.
        if let bedtime {
            let isLastNap = max(1, typicalNaps - completedNapsToday) <= 1
            let preBedWW = Double(profile.window.typicalMinutes) * profile.preBedtimeFactor * adapt
            let bedCap = isLastNap ? bedtime.addingTimeInterval(-preBedWW * 60) : bedtime
            candidates.append((bedCap, .protectBedtime))
        }

        guard let binding = candidates.min(by: { $0.0 < $1.0 }) else { return nil }
        // Don't suggest waking before the nap is restorative (~one sleep cycle).
        let floor = napStart.addingTimeInterval(30 * 60)
        let capped = max(binding.0, floor)

        // Snap to a sleep-cycle boundary so we wake them at a cycle end, not mid-cycle (groggy).
        // Round the nap length DOWN to whole cycles within the cap (≥1 cycle).
        let cycle = Double(profile.sleepCycleMinutes)
        let capMinutes = capped.timeIntervalSince(napStart) / 60
        let cycles = max(1, (capMinutes / cycle).rounded(.down))
        let alignedMinutes = min(capMinutes, cycles * cycle)
        return WakeSuggestion(wakeBy: napStart.addingTimeInterval(alignedMinutes * 60), reason: binding.1)
    }
}
