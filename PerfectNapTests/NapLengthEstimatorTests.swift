import XCTest
@testable import PerfectNap

final class NapLengthEstimatorTests: XCTestCase {
    private var profile: AgeProfile { WakeWindowTable.profile(forAgeDays: 270) } // ~9mo
    private let now = Date(timeIntervalSince1970: 1_700_000_000)
    private func hoursAgo(_ h: Double) -> Date { now.addingTimeInterval(-h * 3600) }

    func testNeedsAtLeastOneDayOfData() {
        // Only naps from the last few hours — not enough history yet.
        let naps = [(start: hoursAgo(1), minutes: 60.0), (start: hoursAgo(3), minutes: 70.0)]
        XCTAssertNil(NapLengthEstimator.estimate(naps: naps, targetStart: now, now: now, profile: profile))
    }

    func testEstimatesFromSameTimeOfDayHistory() {
        // Naps at the same time of day across the last 3 days, ~90 min each.
        let naps = [(hoursAgo(24), 90.0), (hoursAgo(48), 92.0), (hoursAgo(72), 88.0)].map { (start: $0.0, minutes: $0.1) }
        let est = NapLengthEstimator.estimate(naps: naps, targetStart: now, now: now, profile: profile)
        XCTAssertNotNil(est)
        XCTAssertEqual(est!.minutes, 90, "Weighted mean of same-time-of-day naps.")
        XCTAssertGreaterThan(est!.confidence, 0.5, "Several consistent same-time naps → solid confidence.")
    }

    func testTimeOfDayWeightingIgnoresFarOffNaps() {
        // Two ~60-min naps at the target time of day, plus one long nap 12h off (should be ignored).
        let naps = [(hoursAgo(24), 60.0), (hoursAgo(48), 60.0), (hoursAgo(36), 180.0)].map { (start: $0.0, minutes: $0.1) }
        let est = NapLengthEstimator.estimate(naps: naps, targetStart: now, now: now, profile: profile)
        XCTAssertNotNil(est)
        XCTAssertLessThan(est!.minutes, 90, "The 12h-off 3h nap shouldn't drag the estimate up.")
    }

    func testConfidenceLowerWhenInconsistent() {
        let consistent = [(hoursAgo(24), 90.0), (hoursAgo(48), 90.0), (hoursAgo(72), 90.0)].map { (start: $0.0, minutes: $0.1) }
        let scattered = [(hoursAgo(24), 40.0), (hoursAgo(48), 140.0), (hoursAgo(72), 60.0)].map { (start: $0.0, minutes: $0.1) }
        let a = NapLengthEstimator.estimate(naps: consistent, targetStart: now, now: now, profile: profile)!
        let b = NapLengthEstimator.estimate(naps: scattered, targetStart: now, now: now, profile: profile)!
        XCTAssertGreaterThan(a.confidence, b.confidence)
    }
}
