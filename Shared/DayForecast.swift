import Foundation

/// A projected future nap. `startUncertaintyMinutes` widens for naps further out — the chart draws
/// it as an error envelope so the forecast visibly gets less certain as the day goes on.
struct ForecastNap: Equatable, Identifiable {
    let id = UUID()
    let start: Date
    let end: Date
    let startUncertaintyMinutes: Double

    static func == (a: ForecastNap, b: ForecastNap) -> Bool {
        a.start == b.start && a.end == b.end && a.startUncertaintyMinutes == b.startUncertaintyMinutes
    }
}

/// Projects the remaining naps of the day by chaining the wake-window → nap → wake-window pattern
/// forward from the next predicted nap, stopping at bedtime. Each successive nap compounds timing
/// error, so the uncertainty grows step by step.
enum DayForecast {
    static func naps(
        firstNapStart: Date,
        napDurationMinutes: Double,
        wakeWindowMinutes: Double,
        bedtime: Date?,
        maxNaps: Int,
        baseUncertaintyMinutes: Double = 15,
        perStepUncertaintyMinutes: Double = 20
    ) -> [ForecastNap] {
        guard maxNaps > 0, napDurationMinutes > 0, wakeWindowMinutes > 0 else { return [] }
        var result: [ForecastNap] = []
        var start = firstNapStart
        for i in 0..<maxNaps {
            if let bedtime, start >= bedtime { break }
            let end = start.addingTimeInterval(napDurationMinutes * 60)
            result.append(ForecastNap(
                start: start,
                end: end,
                startUncertaintyMinutes: baseUncertaintyMinutes + Double(i) * perStepUncertaintyMinutes
            ))
            start = end.addingTimeInterval(wakeWindowMinutes * 60)
        }
        return result
    }
}
