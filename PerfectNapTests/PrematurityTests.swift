import XCTest
import CoreData
@testable import PerfectNap

final class PrematurityTests: XCTestCase {
    private var container: NSPersistentContainer!
    override func setUp() {
        super.setUp()
        container = NSPersistentContainer(name: "Test", managedObjectModel: CoreDataStack.model)
        let d = NSPersistentStoreDescription(); d.type = NSInMemoryStoreType
        container.persistentStoreDescriptions = [d]
        container.loadPersistentStores { _, e in if let e { fatalError("\(e)") } }
    }
    private func baby(ageDays: Int, weeksEarly: Int) -> Baby {
        let b = Baby.create(in: container.viewContext, name: "T", birthDate: Calendar.current.date(byAdding: .day, value: -ageDays, to: .now)!)
        b.weeksPremature = Int64(weeksEarly)
        return b
    }

    func testCorrectedAgeSubtractsWeeksEarly() {
        let b = baby(ageDays: 180, weeksEarly: 8)
        XCTAssertEqual(b.adjustedAgeInDays, 180 - 56, accuracy: 1)
        XCTAssertLessThan(b.adjustedAgeInDays, b.ageInDays)
    }

    func testFullTermIsUnchanged() {
        let b = baby(ageDays: 180, weeksEarly: 0)
        XCTAssertEqual(b.adjustedAgeInDays, b.ageInDays)
    }

    func testCorrectionStopsAfterTwoYears() {
        let b = baby(ageDays: 800, weeksEarly: 8) // > 730 days
        XCTAssertEqual(b.adjustedAgeInDays, b.ageInDays, "No correction past ~2 years.")
    }

    func testPreemieUsesAYoungerProfile() {
        let preemie = baby(ageDays: 180, weeksEarly: 10)   // corrected ~110d
        let term = baby(ageDays: 180, weeksEarly: 0)
        let preemieProfile = WakeWindowTable.profile(forAgeDays: preemie.adjustedAgeInDays)
        let termProfile = WakeWindowTable.profile(forAgeDays: term.adjustedAgeInDays)
        XCTAssertLessThanOrEqual(preemieProfile.window.typicalMinutes, termProfile.window.typicalMinutes,
            "A preemie's corrected age should map to an equal-or-younger (shorter-window) profile.")
        XCTAssertNotEqual(preemieProfile.label, termProfile.label)
    }
}
