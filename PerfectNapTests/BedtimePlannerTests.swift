import XCTest
@testable import PerfectNap

final class BedtimePlannerTests: XCTestCase {
    private let cal = Calendar.current
    private func today(_ h: Int, _ m: Int = 0) -> Date {
        cal.date(bySettingHour: h, minute: m, second: 0, of: .now)!
    }
    // ~9 months → 2 naps/day, typical WW 180, preBedtimeFactor 1.25.
    private var profile: AgeProfile { WakeWindowTable.profile(forAgeDays: 270) }

    func testLastNapAnchorsToBedtimeMinusPreBedWindow() {
        let target = today(19, 0)
        let lastWake = today(11, 0)
        let plan = BedtimePlanner.plan(
            targetBedtime: target, now: today(11, 5), lastWake: lastWake,
            profile: profile, adaptationFactor: 1.0, completedNapsToday: 1
        )
        XCTAssertNotNil(plan)
        XCTAssertEqual(plan!.napsRemaining, 1)
        XCTAssertTrue(plan!.isLastNapBeforeBed)
        XCTAssertFalse(plan!.clampedToLimits, "11am wake with a 7pm target should fit without clamping.")

        // Last nap end + pre-bed window should land on the target bedtime.
        let preBedWW = Double(profile.window.typicalMinutes) * profile.preBedtimeFactor * 60
        let impliedBedtime = plan!.recommendedNapEnd.addingTimeInterval(preBedWW)
        XCTAssertEqual(impliedBedtime.timeIntervalSince(target), 0, accuracy: 90,
                       "Recommended last nap should end exactly one pre-bed window before bedtime.")
        XCTAssertTrue(plan!.bedtimeSweetSpot.contains(target))
    }

    func testClampsWhenBedtimeUnreachable() {
        // Target only ~30 min after waking → no room for nap + pre-bed window; must clamp.
        let lastWake = today(18, 0)
        let plan = BedtimePlanner.plan(
            targetBedtime: today(18, 30), now: today(18, 1), lastWake: lastWake,
            profile: profile, adaptationFactor: 1.0, completedNapsToday: 1
        )
        XCTAssertNotNil(plan)
        XCTAssertTrue(plan!.clampedToLimits)
        XCTAssertGreaterThanOrEqual(plan!.recommendedNapStart, lastWake.addingTimeInterval(Double(profile.window.lowMinutes) * 60),
                                    "Clamped nap must still respect the minimum wake window.")
    }

    func testNoPlanWhenNoNapsRemaining() {
        // 2 naps/day profile, already did 2.
        let plan = BedtimePlanner.plan(
            targetBedtime: today(19, 0), now: today(16, 0), lastWake: today(15, 0),
            profile: profile, adaptationFactor: 1.0, completedNapsToday: 2
        )
        XCTAssertNil(plan, "With no naps remaining there's nothing to plan.")
    }

    func testMultipleNapsSpaceBackFromBedtime() {
        let target = today(19, 0)
        let plan = BedtimePlanner.plan(
            targetBedtime: target, now: today(7, 5), lastWake: today(7, 0),
            profile: profile, adaptationFactor: 1.0, completedNapsToday: 0
        )
        XCTAssertNotNil(plan)
        XCTAssertEqual(plan!.napsRemaining, 2)
        XCTAssertFalse(plan!.isLastNapBeforeBed, "First of two remaining naps isn't the last before bed.")
        XCTAssertLessThan(plan!.recommendedNapStart, target)
    }
}
