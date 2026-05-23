import XCTest
@testable import PerfectNap

final class MissingNightDetectorTests: XCTestCase {
    // "6–8 months": night-sleep band 11–12h → assumed midpoint 11.5h.
    private let profile = WakeWindowTable.profile(forAgeDays: 200)
    private func at(_ hour: Int) -> Date {
        Calendar.current.date(bySettingHour: hour, minute: 0, second: 0, of: .now)!
    }

    func testNudgesWhenNoNightWasRecorded() {
        let now = at(7)
        let inf = MissingNightDetector.detect(
            recentNightSeconds: 0, lastSleepEnd: now.addingTimeInterval(-14 * 3600), now: now, profile: profile)
        XCTAssertNotNil(inf, "No recorded night this morning → nudge.")
        XCTAssertEqual(inf!.assumedHours, 11.5, accuracy: 0.01, "Assumes the age-band midpoint night.")
        XCTAssertEqual(inf!.suggestedStart.timeIntervalSince(now), -11.5 * 3600, accuracy: 2)
    }

    func testNudgesWhenOnlyAFragmentWasRecorded() {
        let now = at(7)
        XCTAssertNotNil(MissingNightDetector.detect(
            recentNightSeconds: 1.5 * 3600, lastSleepEnd: now, now: now, profile: profile),
            "Under ~2h recorded = not really recorded → assume a full night and nudge.")
    }

    func testNoNudgeWhenAReasonableNightWasRecorded() {
        // The reported bug: 10.5h recorded must NOT warn — that's plenty of sleep, even if a touch
        // short of the 11–12h band. Only an almost-empty night should nudge.
        let now = at(7)
        XCTAssertNil(MissingNightDetector.detect(
            recentNightSeconds: 10.5 * 3600, lastSleepEnd: now, now: now, profile: profile),
            "A reasonable night (10 of 12h) must not trigger the nudge.")
    }

    func testThresholdSitsAtTwoHours() {
        let now = at(8)
        XCTAssertNil(MissingNightDetector.detect(recentNightSeconds: 2 * 3600, lastSleepEnd: now, now: now, profile: profile),
                     "Exactly 2h counts as recorded.")
        XCTAssertNotNil(MissingNightDetector.detect(recentNightSeconds: 1.99 * 3600, lastSleepEnd: now, now: now, profile: profile),
                        "Just under 2h is treated as unrecorded.")
    }

    func testNoNudgeInTheAfternoon() {
        let now = at(15)
        XCTAssertNil(MissingNightDetector.detect(
            recentNightSeconds: 0, lastSleepEnd: now.addingTimeInterval(-20 * 3600), now: now, profile: profile),
            "\"Did you record last night?\" makes no sense in the afternoon.")
    }

    func testNoNudgeForBrandNewUserWithNoHistory() {
        XCTAssertNil(MissingNightDetector.detect(recentNightSeconds: 0, lastSleepEnd: nil, now: at(7), profile: profile))
    }
}
