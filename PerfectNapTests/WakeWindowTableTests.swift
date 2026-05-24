import XCTest
@testable import PerfectNap

/// Structural invariants on the clinical wake-window table. These don't pin specific numbers (those
/// are tuned against the literature) — they guard the *shape* of the data so a future edit can't
/// silently introduce an age gap, an inverted window, a >24h sleep budget, or a non-monotonic cycle
/// length that would corrupt every downstream prediction.
final class WakeWindowTableTests: XCTestCase {
    private var profiles: [AgeProfile] { WakeWindowTable.profiles }

    func testAgeBandsAreContiguousAndAscending() {
        XCTAssertFalse(profiles.isEmpty)
        var previousMax = -1
        for p in profiles {
            XCTAssertGreaterThan(p.maxAgeDays, previousMax, "Age bands must strictly ascend (\(p.label)).")
            previousMax = p.maxAgeDays
        }
    }

    func testEveryAgeMapsToExactlyOneProfileWithNoGaps() {
        // Walk every day from birth to past the last band; the lookup must always resolve and the
        // band index must only ever move forward (no skipped or overlapping bands).
        var lastIndex = 0
        for day in stride(from: 0, through: profiles.last!.maxAgeDays + 30, by: 1) {
            let profile = WakeWindowTable.profile(forAgeDays: day)
            let idx = profiles.firstIndex { $0.label == profile.label }!
            XCTAssertGreaterThanOrEqual(idx, lastIndex, "Age \(day) jumped backward in bands.")
            lastIndex = idx
        }
        XCTAssertEqual(WakeWindowTable.profile(forAgeDays: -10).label, profiles.first!.label,
            "Negative/zero age clamps to the newborn band.")
        XCTAssertEqual(WakeWindowTable.profile(forAgeDays: 99_999).label, profiles.last!.label,
            "Beyond the last band clamps to the oldest profile.")
    }

    func testWindowsAreOrderedAndPositive() {
        for p in profiles {
            XCTAssertGreaterThan(p.window.lowMinutes, 0, "\(p.label): window must be positive.")
            XCTAssertLessThanOrEqual(p.window.lowMinutes, p.window.typicalMinutes, "\(p.label): low ≤ typical.")
            XCTAssertLessThanOrEqual(p.window.typicalMinutes, p.window.highMinutes, "\(p.label): typical ≤ high.")
        }
    }

    func testSleepBudgetsAreSaneAndUnder24Hours() {
        for p in profiles {
            XCTAssertLessThanOrEqual(p.totalDaySleepHours.lowerBound, p.totalDaySleepHours.upperBound)
            XCTAssertLessThanOrEqual(p.totalNightSleepHours.lowerBound, p.totalNightSleepHours.upperBound)
            let maxTotal = p.totalDaySleepHours.upperBound + p.totalNightSleepHours.upperBound
            XCTAssertLessThanOrEqual(maxTotal, 24.0, "\(p.label): can't sleep more than 24h/day.")
            XCTAssertGreaterThanOrEqual(p.totalNightSleepHours.upperBound, 8.0, "\(p.label): night sleep floor.")
            XCTAssertLessThanOrEqual(p.napsPerDay.lowerBound, p.napsPerDay.upperBound)
        }
    }

    func testNapCountTrendsDownWithAge() {
        // Naps-per-day should never *increase* as a baby gets older (newborns nap most).
        var previousUpper = Int.max
        for p in profiles {
            XCTAssertLessThanOrEqual(p.napsPerDay.upperBound, previousUpper, "\(p.label): nap count rose with age.")
            previousUpper = p.napsPerDay.upperBound
        }
    }

    func testSleepCycleLengthIsMonotonicAndInRange() {
        var previous = 0
        for p in profiles {
            let c = p.sleepCycleMinutes
            XCTAssertGreaterThanOrEqual(c, previous, "\(p.label): cycle length must not shrink with age.")
            XCTAssertTrue((40...120).contains(c), "\(p.label): \(c)-min cycle is outside the plausible range.")
            previous = c
        }
    }

    func testPositionFactorsAreInPlausibleRange() {
        for p in profiles {
            XCTAssertTrue((0.5...1.5).contains(p.firstWindowFactor), "\(p.label): firstWindowFactor out of range.")
            XCTAssertTrue((0.5...1.5).contains(p.preBedtimeFactor), "\(p.label): preBedtimeFactor out of range.")
        }
    }

    func testWakeWindowChangesSmoothlyEveryDay() {
        // No band-boundary cliffs: the typical window changes by at most a couple of minutes per day
        // across 0–2yr (it used to step ~20 min at each band edge). And it never decreases with age here.
        var prev = WakeWindowTable.profile(forAgeDays: 0).window.typicalMinutes
        for day in 1...730 {
            let t = WakeWindowTable.profile(forAgeDays: day).window.typicalMinutes
            XCTAssertLessThanOrEqual(abs(t - prev), 3, "Day \(day): \(abs(t - prev))-min jump — should be continuous.")
            XCTAssertGreaterThanOrEqual(t, prev, "Day \(day): the window should not shrink with age in 0–2yr.")
            prev = t
        }
    }

    func testBandMidpointStillHitsPublishedValue() {
        // Interpolation passes through each band's documented typical at the band's midpoint age.
        XCTAssertEqual(WakeWindowTable.profile(forAgeDays: 75).window.typicalMinutes, 80, accuracy: 1)   // 2–3 mo
        XCTAssertEqual(WakeWindowTable.profile(forAgeDays: 270).window.typicalMinutes, 180, accuracy: 1) // 8–10 mo
    }
}
