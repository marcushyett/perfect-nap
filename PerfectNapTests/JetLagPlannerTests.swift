import XCTest
@testable import PerfectNap

final class JetLagPlannerTests: XCTestCase {
    private var cal: Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!; return c }
    private func d(_ y: Int, _ mo: Int, _ da: Int, _ h: Int = 12) -> Date {
        cal.date(from: DateComponents(year: y, month: mo, day: da, hour: h))!
    }
    private let ny = TimeZone(identifier: "America/New_York")!     // May: EDT (UTC-4)
    private let london = TimeZone(identifier: "Europe/London")!    // May: BST (UTC+1) → +5h east of NY
    private let la = TimeZone(identifier: "America/Los_Angeles")!  // May: PDT (UTC-7) → -3h west of NY
    private let tokyo = TimeZone(identifier: "Asia/Tokyo")!        // +9h → +13h raw from NY
    private let paris = TimeZone(identifier: "Europe/Paris")!      // CEST (UTC+2)

    // MARK: direction & sign

    func testEastwardLandedShiftsScheduleLater() {
        let p = JetLagPlanner.plan(originTZ: ny, destinationTZ: london,
            departure: d(2026, 5, 10, 6), arrival: d(2026, 5, 10, 6), returnDate: d(2026, 5, 25),
            strategy: .adaptAfter, ageDays: 300, now: d(2026, 5, 10, 20), calendar: cal)
        XCTAssertNotNil(p)
        XCTAssertEqual(p!.phase, .adapting)
        XCTAssertTrue(p!.directionIsAdvance, "NY→London is eastward = phase advance.")
        XCTAssertEqual(p!.signedShiftMinutes, 300)
        XCTAssertGreaterThan(p!.scheduleOffsetMinutes, 0, "Arrival day: schedule sits later (origin clock).")
        XCTAssertEqual(p!.scheduleOffsetMinutes, 300, accuracy: 5)
    }

    func testWestwardLandedShiftsScheduleEarlier() {
        let p = JetLagPlanner.plan(originTZ: ny, destinationTZ: la,
            departure: d(2026, 5, 10, 6), arrival: d(2026, 5, 10, 6), returnDate: d(2026, 5, 25),
            strategy: .adaptAfter, ageDays: 1500, now: d(2026, 5, 10, 20), calendar: cal)
        XCTAssertNotNil(p)
        XCTAssertEqual(p!.phase, .adapting)
        XCTAssertFalse(p!.directionIsAdvance, "NY→LA is westward = phase delay.")
        XCTAssertEqual(p!.signedShiftMinutes, -180)
        XCTAssertLessThan(p!.scheduleOffsetMinutes, 0)
        XCTAssertEqual(p!.scheduleOffsetMinutes, -180, accuracy: 5)
    }

    // MARK: ramp & settle

    func testAdaptingRampsDownToSettled() {
        // age 300 → advance rate 60*1.2 = 72/day; 300min needs ~5 days.
        func offset(_ daysAfter: Int) -> Int {
            JetLagPlanner.plan(originTZ: ny, destinationTZ: london,
                departure: d(2026, 5, 10, 6), arrival: d(2026, 5, 10, 6), returnDate: d(2026, 5, 25),
                strategy: .adaptAfter, ageDays: 300, now: d(2026, 5, 10 + daysAfter, 20), calendar: cal)?.scheduleOffsetMinutes ?? 0
        }
        XCTAssertGreaterThan(offset(0), offset(2), "Offset shrinks each day.")
        XCTAssertGreaterThan(offset(2), offset(4))
        let settled = JetLagPlanner.plan(originTZ: ny, destinationTZ: london,
            departure: d(2026, 5, 10, 6), arrival: d(2026, 5, 10, 6), returnDate: d(2026, 5, 25),
            strategy: .adaptAfter, ageDays: 300, now: d(2026, 5, 16, 20), calendar: cal)
        XCTAssertEqual(settled?.phase, .settled)
        XCTAssertEqual(settled?.scheduleOffsetMinutes, 0)
    }

    // MARK: pre-adapt (adapt-before)

    func testPreAdaptEastwardShiftsEarlierBeforeDeparture() {
        let p = JetLagPlanner.plan(originTZ: ny, destinationTZ: london,
            departure: d(2026, 5, 10, 6), arrival: d(2026, 5, 10, 6), returnDate: d(2026, 5, 25),
            strategy: .adaptBefore, ageDays: 300, now: d(2026, 5, 8, 12), calendar: cal)
        XCTAssertEqual(p?.phase, .preAdapt)
        XCTAssertLessThan(p!.scheduleOffsetMinutes, 0, "Pre-adapting eastward = go to bed earlier in home time.")
    }

    // MARK: continuity at landing

    func testOffsetIsContinuousAcrossLandingExceptForTheClockJump() {
        let before = JetLagPlanner.plan(originTZ: ny, destinationTZ: london,
            departure: d(2026, 5, 10, 6), arrival: d(2026, 5, 10, 6), returnDate: d(2026, 5, 25),
            strategy: .adaptBefore, ageDays: 300, now: d(2026, 5, 10, 5), calendar: cal)!
        let after = JetLagPlanner.plan(originTZ: ny, destinationTZ: london,
            departure: d(2026, 5, 10, 6), arrival: d(2026, 5, 10, 6), returnDate: d(2026, 5, 25),
            strategy: .adaptBefore, ageDays: 300, now: d(2026, 5, 10, 7), calendar: cal)!
        // The body's progress is continuous; the displayed offset differs by exactly the zone shift.
        XCTAssertEqual(after.scheduleOffsetMinutes - before.scheduleOffsetMinutes, 300, accuracy: 5)
    }

    // MARK: already-landed (implicit via past arrival)

    func testAlreadyLandedRampsFromPastArrival() {
        let p = JetLagPlanner.plan(originTZ: ny, destinationTZ: london,
            departure: d(2026, 5, 8, 6), arrival: d(2026, 5, 8, 6), returnDate: d(2026, 5, 25),
            strategy: .adaptAfter, ageDays: 300, now: d(2026, 5, 11, 12), calendar: cal)
        XCTAssertEqual(p?.phase, .adapting)
        // 3 days at 72/day = 216 consumed, residual 84.
        XCTAssertEqual(p!.scheduleOffsetMinutes, 84, accuracy: 6)
    }

    // MARK: stay on home time

    func testShortStayRecommendsStayingOnHomeTime() {
        let p = JetLagPlanner.plan(originTZ: ny, destinationTZ: london,
            departure: d(2026, 5, 10, 6), arrival: d(2026, 5, 10, 6), returnDate: d(2026, 5, 12),
            strategy: .adaptAfter, ageDays: 300, now: d(2026, 5, 10, 20), calendar: cal)
        XCTAssertEqual(p?.phase, .stayOnHome)
        XCTAssertEqual(p?.scheduleOffsetMinutes, 300, "Hold the home schedule across the short trip.")
    }

    func testSmallShiftRecommendsStayingOnHomeTime() {
        let p = JetLagPlanner.plan(originTZ: london, destinationTZ: paris,
            departure: d(2026, 5, 10, 6), arrival: d(2026, 5, 10, 6), returnDate: d(2026, 5, 30),
            strategy: .adaptAfter, ageDays: 300, now: d(2026, 5, 10, 20), calendar: cal)
        XCTAssertEqual(p?.phase, .stayOnHome, "A 1h shift isn't worth dragging a schedule around.")
        XCTAssertEqual(p?.signedShiftMinutes, 60)
    }

    func testNegligibleShiftReturnsNil() {
        let p = JetLagPlanner.plan(originTZ: london, destinationTZ: london,
            departure: d(2026, 5, 10, 6), arrival: d(2026, 5, 10, 6), returnDate: nil,
            strategy: .adaptAfter, ageDays: 300, now: d(2026, 5, 10, 20), calendar: cal)
        XCTAssertNil(p, "Same zone → no jet lag.")
    }

    // MARK: shorter-way-round normalisation

    func testFarEastwardZoneIsTreatedAsTheShorterDelay() {
        // NY→Tokyo is +13h raw, but the body takes the shorter 11h delay.
        let p = JetLagPlanner.plan(originTZ: ny, destinationTZ: tokyo,
            departure: d(2026, 5, 10, 6), arrival: d(2026, 5, 10, 6), returnDate: d(2026, 6, 1),
            strategy: .adaptAfter, ageDays: 1500, now: d(2026, 5, 10, 20), calendar: cal)
        XCTAssertNotNil(p)
        XCTAssertEqual(p!.signedShiftMinutes, -660, "13h east normalises to 11h delay (the shorter path).")
        XCTAssertFalse(p!.directionIsAdvance)
    }

    // MARK: return leg

    func testReturnLegRampsHomeThenClears() {
        // NY→London out; on the way home (London→NY) it's a westward delay.
        let mid = JetLagPlanner.plan(originTZ: ny, destinationTZ: london,
            departure: d(2026, 5, 10, 6), arrival: d(2026, 5, 10, 6), returnDate: d(2026, 5, 20, 6),
            strategy: .adaptAfter, ageDays: 300, now: d(2026, 5, 22, 12), calendar: cal)
        XCTAssertEqual(mid?.phase, .adaptingHome)
        XCTAssertNotNil(mid)
        XCTAssertLessThan(mid!.scheduleOffsetMinutes, 0, "Heading home from the east = shift later/earlier back toward home.")

        let done = JetLagPlanner.plan(originTZ: ny, destinationTZ: london,
            departure: d(2026, 5, 10, 6), arrival: d(2026, 5, 10, 6), returnDate: d(2026, 5, 20, 6),
            strategy: .adaptAfter, ageDays: 300, now: d(2026, 5, 26, 12), calendar: cal)
        XCTAssertNil(done, "Home and fully reset → trip is over.")
    }

    // MARK: age scaling

    func testInfantAdaptsFasterThanAdult() {
        func days(_ ageDays: Int) -> Int {
            JetLagPlanner.plan(originTZ: ny, destinationTZ: london,
                departure: d(2026, 5, 10, 6), arrival: d(2026, 5, 10, 6), returnDate: d(2026, 5, 25),
                strategy: .adaptAfter, ageDays: ageDays, now: d(2026, 5, 10, 20), calendar: cal)!.daysRemaining
        }
        XCTAssertLessThanOrEqual(days(120), days(12000), "An infant re-entrains at least as fast as an adult.")
        XCTAssertLessThan(days(120), days(12000), "And in practice strictly faster for a 5h shift.")
    }

    // MARK: realism across ages — offset never exceeds the zone shift, days bounded

    func testOffsetNeverExceedsTheZoneShiftAtAnyAge() {
        for age in [30, 120, 300, 600, 1500, 4000, 12000] {
            for dayAfter in 0...8 {
                let p = JetLagPlanner.plan(originTZ: ny, destinationTZ: london,
                    departure: d(2026, 5, 10, 6), arrival: d(2026, 5, 10, 6), returnDate: d(2026, 5, 28),
                    strategy: .adaptAfter, ageDays: age, now: d(2026, 5, 10 + dayAfter, 20), calendar: cal)
                if let p {
                    XCTAssertLessThanOrEqual(abs(p.scheduleOffsetMinutes), 300 + 5,
                        "age \(age) day \(dayAfter): offset must never exceed the 5h zone shift.")
                    XCTAssertGreaterThanOrEqual(p.scheduleOffsetMinutes, -5,
                        "Eastward offset stays non-negative (never shifts the wrong way).")
                }
            }
        }
    }
}
