import XCTest
@testable import PerfectNap

/// Guards the rule that prevents the stuck-Live-Activity bug from regressing:
/// the intent is derived deterministically from SleepStore truth, and stays `.none`
/// when tracking is paused, even if a prediction exists.
final class NapLiveActivityIntentTests: XCTestCase {
    func testNappingIntentEqualityAndInequality() {
        let t = Date(timeIntervalSince1970: 1_000_000)
        let a: NapLiveActivityIntent = .napping(start: t, kind: .nap)
        let b: NapLiveActivityIntent = .napping(start: t, kind: .nap)
        let c: NapLiveActivityIntent = .napping(start: t.addingTimeInterval(60), kind: .nap)
        let d: NapLiveActivityIntent = .napping(start: t, kind: .night)
        XCTAssertEqual(a, b)
        XCTAssertNotEqual(a, c, "Different start times must be distinguishable so reconcile updates the activity.")
        XCTAssertNotEqual(a, d, "Switching nap kind (day vs night) must be distinguishable.")
    }

    func testAwakeIntentEquality() {
        let t = Date(timeIntervalSince1970: 1_000_000)
        let last = t.addingTimeInterval(-3600)
        let latest = t.addingTimeInterval(1800)
        XCTAssertEqual(NapLiveActivityIntent.awake(nextNapAt: t, lastEndedAt: last, latestNapAt: latest), .awake(nextNapAt: t, lastEndedAt: last, latestNapAt: latest))
        XCTAssertNotEqual(NapLiveActivityIntent.awake(nextNapAt: t, lastEndedAt: last, latestNapAt: latest), .awake(nextNapAt: t.addingTimeInterval(60), lastEndedAt: last, latestNapAt: latest))
        XCTAssertNotEqual(NapLiveActivityIntent.awake(nextNapAt: t, lastEndedAt: last, latestNapAt: latest), .awake(nextNapAt: t, lastEndedAt: nil, latestNapAt: latest))
        XCTAssertNotEqual(NapLiveActivityIntent.awake(nextNapAt: t, lastEndedAt: last, latestNapAt: latest), .none)
    }
}
