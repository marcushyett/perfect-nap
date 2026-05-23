import XCTest
@testable import PerfectNap

final class DSTTests: XCTestCase {
    private let tz = TimeZone(identifier: "America/New_York")!
    private var cal: Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = tz; return c }
    private func date(_ y: Int, _ mo: Int, _ d: Int, _ h: Int) -> Date {
        cal.date(from: DateComponents(year: y, month: mo, day: d, hour: h))!
    }

    func testSpringForwardShiftsEarlier() {
        // US DST begins Sun Mar 8 2026. Two days before → easing earlier (phase advance).
        let adj = DSTAdjuster.current(now: date(2026, 3, 6, 12), timeZone: tz, calendar: cal)
        XCTAssertNotNil(adj)
        XCTAssertTrue(adj!.springsForward)
        XCTAssertLessThan(adj!.shiftMinutes, 0, "Spring forward → shift the schedule earlier.")
        XCTAssertGreaterThanOrEqual(adj!.shiftMinutes, -60)
    }

    func testFallBackShiftsLater() {
        // US DST ends Sun Nov 1 2026. Two days before → easing later.
        let adj = DSTAdjuster.current(now: date(2026, 10, 30, 12), timeZone: tz, calendar: cal)
        XCTAssertNotNil(adj)
        XCTAssertFalse(adj!.springsForward)
        XCTAssertGreaterThan(adj!.shiftMinutes, 0, "Fall back → shift the schedule later.")
    }

    func testNoAdjustmentFarFromAnyTransition() {
        XCTAssertNil(DSTAdjuster.current(now: date(2026, 6, 1, 12), timeZone: tz, calendar: cal))
    }

    func testShiftRampsUpAsTransitionApproaches() {
        let early = DSTAdjuster.current(now: date(2026, 3, 6, 2), timeZone: tz, calendar: cal)  // ~2 days out
        let late = DSTAdjuster.current(now: date(2026, 3, 7, 12), timeZone: tz, calendar: cal)  // <1 day out
        XCTAssertNotNil(early); XCTAssertNotNil(late)
        XCTAssertLessThan(abs(early!.shiftMinutes), abs(late!.shiftMinutes), "Closer to the change → bigger shift.")
    }
}
