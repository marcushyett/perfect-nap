import XCTest
import CoreData
@testable import PerfectNap

/// Regression guard: the resettle suggestion (advice about the nap that just ended) must surface
/// whenever the baby is awake — including after the parent ends the nap via "Stop tracking", which
/// pauses next-nap reminders. A previous version gated resettle behind `!isPaused`, so ending a nap
/// that way silently hid it.
@MainActor
final class SleepStoreResettleTests: XCTestCase {
    private var container: NSPersistentContainer!

    override func setUp() {
        super.setUp()
        container = NSPersistentContainer(name: "Test", managedObjectModel: CoreDataStack.model)
        let d = NSPersistentStoreDescription(); d.type = NSInMemoryStoreType
        container.persistentStoreDescriptions = [d]
        container.loadPersistentStores { _, e in if let e { fatalError("\(e)") } }
        TrackingState.isPaused = false
        TrackingState.selectedBabyID = nil
    }

    override func tearDown() {
        TrackingState.isPaused = false
        TrackingState.selectedBabyID = nil
        super.tearDown()
    }

    /// 9-month-old (typical nap ~82 min): a 30-min nap that ended 5 min ago is short + inside the window.
    @discardableResult
    private func seedShortRecentNap() -> UUID {
        let ctx = container.viewContext
        let baby = Baby.create(in: ctx, name: "T", birthDate: Calendar.current.date(byAdding: .month, value: -9, to: .now)!)
        let id = baby.id!
        NapSession.create(in: ctx, startedAt: Date.now.addingTimeInterval(-13 * 3600),
                          endedAt: Date.now.addingTimeInterval(-3 * 3600), kind: .night, babyID: id)
        NapSession.create(in: ctx, startedAt: Date.now.addingTimeInterval(-35 * 60),
                          endedAt: Date.now.addingTimeInterval(-5 * 60), kind: .nap, babyID: id)
        try? ctx.save()
        return id
    }

    func testResettleShowsWhenAwakeAndTracking() {
        seedShortRecentNap()
        TrackingState.isPaused = false
        let store = SleepStore(context: container.viewContext)
        store.refresh()
        XCTAssertNotNil(store.resettle, "A short, recent nap should produce a resettle suggestion.")
    }

    func testResettleStillShowsWhenTrackingPaused() {
        seedShortRecentNap()
        TrackingState.isPaused = true
        let store = SleepStore(context: container.viewContext)
        store.refresh()
        XCTAssertNotNil(store.resettle, "Resettle must not be suppressed by the paused (Stop tracking) state.")
        XCTAssertNil(store.prediction, "Next-nap prediction stays suppressed while paused — only resettle shows.")
    }

    func testNoResettleForAFullLengthNap() {
        let ctx = container.viewContext
        let baby = Baby.create(in: ctx, name: "T", birthDate: Calendar.current.date(byAdding: .month, value: -9, to: .now)!)
        let id = baby.id!
        NapSession.create(in: ctx, startedAt: Date.now.addingTimeInterval(-95 * 60),
                          endedAt: Date.now.addingTimeInterval(-5 * 60), kind: .nap, babyID: id) // ~90 min, full
        try? ctx.save()
        let store = SleepStore(context: container.viewContext)
        store.refresh()
        XCTAssertNil(store.resettle, "A full-length nap shouldn't suggest resettling.")
    }
}
