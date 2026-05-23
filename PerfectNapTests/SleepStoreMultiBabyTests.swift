import XCTest
import CoreData
@testable import PerfectNap

/// Multi-baby data isolation is the robustness foundation under both the baby switcher and CloudKit
/// sharing: every nap carries a `babyID`, and the selected baby's view (naps, last sleep, active
/// session, prediction) must contain *only* that baby's data. A leak here would cross-contaminate two
/// children's sleep — the worst kind of bug in this app. (`SharingCoordinator` itself is thin CloudKit
/// glue with no testable pure logic, so the meaningful automated coverage lives here.)
@MainActor
final class SleepStoreMultiBabyTests: XCTestCase {
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

    private func makeBaby(_ name: String, ageMonths: Int) -> Baby {
        Baby.create(in: container.viewContext, name: name,
                    birthDate: Calendar.current.date(byAdding: .month, value: -ageMonths, to: .now)!)
    }

    private func addNap(_ babyID: UUID, startHoursAgo: Double, durationMin: Double, active: Bool = false) {
        // Clamp into "today" so napsToday-based assertions don't flake when the suite runs just after
        // midnight (where "N hours ago" would land on the previous calendar day and drop out of napsToday).
        let dayStart = Calendar.current.startOfDay(for: .now)
        let start = max(Date.now.addingTimeInterval(-startHoursAgo * 3600), dayStart.addingTimeInterval(60))
        NapSession.create(in: container.viewContext, startedAt: start,
                          endedAt: active ? nil : start.addingTimeInterval(durationMin * 60),
                          kind: .nap, babyID: babyID)
    }

    func testSelectedBabysViewExcludesOtherBabysNaps() {
        let a = makeBaby("Rosie", ageMonths: 9); let aID = a.id!
        let b = makeBaby("Theo", ageMonths: 4); let bID = b.id!
        addNap(aID, startHoursAgo: 2, durationMin: 60)
        addNap(aID, startHoursAgo: 5, durationMin: 45)
        addNap(bID, startHoursAgo: 3, durationMin: 90)
        try? container.viewContext.save()

        let store = SleepStore(context: container.viewContext)
        store.selectBaby(a)
        XCTAssertEqual(store.baby?.id, aID)
        XCTAssertEqual(store.napsToday.count, 2, "Rosie's view should show only Rosie's two naps.")
        XCTAssertTrue(store.napsToday.allSatisfy { $0.babyID == aID }, "No Theo naps may leak in.")

        store.selectBaby(b)
        XCTAssertEqual(store.baby?.id, bID)
        XCTAssertEqual(store.napsToday.count, 1, "Theo's view should show only Theo's nap.")
        XCTAssertTrue(store.napsToday.allSatisfy { $0.babyID == bID })
    }

    func testActiveNapDoesNotLeakAcrossBabies() {
        let a = makeBaby("Rosie", ageMonths: 9); let aID = a.id!
        let b = makeBaby("Theo", ageMonths: 9)
        addNap(aID, startHoursAgo: 0.5, durationMin: 0, active: true) // Rosie is napping now
        try? container.viewContext.save()

        let store = SleepStore(context: container.viewContext)
        store.selectBaby(a)
        XCTAssertNotNil(store.activeSession, "Rosie should read as napping.")
        store.selectBaby(b)
        XCTAssertNil(store.activeSession, "Theo is not napping just because Rosie is.")
    }

    func testLastCompletedSleepIsPerBaby() {
        let a = makeBaby("Rosie", ageMonths: 9); let aID = a.id!
        let b = makeBaby("Theo", ageMonths: 9); let bID = b.id!
        addNap(aID, startHoursAgo: 1, durationMin: 40)   // Rosie's most recent
        addNap(bID, startHoursAgo: 6, durationMin: 80)   // Theo's most recent (older clock time)
        try? container.viewContext.save()

        let store = SleepStore(context: container.viewContext)
        store.selectBaby(a)
        XCTAssertEqual(store.lastCompletedSleep?.babyID, aID)
        store.selectBaby(b)
        XCTAssertEqual(store.lastCompletedSleep?.babyID, bID)
    }

    func testPredictionUsesOnlyTheSelectedBabysHistory() {
        // Two same-age babies; one has lots of day sleep banked, the other none. Their predictions
        // must differ — proving the predictor sees only the selected baby's naps.
        let heavy = makeBaby("Heavy", ageMonths: 9); let heavyID = heavy.id!
        let light = makeBaby("Light", ageMonths: 9); let lightID = light.id!
        for h in stride(from: 2.0, through: 8.0, by: 2.0) { addNap(heavyID, startHoursAgo: h, durationMin: 120) }
        addNap(lightID, startHoursAgo: 2, durationMin: 30)
        try? container.viewContext.save()

        let store = SleepStore(context: container.viewContext)
        store.selectBaby(heavy)
        let heavyPrediction = store.prediction
        store.selectBaby(light)
        let lightPrediction = store.prediction
        XCTAssertNotNil(heavyPrediction); XCTAssertNotNil(lightPrediction)
        XCTAssertNotEqual(heavyPrediction, lightPrediction,
            "Different per-baby histories must yield different predictions (no shared state).")
    }

    func testAddBabySelectsItAndStartsEmpty() {
        let store = SleepStore(context: container.viewContext)
        store.addBaby(name: "Nia", birthDate: Calendar.current.date(byAdding: .month, value: -6, to: .now)!)
        XCTAssertEqual(store.baby?.displayName, "Nia")
        XCTAssertTrue(store.napsToday.isEmpty)
        XCTAssertEqual(store.babies.count, 1)
    }

    func testRemoveOwnedBabyDeletesItAndItsNaps() {
        let a = makeBaby("Rosie", ageMonths: 9); let aID = a.id!
        let b = makeBaby("Theo", ageMonths: 9)
        addNap(aID, startHoursAgo: 2, durationMin: 60)
        addNap(aID, startHoursAgo: 5, durationMin: 60)
        try? container.viewContext.save()

        let store = SleepStore(context: container.viewContext)
        store.selectBaby(a)
        store.removeBaby(a)

        XCTAssertEqual(store.babies.count, 1, "Only Theo remains.")
        XCTAssertNotEqual(store.baby?.id, aID, "Selection falls away from the removed baby.")
        let orphanReq = NapSession.fetchRequest()
        orphanReq.predicate = NSPredicate(format: "babyID == %@", aID as NSUUID)
        let orphans = (try? container.viewContext.fetch(orphanReq)) ?? []
        XCTAssertTrue(orphans.isEmpty, "Removing an owned baby must delete its naps (no orphans).")
        _ = b
    }
}
