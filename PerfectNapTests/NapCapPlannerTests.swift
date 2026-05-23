import XCTest
@testable import PerfectNap

final class NapCapPlannerTests: XCTestCase {
    private var profile: AgeProfile { WakeWindowTable.profile(forAgeDays: 270) } // ~9mo, ~2 naps
    private let cal = Calendar.current
    private func at(_ h: Int, _ m: Int = 0) -> Date { cal.date(bySettingHour: h, minute: m, second: 0, of: .now)! }

    func testProtectBedtimeBindsForLastNap() {
        // Last nap (1 already done today), bedtime 19:00, plenty of day-sleep budget left.
        let sug = NapCapPlanner.suggest(
            napStart: at(14, 0), bedtime: at(19, 0), profile: profile,
            adaptationFactor: 1.0, completedNapMinutesToday: 90, completedNapsToday: 1
        )
        XCTAssertNotNil(sug)
        XCTAssertEqual(sug!.reason, .protectBedtime)
        XCTAssertLessThan(sug!.wakeBy, at(19, 0), "Must wake before bedtime.")
        XCTAssertGreaterThan(sug!.wakeBy, at(14, 30), "And after a restorative minimum.")
    }

    func testBalanceDaySleepWhenMoreNapsRemain() {
        // First nap of the day (0 done) → not the last nap → bedtime cap doesn't apply.
        let sug = NapCapPlanner.suggest(
            napStart: at(9, 0), bedtime: at(19, 0), profile: profile,
            adaptationFactor: 1.0, completedNapMinutesToday: 0, completedNapsToday: 0
        )
        XCTAssertNotNil(sug)
        XCTAssertEqual(sug!.reason, .balanceDaySleep)
    }

    func testRestorativeFloorPreventsImmediateWake() {
        // Day budget already blown → still shouldn't suggest waking in the first 30 min.
        let start = at(16, 0)
        let sug = NapCapPlanner.suggest(
            napStart: start, bedtime: nil, profile: profile,
            adaptationFactor: 1.0, completedNapMinutesToday: 600, completedNapsToday: 2
        )
        XCTAssertNotNil(sug)
        XCTAssertGreaterThanOrEqual(sug!.wakeBy, start.addingTimeInterval(30 * 60))
    }
}
