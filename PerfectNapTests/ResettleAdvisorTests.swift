import XCTest
@testable import PerfectNap

final class ResettleAdvisorTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)
    private func profile(_ days: Int) -> AgeProfile { WakeWindowTable.profile(forAgeDays: days) }

    func testSuggestsResettleForAShortNapWithinWindow() {
        let p = profile(270) // 9mo
        let typical = BedtimePlanner.typicalNapMinutes(p)
        let shortNap = typical * 0.4
        let end = now.addingTimeInterval(-5 * 60) // woke 5 min ago
        let r = ResettleAdvisor.suggestion(lastNapEnd: end, lastNapMinutes: shortNap, lastNapKind: .nap, profile: p, now: now)
        XCTAssertNotNil(r)
        XCTAssertEqual(r?.napMinutes, Int(shortNap.rounded()))
        XCTAssertEqual(r?.until, end.addingTimeInterval(ResettleAdvisor.windowMinutes * 60))
    }

    func testNoResettleForAFullLengthNap() {
        let p = profile(270)
        let fullNap = BedtimePlanner.typicalNapMinutes(p) * 0.9
        let r = ResettleAdvisor.suggestion(lastNapEnd: now.addingTimeInterval(-60), lastNapMinutes: fullNap, lastNapKind: .nap, profile: p, now: now)
        XCTAssertNil(r, "A near-full nap shouldn't prompt resettling.")
    }

    func testNoResettleOnceWindowHasPassed() {
        let p = profile(270)
        let shortNap = BedtimePlanner.typicalNapMinutes(p) * 0.4
        // Woke 25 min ago; the 20-min resettle window has passed → back to normal prediction.
        let end = now.addingTimeInterval(-25 * 60)
        XCTAssertNil(ResettleAdvisor.suggestion(lastNapEnd: end, lastNapMinutes: shortNap, lastNapKind: .nap, profile: p, now: now))
    }

    func testIgnoresNightSleepAndMisTaps() {
        let p = profile(270)
        XCTAssertNil(ResettleAdvisor.suggestion(lastNapEnd: now.addingTimeInterval(-60), lastNapMinutes: 30, lastNapKind: .night, profile: p, now: now))
        XCTAssertNil(ResettleAdvisor.suggestion(lastNapEnd: now.addingTimeInterval(-60), lastNapMinutes: 3, lastNapKind: .nap, profile: p, now: now), "Sub-5-min mis-tap isn't a nap to resettle.")
    }

    /// The "short nap" threshold must be age-relative: the same 35-min nap is short for an older baby
    /// (long typical nap) but a normal/near-full nap for a young infant (short typical nap).
    func testShortNapThresholdIsAgeRelativeAcrossAllAges() {
        let end = now.addingTimeInterval(-60)
        for prof in WakeWindowTable.profiles {
            let typical = BedtimePlanner.typicalNapMinutes(prof)
            let clearlyShort = ResettleAdvisor.suggestion(lastNapEnd: end, lastNapMinutes: typical * 0.45, lastNapKind: .nap, profile: prof, now: now)
            let clearlyFull = ResettleAdvisor.suggestion(lastNapEnd: end, lastNapMinutes: typical * 0.95, lastNapKind: .nap, profile: prof, now: now)
            XCTAssertNotNil(clearlyShort, "\(prof.label): \(Int(typical * 0.45))m (<65% of \(Int(typical))m typical) should suggest resettle")
            XCTAssertNil(clearlyFull, "\(prof.label): \(Int(typical * 0.95))m (near-full) should not suggest resettle")
        }
    }
}
