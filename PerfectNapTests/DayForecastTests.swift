import XCTest
@testable import PerfectNap

final class DayForecastTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    func testChainsNapsAndStopsAtBedtime() {
        // cycle = 60m nap + 120m wake = 3h. Bedtime 6h out → naps at 0h and 3h; the 6h one is stopped.
        let naps = DayForecast.naps(
            firstNapStart: now, napDurationMinutes: 60, wakeWindowMinutes: 120,
            bedtime: now.addingTimeInterval(6 * 3600), maxNaps: 5
        )
        XCTAssertEqual(naps.count, 2)
        XCTAssertEqual(naps[0].start, now)
        XCTAssertEqual(naps[1].start.timeIntervalSince(now), 3 * 3600, accuracy: 1)
    }

    func testUncertaintyGrowsWithEachNap() {
        let naps = DayForecast.naps(
            firstNapStart: now, napDurationMinutes: 45, wakeWindowMinutes: 60,
            bedtime: nil, maxNaps: 3
        )
        XCTAssertEqual(naps.count, 3, "No bedtime → capped only by maxNaps.")
        XCTAssertLessThan(naps[0].startUncertaintyMinutes, naps[1].startUncertaintyMinutes)
        XCTAssertLessThan(naps[1].startUncertaintyMinutes, naps[2].startUncertaintyMinutes)
    }

    func testEmptyWhenNoNapsRemain() {
        XCTAssertTrue(DayForecast.naps(firstNapStart: now, napDurationMinutes: 60, wakeWindowMinutes: 120, bedtime: nil, maxNaps: 0).isEmpty)
    }
}
