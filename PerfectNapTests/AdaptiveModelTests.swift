import XCTest
import CoreData
@testable import PerfectNap

/// The per-baby adaptation engine (`AdaptiveModel`) multiplies into *every* prediction, so it must
/// learn the right direction, converge, stay bounded, resist outliers, and — critically — refuse to
/// learn from a forgotten-nap-sized wake window. These tests exercise those guarantees behaviorally
/// (direction, convergence, bounds, stability) rather than pinning the exact EMA constants.
final class AdaptiveModelTests: XCTestCase {
    private var container: NSPersistentContainer!
    private let cal = Calendar.current

    override func setUp() {
        super.setUp()
        container = NSPersistentContainer(name: "Test", managedObjectModel: CoreDataStack.model)
        let d = NSPersistentStoreDescription(); d.type = NSInMemoryStoreType
        container.persistentStoreDescriptions = [d]
        container.loadPersistentStores { _, e in if let e { fatalError("\(e)") } }
    }

    // 9-month-old: profile "8–10 months", typical window 180 min, high 240, naps/day 2.
    private func baby(ageDays: Int = 270, factor: Double = 1.0, confidence: Double = 0.0) -> Baby {
        let b = Baby.create(in: container.viewContext, name: "T",
                            birthDate: cal.date(byAdding: .day, value: -ageDays, to: .now)!)
        b.adaptationFactor = factor
        b.adaptationConfidence = confidence
        return b
    }

    /// A noon-anchored nap: previous sleep ended at `prevHour`, baby was awake `awakeMin`, then napped
    /// `durationMin`. Returns (prevEnd, the completed nap).
    private func scenario(prevHour: Int = 12, awakeMin: Double, durationMin: Double) -> (Date, NapSession) {
        let prevEnd = cal.date(bySettingHour: prevHour, minute: 0, second: 0, of: .now)!
        let start = prevEnd.addingTimeInterval(awakeMin * 60)
        let nap = NapSession.create(in: container.viewContext, startedAt: start,
                                    endedAt: start.addingTimeInterval(durationMin * 60), kind: .nap)
        return (prevEnd, nap)
    }

    @discardableResult
    private func applyOnce(_ b: Baby, prevHour: Int = 12, awakeMin: Double, durationMin: Double = 80,
                           napsToday: [NapSession] = []) -> (factor: Double, confidence: Double)? {
        let (prevEnd, nap) = scenario(prevHour: prevHour, awakeMin: awakeMin, durationMin: durationMin)
        let result = AdaptiveModel.update(baby: b, endingNap: nap, previousSleepEnd: prevEnd, napsToday: napsToday)
        if let result { b.adaptationFactor = result.factor; b.adaptationConfidence = result.confidence }
        return result
    }

    // MARK: - guards (no learning)

    func testNightSleepIsNotAnObservation() {
        let b = baby()
        let prevEnd = cal.date(bySettingHour: 7, minute: 0, second: 0, of: .now)!
        let night = NapSession.create(in: container.viewContext, startedAt: prevEnd.addingTimeInterval(3600),
                                      endedAt: prevEnd.addingTimeInterval(3 * 3600), kind: .night)
        XCTAssertNil(AdaptiveModel.update(baby: b, endingNap: night, previousSleepEnd: prevEnd, napsToday: []))
    }

    func testTooShortNapDoesNotMoveTheFactor() {
        let b = baby(factor: 1.05)
        let r = applyOnce(b, awakeMin: 200, durationMin: 15) // < 25 min
        XCTAssertEqual(r?.factor, 1.05, "A catnap under the quality floor isn't a learning signal.")
        XCTAssertEqual(r?.confidence, 0.0, "Confidence shouldn't grow on a non-observation.")
    }

    func testMissingPreviousSleepDoesNotMoveTheFactor() {
        let b = baby(factor: 1.1)
        let (_, nap) = scenario(awakeMin: 200, durationMin: 80)
        let r = AdaptiveModel.update(baby: b, endingNap: nap, previousSleepEnd: nil, napsToday: [])
        XCTAssertEqual(r?.factor, 1.1)
    }

