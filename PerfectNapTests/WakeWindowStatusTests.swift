import XCTest
@testable import PerfectNap

final class WakeWindowStatusTests: XCTestCase {
    private func prediction(earliest: Date, recommended: Date, latest: Date) -> NapPrediction {
        NapPrediction(
            recommendedStart: recommended,
            earliestStart: earliest,
            latestStart: latest,
            usedWindowMinutes: 120,
            baselineMinutes: 120,
            position: .middleOfDay,
            rationale: "test",
            basedOnNapEnd: earliest.addingTimeInterval(-3600)
        )
    }

    func testBuildingBeforeEarliest() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let p = prediction(earliest: now.addingTimeInterval(600), recommended: now.addingTimeInterval(1200), latest: now.addingTimeInterval(1800))
        XCTAssertEqual(p.status(at: now), .building)
        XCTAssertEqual(p.minutesOvertired(at: now), 0)
    }

    func testIdealWindowWithinRange() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let p = prediction(earliest: now.addingTimeInterval(-600), recommended: now, latest: now.addingTimeInterval(1200))
        XCTAssertEqual(p.status(at: now), .ideal)
        XCTAssertEqual(p.minutesOvertired(at: now), 0, "Not overtired while still inside the window.")
    }

    func testOvertiredPastLatest() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let p = prediction(earliest: now.addingTimeInterval(-3600), recommended: now.addingTimeInterval(-1800), latest: now.addingTimeInterval(-1200))
        XCTAssertEqual(p.status(at: now), .overtired)
        XCTAssertEqual(p.minutesOvertired(at: now), 20, "20 min past the latest window.")
    }

    func testNeverNegativeCountdown() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let p = prediction(earliest: now.addingTimeInterval(-100), recommended: now.addingTimeInterval(-100), latest: now.addingTimeInterval(100))
        XCTAssertEqual(p.minutesUntilRecommended(at: now), 0, "Past the recommended time shows 0, never a negative '-0'.")
    }
}
