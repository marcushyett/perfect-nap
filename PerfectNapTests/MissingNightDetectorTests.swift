import XCTest
@testable import PerfectNap

final class MissingNightDetectorTests: XCTestCase {
    // "6–8 months": night-sleep band 11–12h → assumed midpoint 11.5h.
    private let profile = WakeWindowTable.profile(forAgeDays: 200)
    private func at(_ hour: Int) -> Date {
        Calendar.current.date(bySettingHour: hour, minute: 0, second: 0, of: .now)!
    }

    func testNudgesInMorningWhenLastSleepWasYesterdaysNap() {
        let now = at(7)
        let lastNapEnd = now.addingTimeInterval(-14 * 3600)   // ~5pm yesterday; the night since is unlogged
        let inf = MissingNightDetector.detect(lastSleepKind: .nap, lastSleepEnd: lastNapEnd, now: now, profile: profile)
        XCTAssertNotNil(inf, "Morning + a 14h-old last sleep means the night wasn't recorded → nudge.")
        XCTAssertEqual(inf!.assumedHours, 11.5, accuracy: 0.01, "Assumes the age-band midpoint night.")
        XCTAssertEqual(inf!.suggestedEnd.timeIntervalSince(now), 0, accuracy: 2, "Prefilled night ends ~now.")
        XCTAssertEqual(inf!.suggestedStart.timeIntervalSince(now), -11.5 * 3600, accuracy: 2, "Start = now − assumed night.")
    }

    func testNoNudgeWhenLastNightWasRecordedThisMorning() {
        let now = at(7)
        let nightEnd = now.addingTimeInterval(-1 * 3600)      // woke at 6am from a logged night
        XCTAssertNil(MissingNightDetector.detect(lastSleepKind: .night, lastSleepEnd: nightEnd, now: now, profile: profile))
    }

    func testNoNudgeInTheAfternoon() {
        let now = at(15)
        let lastNapEnd = now.addingTimeInterval(-20 * 3600)
        XCTAssertNil(MissingNightDetector.detect(lastSleepKind: .nap, lastSleepEnd: lastNapEnd, now: now, profile: profile),
                     "\"Did you record last night?\" makes no sense in the afternoon.")
    }

    func testNoNudgeForBrandNewUserWithNoHistory() {
        XCTAssertNil(MissingNightDetector.detect(lastSleepKind: nil, lastSleepEnd: nil, now: at(7), profile: profile))
    }

    func testNoNudgeWhenLastSleepWasRecentThisMorning() {
        let now = at(9)
        let recentNapEnd = now.addingTimeInterval(-2 * 3600)  // napped at 7am — the night clearly wasn't skipped
        XCTAssertNil(MissingNightDetector.detect(lastSleepKind: .nap, lastSleepEnd: recentNapEnd, now: now, profile: profile))
    }
}
