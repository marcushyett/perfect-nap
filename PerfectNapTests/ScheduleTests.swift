import XCTest
@testable import PerfectNap

final class ScheduleTests: XCTestCase {
    private let cal = Calendar.current

    func testBlendWeightRampsWithAgeAndIsZeroUnderFourMonths() {
        XCTAssertEqual(ScheduleBlend.weight(adjustedAgeDays: 90), 0, "Under ~4mo → pure wake windows.")
        XCTAssertEqual(ScheduleBlend.weight(adjustedAgeDays: 120), 0, accuracy: 0.001)
        let mid = ScheduleBlend.weight(adjustedAgeDays: 195) // ~halfway 4→9mo
        XCTAssertGreaterThan(mid, 0)
        XCTAssertLessThan(mid, ScheduleBlend.maxWeight)
        XCTAssertEqual(ScheduleBlend.weight(adjustedAgeDays: 300), ScheduleBlend.maxWeight, accuracy: 0.001, "By ~9mo → capped weight.")
        XCTAssertLessThanOrEqual(ScheduleBlend.weight(adjustedAgeDays: 1000), ScheduleBlend.maxWeight, "Never exceeds the cap.")
    }

    func testLearnerAveragesConsistentHistory() {
        let profile = WakeWindowTable.profile(forAgeDays: 270)
        let today = cal.date(bySettingHour: 6, minute: 0, second: 0, of: .now)!
        var history: [(start: Date, kind: SleepKind)] = []
        // 5 prior days, naps at 09:30 and 14:00 each.
        for d in 1...5 {
            let day = cal.date(byAdding: .day, value: -d, to: today)!
            history.append((cal.date(bySettingHour: 9, minute: 30, second: 0, of: day)!, .nap))
            history.append((cal.date(bySettingHour: 14, minute: 0, second: 0, of: day)!, .nap))
        }
        let anchors = ScheduleLearner.anchors(history: history, today: today, morningWake: cal.date(bySettingHour: 7, minute: 0, second: 0, of: today)!, profile: profile)
        XCTAssertEqual(anchors.count, 2)
        XCTAssertEqual(cal.component(.hour, from: anchors[0]), 9)
        XCTAssertEqual(cal.component(.minute, from: anchors[0]), 30)
        XCTAssertEqual(cal.component(.hour, from: anchors[1]), 14)
    }

    func testLearnerFallsBackToGenericWithSparseHistory() {
        let profile = WakeWindowTable.profile(forAgeDays: 270)
        let today = cal.date(bySettingHour: 6, minute: 0, second: 0, of: .now)!
        let morningWake = cal.date(bySettingHour: 7, minute: 0, second: 0, of: today)!
        // Only one prior day → below minDays → generic anchors.
        let history: [(start: Date, kind: SleepKind)] = [(cal.date(byAdding: .day, value: -1, to: today)!, .nap)]
        let anchors = ScheduleLearner.anchors(history: history, today: today, morningWake: morningWake, profile: profile)
        XCTAssertFalse(anchors.isEmpty)
        XCTAssertGreaterThan(anchors[0], morningWake, "Generic first nap is a wake window after morning wake.")
    }
}
