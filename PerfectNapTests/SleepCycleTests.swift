import XCTest
import CoreData
@testable import PerfectNap

final class SleepCycleTests: XCTestCase {
    private let cal = Calendar.current
    private func at(_ h: Int, _ m: Int = 0) -> Date { cal.date(bySettingHour: h, minute: m, second: 0, of: .now)! }

    func testCycleLengthIncreasesWithAge() {
        let newborn = WakeWindowTable.profile(forAgeDays: 20).sleepCycleMinutes
        let infant = WakeWindowTable.profile(forAgeDays: 270).sleepCycleMinutes
        let toddler = WakeWindowTable.profile(forAgeDays: 600).sleepCycleMinutes
        let child = WakeWindowTable.profile(forAgeDays: 365 * 4).sleepCycleMinutes
        XCTAssertLessThan(newborn, infant)
        XCTAssertLessThan(infant, toddler)
        XCTAssertLessThan(toddler, child)
        XCTAssertEqual(newborn, 50)
        XCTAssertEqual(child, 85)
    }

    func testWakeSuggestionLandsOnACycleBoundaryAtEveryAge() {
        let bedtime = at(20, 0)
        for profile in WakeWindowTable.profiles {
            let cycle = Double(profile.sleepCycleMinutes)
            guard let sug = NapCapPlanner.suggest(
                napStart: at(9, 0), bedtime: bedtime, profile: profile,
                adaptationFactor: 1.0, completedNapMinutesToday: 0, completedNapsToday: 0
            ) else { continue }
            let napMinutes = (sug.wakeBy.timeIntervalSince(at(9, 0)) / 60).rounded()
            // Either a whole number of cycles, or the sub-one-cycle floor when little room remains.
            let remainder = napMinutes.truncatingRemainder(dividingBy: cycle)
            XCTAssertTrue(remainder < 1 || napMinutes <= cycle,
                "\(profile.label): wake \(Int(napMinutes))m not on a \(Int(cycle))m cycle boundary")
        }
    }

    func testLowConfidenceNapEstimateIsCycleAligned() {
        let profile = WakeWindowTable.profile(forAgeDays: 270) // cycle 55
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        // One nap >24h ago (passes the gate) but a single sample → low confidence → cycle-aligned.
        let naps = [(start: now.addingTimeInterval(-26 * 3600), minutes: 70.0)]
        let est = NapLengthEstimator.estimate(naps: naps, targetStart: now, now: now, profile: profile)
        XCTAssertNotNil(est)
        if let est, est.confidence < 0.5 {
            XCTAssertEqual(est.minutes % profile.sleepCycleMinutes, 0, "Low-confidence estimate should snap to a cycle multiple")
        }
    }
}
