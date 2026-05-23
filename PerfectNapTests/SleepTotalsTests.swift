import XCTest
@testable import PerfectNap

final class SleepTotalsTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)
    private func ago(_ h: Double) -> Date { now.addingTimeInterval(-h * 3600) }
    private func s(_ startH: Double, _ endH: Double, _ k: SleepKind) -> SleepTotals.Session {
        SleepTotals.Session(start: ago(startH), end: ago(endH), kind: k)
    }

    func testNightIsMostRecentNightAndDayIsNapsAfterIt() {
        // Night ended 3h ago (10h long); two naps since then.
        let sessions = [
            s(13, 3, .night),
            s(2.5, 1.5, .nap),
            s(1.0, 0.5, .nap),
        ]
        let (day, night) = SleepTotals.bases(sessions)
        XCTAssertEqual(night, 600, accuracy: 1, "Most recent night = 10h.")
        XCTAssertEqual(day, 90, accuracy: 1, "Two 1h/0.5h naps after the night = 90 min.")
    }

    func testDayPersistsPreviousDayUntilNewDayHasANap() {
        // Last night ended 1h ago; no naps since. Previous day had two naps. Should show previous day.
        let sessions = [
            s(38, 26, .night),   // previous night
            s(24, 23, .nap),     // previous day nap (1h)
            s(20, 19.5, .nap),   // previous day nap (0.5h)
            s(11, 1, .night),    // last night (ended 1h ago)
        ]
        let (day, night) = SleepTotals.bases(sessions)
        XCTAssertEqual(night, 600, accuracy: 1, "Most recent night = 10h.")
        XCTAssertEqual(day, 90, accuracy: 1, "No nap since last night → previous day's 90 min persists.")
    }
}
