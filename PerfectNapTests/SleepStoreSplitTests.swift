import XCTest
@testable import PerfectNap

final class SleepSplitTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_000_000)

    func testValidSplitProducesTwoAdjacentIntervals() {
        let end = start.addingTimeInterval(2 * 3600)
        let wokeAt = start.addingTimeInterval(45 * 60)
        let backAsleep = start.addingTimeInterval(60 * 60)
        let plan = SleepSplit.plan(start: start, end: end, awakeStart: wokeAt, awakeEnd: backAsleep)
        XCTAssertNotNil(plan)
        XCTAssertEqual(plan!.first.0, start)
        XCTAssertEqual(plan!.first.1, wokeAt)
        XCTAssertEqual(plan!.second.0, backAsleep)
        XCTAssertEqual(plan!.second.1, end)
    }

    func testRejectsInProgressSleep() {
        XCTAssertNil(SleepSplit.plan(start: start, end: nil,
                                     awakeStart: start.addingTimeInterval(600),
                                     awakeEnd: start.addingTimeInterval(1200)))
    }

    func testRejectsGapOutsideBounds() {
        let end = start.addingTimeInterval(3600)
        XCTAssertNil(SleepSplit.plan(start: start, end: end,
                                     awakeStart: start.addingTimeInterval(600),
                                     awakeEnd: end.addingTimeInterval(600)),
                     "awakeEnd past the sleep end must be rejected.")
    }

    func testRejectsInvertedGap() {
        let end = start.addingTimeInterval(3600)
        XCTAssertNil(SleepSplit.plan(start: start, end: end,
                                     awakeStart: start.addingTimeInterval(1800),
                                     awakeEnd: start.addingTimeInterval(900)),
                     "awakeEnd before awakeStart must be rejected.")
    }
}
