import Foundation

enum SleepKind: String, Codable, CaseIterable {
    case nap
    case night

    static func classify(start: Date, calendar: Calendar = .current) -> SleepKind {
        let hour = calendar.component(.hour, from: start)
        return (hour >= 19 || hour < 5) ? .night : .nap
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