    func testForgottenNapSizedWindowIsRejected() {
        // 9mo high window 240 × 1.5 = 360 plausibility ceiling. 8h awake almost certainly = a missed
        // nap, not a baby who tolerates 8h — learning from it would wrongly stretch the factor.
        let b = baby(factor: 1.0)
        let r = applyOnce(b, awakeMin: 480, durationMin: 80)
        XCTAssertEqual(r?.factor, 1.0, "An implausibly long window must not teach a longer factor.")
    }

    // MARK: - direction & convergence

    func testConvergesUpwardForConsistentlyLongWindows() {
        let b = baby(factor: 1.0)
        var last = 1.0
        for _ in 0..<8 {
            let f = applyOnce(b, awakeMin: 230, durationMin: 80)!.factor // 230 > typical 180
            XCTAssertGreaterThanOrEqual(f, last, "Each long-window observation nudges the factor up (monotone).")
            last = f
        }
        XCTAssertGreaterThan(last, 1.10, "After a week of long windows the baby reads as a longer-window baby.")
        XCTAssertLessThanOrEqual(last, AdaptiveModel.maximumFactor)
    }

    func testConvergesDownwardForConsistentlyShortWindows() {
        let b = baby(factor: 1.0)
        for _ in 0..<8 { applyOnce(b, awakeMin: 120, durationMin: 80) } // 120 < typical 180
        XCTAssertLessThan(b.adaptationFactor, 0.92)
        XCTAssertGreaterThanOrEqual(b.adaptationFactor, AdaptiveModel.minimumFactor)
    }

    // MARK: - bounds

    func testFactorNeverLeavesClinicalBounds() {
        let high = baby(factor: AdaptiveModel.maximumFactor)
        for _ in 0..<20 { applyOnce(high, awakeMin: 350, durationMin: 80) } // ratio pegged high
        XCTAssertLessThanOrEqual(high.adaptationFactor, AdaptiveModel.maximumFactor + 1e-9)

        let low = baby(factor: AdaptiveModel.minimumFactor)
        for _ in 0..<20 { applyOnce(low, awakeMin: 15.0, durationMin: 80) } // awakeMin>10 but tiny ratio
        XCTAssertGreaterThanOrEqual(low.adaptationFactor, AdaptiveModel.minimumFactor - 1e-9)
    }

    // MARK: - stability & confidence

    func testSingleOutlierMovesFactorOnlyModestly() {
        let b = baby(factor: 1.0)
        applyOnce(b, awakeMin: 350, durationMin: 80) // one extreme-but-plausible observation
        XCTAssertGreaterThan(b.adaptationFactor, 1.0)
        XCTAssertLessThan(b.adaptationFactor, 1.10, "One observation shouldn't yank the factor to the extreme.")
    }

    func testConfidenceGrowsAndSaturates() {
        let b = baby()
        for _ in 0..<40 { applyOnce(b, awakeMin: 200, durationMin: 80) }
        XCTAssertEqual(b.adaptationConfidence, 1.0, accuracy: 1e-6, "Confidence saturates at 1.0.")
    }

    func testLearningRateDecaysAsConfidenceGrows() {
        // Same observation moves a low-confidence baby more than a high-confidence one (EMA settles).
        let fresh = baby(factor: 1.0, confidence: 0.0)
        let seasoned = baby(factor: 1.0, confidence: 1.0)
        let dFresh = applyOnce(fresh, awakeMin: 230, durationMin: 80)!.factor - 1.0
        let dSeasoned = applyOnce(seasoned, awakeMin: 230, durationMin: 80)!.factor - 1.0
        XCTAssertGreaterThan(dFresh, dSeasoned, "Early naps should move the factor more than late ones.")
    }

    // MARK: - position awareness

    func testFirstMorningWindowUsesAShorterExpectedBaseline() {
        // Prev sleep ending pre-10am is treated as night → expected awake = typical × firstWindowFactor
        // (0.90 < 1.0). So the *same* awake time reads as a longer-than-expected window vs a midday one,
        // pushing the factor higher.
        let morning = baby(factor: 1.0)
        applyOnce(morning, prevHour: 7, awakeMin: 180, durationMin: 80)
        let midday = baby(factor: 1.0)
        applyOnce(midday, prevHour: 12, awakeMin: 180, durationMin: 80, napsToday: [])
        XCTAssertGreaterThan(morning.adaptationFactor, midday.adaptationFactor,
            "180 min awake exceeds the shorter morning baseline more than the midday one.")
    }
}
