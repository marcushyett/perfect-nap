import XCTest
@testable import PerfectNap

final class NapLengthEstimatorTests: XCTestCase {
    private var profile: AgeProfile { WakeWindowTable.profile(forAgeDays: 270) } // ~9mo

    func testFallsBackToAgeTypicalWithNoData() {
        let ageTypical = Int(BedtimePlanner.typicalNapMinutes(profile).rounded())
        XCTAssertEqual(NapLengthEstimator.estimate(recentNapMinutes: [], profile: profile), ageTypical)
    }

    func testLeansTowardRecentNaps() {
        let ageTypical = BedtimePlanner.typicalNapMinutes(profile)
        // Consistently long naps should pull the estimate above the age baseline.
        let est = NapLengthEstimator.estimate(recentNapMinutes: [120, 115, 125, 118, 122, 119], profile: profile)
        XCTAssertGreaterThan(Double(est), ageTypical)
        XCTAssertLessThanOrEqual(est, 125)
    }

    func testIgnoresCatnaps() {
        // A handful of <15-min false starts shouldn't drag the estimate down to ~5 min.
        let est = NapLengthEstimator.estimate(recentNapMinutes: [5, 4, 6], profile: profile)
        XCTAssertEqual(est, Int(BedtimePlanner.typicalNapMinutes(profile).rounded()),
                       "All-catnap input is ignored → age typical.")
    }
}
