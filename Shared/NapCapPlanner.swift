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

        // Day-sleep budget: cap so the day's total stays within the age upper bound.
        let dayBudgetMin = profile.totalDaySleepHours.upperBound * 60
        let remaining = max(20, dayBudgetMin - completedNapMinutesToday)
        var candidates: [(Date, WakeSuggestion.Reason)] = [(napStart.addingTimeInterval(remaining * 60), .balanceDaySleep)]

        // Bedtime cap — only for the last nap of the day (when one nap remains, i.e. this one).
        let typicalNaps = max(1, (profile.napsPerDay.lowerBound + profile.napsPerDay.upperBound) / 2)
        let isLastNap = max(1, typicalNaps - completedNapsToday) <= 1
        if isLastNap, let bedtime {
            let preBedWW = Double(profile.window.typicalMinutes) * profile.preBedtimeFactor * adapt
            candidates.append((bedtime.addingTimeInterval(-preBedWW * 60), .protectBedtime))
        }

        guard let binding = candidates.min(by: { $0.0 < $1.0 }) else { return nil }
        // Don't suggest waking before the nap is restorative (~one sleep cycle).
        let floor = napStart.addingTimeInterval(30 * 60)
        return WakeSuggestion(wakeBy: max(binding.0, floor), reason: binding.1)
    }
}
