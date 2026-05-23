import Foundation

enum SleepKind: String, Codable, CaseIterable {
    case nap
    case night

    /// A sleep beginning within this many minutes *before* the target bedtime is an early night, not
    /// a late nap (an overtired baby going down early is starting the night).
    static let earlyBedtimeBufferMinutes = 60
    /// Default evening cutoff when no bedtime is set, and the latest the night ever starts.
    static let defaultNightStartMinutes = 19 * 60   // 7:00 PM
    static let morningStartMinutes = 5 * 60         // before 5:00 AM is still night

    /// Classifies a sleep as a daytime nap or night sleep. When a target bedtime is set, a sleep that
    /// starts close to (or after) it counts as night — so an early bedtime turns the "nap" into night
    /// sleep rather than a late-afternoon nap.
    static func classify(start: Date, bedtimeMinutes: Int? = nil, calendar: Calendar = .current) -> SleepKind {
        let c = calendar.dateComponents([.hour, .minute], from: start)
        let minuteOfDay = (c.hour ?? 0) * 60 + (c.minute ?? 0)
        if minuteOfDay < morningStartMinutes { return .night }      // pre-dawn is always night
        var nightStart = defaultNightStartMinutes
        if let bedtimeMinutes, bedtimeMinutes > 0 {
            nightStart = min(nightStart, bedtimeMinutes - earlyBedtimeBufferMinutes)
        }
        return minuteOfDay >= nightStart ? .night : .nap
    }

    /// A "night waking": the baby woke from night sleep and it's still night. The right response is a
    /// simple resettle (back to sleep) — not a daytime nap with a wake-window countdown.
    static func isNightWaking(lastSleepKind: SleepKind?, now: Date, bedtimeMinutes: Int?, calendar: Calendar = .current) -> Bool {
        lastSleepKind == .night && classify(start: now, bedtimeMinutes: bedtimeMinutes, calendar: calendar) == .night
    }
}

/// Pure split arithmetic, isolated from the data layer so it's unit-testable.
enum SleepSplit {
    /// Given a completed sleep [start, end] and a mid-sleep wake gap [awakeStart, awakeEnd],
    /// returns the two resulting closed intervals, or nil if the gap isn't strictly inside the sleep.
    static func plan(
        start: Date,
        end: Date?,
        awakeStart: Date,
        awakeEnd: Date
    ) -> (first: (Date, Date), second: (Date, Date))? {
        guard let end else { return nil }
        guard awakeStart > start, awakeEnd < end, awakeEnd > awakeStart else { return nil }
        return ((start, awakeStart), (awakeEnd, end))
    }
}

/// What NapPredictor / AdaptiveModel need from a baby — a value view so they don't depend on the
/// persistence type (keeps prediction logic and its tests free of Core Data).
protocol BabyProfileProviding {
    var ageInDays: Int { get }
    var adaptationFactor: Double { get }
    var adaptationConfidence: Double { get }
}
