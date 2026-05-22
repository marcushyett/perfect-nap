import XCTest
import CoreData
@testable import PerfectNap

final class NapPredictorTests: XCTestCase {
    private func makeContext() -> NSManagedObjectContext {
        let container = NSPersistentContainer(name: "Test", managedObjectModel: CoreDataStack.model)
        let desc = NSPersistentStoreDescription()
        desc.type = NSInMemoryStoreType
        container.persistentStoreDescriptions = [desc]
        container.loadPersistentStores { _, error in if let error { fatalError("in-memory store: \(error)") } }
        return container.viewContext
    }

    private func baby(_ ctx: NSManagedObjectContext, monthsOld: Int) -> Baby {
        let birth = Calendar.current.date(byAdding: .month, value: -monthsOld, to: .now)!
        return Baby.create(in: ctx, name: "Test", birthDate: birth)
    }

    func testSyntheticPredictionWhenNoLastSleep() {
        let ctx = makeContext()
        let predictor = NapPredictor(baby: baby(ctx, monthsOld: 4))
        let prediction = predictor.predict(lastSleep: nil, napsToday: [])
        XCTAssertNotNil(prediction, "Predictor must return a fallback when no prior sleep exists.")
        XCTAssertTrue(prediction!.rationale.contains("No prior nap"))
        XCTAssertGreaterThan(prediction!.recommendedStart, .now)
    }

    func testAnchorsToLastSleepEndWhenAvailable() {
        let ctx = makeContext()
        let now = Date.now
        let endedAt = now.addingTimeInterval(-30 * 60)
        let session = NapSession.create(in: ctx, startedAt: endedAt.addingTimeInterval(-60 * 60), endedAt: endedAt, kind: .nap)
        let predictor = NapPredictor(baby: baby(ctx, monthsOld: 4), now: now)
        let prediction = predictor.predict(lastSleep: session, napsToday: [])
        XCTAssertNotNil(prediction)
        XCTAssertEqual(prediction!.basedOnNapEnd, endedAt)
        XCTAssertGreaterThan(prediction!.recommendedStart, endedAt)
    }

    func testReturnsOverdueWhenWakeWindowAlreadyPassed() {
        let ctx = makeContext()
        let now = Date.now
        let endedHoursAgo = now.addingTimeInterval(-6 * 3600)
        let session = NapSession.create(in: ctx, startedAt: endedHoursAgo.addingTimeInterval(-3600), endedAt: endedHoursAgo, kind: .nap)
        let predictor = NapPredictor(baby: baby(ctx, monthsOld: 4), now: now)
        let prediction = predictor.predict(lastSleep: session, napsToday: [])
        XCTAssertNotNil(prediction)
        XCTAssertTrue(prediction!.isOverdue, "A 6-hour-old wake should be flagged overdue at 4 months.")
    }

    func testShortNapShortensNextWindow() {
        let ctx = makeContext()
        let now = Date.now
        let endedAt = now.addingTimeInterval(-5 * 60)
        let shortNap = NapSession.create(in: ctx, startedAt: endedAt.addingTimeInterval(-20 * 60), endedAt: endedAt, kind: .nap)
        let normalNap = NapSession.create(in: ctx, startedAt: endedAt.addingTimeInterval(-60 * 60), endedAt: endedAt, kind: .nap)
        let p = NapPredictor(baby: baby(ctx, monthsOld: 4), now: now)
        let shortPrediction = p.predict(lastSleep: shortNap, napsToday: [])!
        let normalPrediction = p.predict(lastSleep: normalNap, napsToday: [])!
        XCTAssertLessThan(shortPrediction.usedWindowMinutes, normalPrediction.usedWindowMinutes,
                          "A <30 min nap should yield a shorter next wake window than a 60 min nap.")
    }
}
