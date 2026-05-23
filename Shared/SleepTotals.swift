import Foundation

/// Computes the day-nap and night-sleep totals the gauges display.
///
///  • **Night** = the most recent night session. Shown until a *new* night session begins (so during
///    the day you see last night's total; the caller swaps in the live elapsed once tonight starts).
///  • **Day** = naps of the current day (those after the most recent night ended). If a new day hasn't
///    logged a nap yet, the previous day's total persists — same principle as night.
enum SleepTotals {
    struct Session { let start: Date; let end: Date; let kind: SleepKind }

    /// Returns (dayNapMinutes, nightMinutes) from completed sessions.
    static func bases(_ completed: [Session]) -> (day: Double, night: Double) {
        let sorted = completed.sorted { $0.start > $1.start } // newest first
        func minutes(_ arr: [Session]) -> Double { arr.reduce(0) { $0 + $1.end.timeIntervalSince($1.start) / 60 } }

        let nights = sorted.filter { $0.kind == .night }
        let naps = sorted.filter { $0.kind == .nap }
        let nightMin = nights.first.map { $0.end.timeIntervalSince($0.start) / 60 } ?? 0

        guard let lastNight = nights.first else { return (minutes(naps), 0) }

        let currentDay = naps.filter { $0.start >= lastNight.end }
        if !currentDay.isEmpty { return (minutes(currentDay), nightMin) }

        // No nap since the last night yet → keep showing the previous day's naps.
        if nights.count >= 2 {
            let prevDay = naps.filter { $0.start >= nights[1].end && $0.start < lastNight.start }
            return (minutes(prevDay), nightMin)
        }
        return (minutes(naps.filter { $0.start < lastNight.start }), nightMin)
    }
}
