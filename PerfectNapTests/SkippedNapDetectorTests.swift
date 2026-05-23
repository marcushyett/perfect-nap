import XCTest
@testable import PerfectNap

final class SkippedNapDetectorTests: XCTestCase {
    // ~9 months → 2 naps/day, typical WW 180, high 240.
    private var profile: AgeProfile { WakeWindowTable.profile(forAgeDays: 270) }

    func testNoInferenceWithinNormalWindow() {
        let lastWake = Date.now.addingTimeInterval(-3 * 3600) // 3h, within high (4h)
        let inf = SkippedNapDetector.detect(lastWake: lastWake, now: .now, profile: profile, adaptationFactor: 1.0)
        XCTAssertNil(inf, "A 3h wake at 9mo is within the normal window — no missed nap.")
    }

    func testInfersMissedNapWhenWindowImplausiblyLong() {
        // high = 240 min; implausibility factor 1.5 → > 360 min (6h). Use 8h.
        let lastWake = Date.now.addingTimeInterval(-8 * 3600)
        let inf = SkippedNapDetector.detect(lastWake: lastWake, now: .now, profile: profile, adaptationFactor: 1.0)
        XCTAssertNotNil(inf, "An 8h wake at 9mo strongly implies a forgotten nap.")
        XCTAssertGreaterThan(inf!.likelyStart, lastWake)
        XCTAssertLessThan(inf!.likelyEnd, .now)
        XCTAssertGreaterThan(inf!.likelyEnd, inf!.likelyStart)
    }

    func testInferenceIsStableAsClockAdvances() {
        // Same last wake, two different "now"s 5 min apart → identical inferred slot. (Drift here is
        // what flickered the home screen between "next nap in 0m" and "overdue by 0 min".)
        let lastWake = Date.now.addingTimeInterval(-8 * 3600)
        let a = SkippedNapDetector.detect(lastWake: lastWake, now: .now, profile: profile, adaptationFactor: 1.0)
        let b = SkippedNapDetector.detect(lastWake: lastWake, now: Date.now.addingTimeInterval(300), profile: profile, adaptationFactor: 1.0)
        XCTAssertNotNil(a)
        XCTAssertEqual(a, b, "Inferred nap must not move with the clock.")
    }

    func testNoInferenceForAgesThatDontNap() {
        // 5+ years: napsPerDay upper bound 0.
        let old = WakeWindowTable.profile(forAgeDays: 365 * 5)
        let lastWake = Date.now.addingTimeInterval(-12 * 3600)
        XCTAssertNil(SkippedNapDetector.detect(lastWake: lastWake, now: .now, profile: old, adaptationFactor: 1.0))
    }
}
