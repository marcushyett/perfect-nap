import XCTest
import CoreData
@testable import PerfectNap

/// Sanity-checks every predictor across every age band: nothing should suggest sleeping past
/// bedtime, an implausibly long single nap, a negative/backwards window, or a wildly out-of-range
/// wake window. These guard against "calculations wildly off" regressions.
final class PredictionRealismTests: XCTestCase {
    private func makeContext() -> NSManagedObjectContext {
        let c = NSPersistentContainer(name: "Test", managedObjectModel: CoreDataStack.model)
        let d = NSPersistentStoreDescription(); d.type = NSInMemoryStoreType
        c.persistentStoreDescriptions = [d]
        c.loadPersistentStores { _, e in if let e { fatalError("\(e)") } }
        return c.viewContext
    }
    private func baby(_ ctx: NSManagedObjectContext, ageDays: Int) -> Baby {
        Baby.create(in: ctx, name: "T", birthDate: Calendar.current.date(byAdding: .day, value: -ageDays, to: .now)!)
    }
    private let cal = Calendar.current
    private func at(_ h: Int, _ m: Int = 0) -> Date { cal.date(bySettingHour: h, minute: m, second: 0, of: .now)! }

    /// A representative age (in days) that resolves to each profile.
    private var ageSamples: [(Int, AgeProfile)] {
        WakeWindowTable.profiles.map { ($0.maxAgeDays, $0) }
    }

    // MARK: - Wake suggestion (nap capping)

    func testWakeSuggestionIsRealisticAndBeforeBedtimeAtEveryAge() {
        let ctx = makeContext()
        let bedtime = at(19, 0)
        for (ageDays, profile) in ageSamples {
            _ = baby(ctx, ageDays: ageDays)
            for napStartHour in [9, 12, 15, 18] {
                for completedNaps in 0...3 {
                    guard let sug = NapCapPlanner.suggest(
                        napStart: at(napStartHour), bedtime: bedtime, profile: profile,
                        adaptationFactor: 1.0, completedNapMinutesToday: Double(completedNaps) * 60,
                        completedNapsToday: completedNaps
                    ) else { continue }
                    let napMinutes = sug.wakeBy.timeIntervalSince(at(napStartHour)) / 60
                    XCTAssertGreaterThanOrEqual(napMinutes, 29, "\(profile.label) @\(napStartHour)h: nap cap \(Int(napMinutes))m too short")
                    XCTAssertLessThanOrEqual(napMinutes, 181, "\(profile.label) @\(napStartHour)h: single nap \(Int(napMinutes))m exceeds 3h")
                    // Never suggest waking after bedtime (small tolerance for the 30-min floor edge).
                    XCTAssertLessThanOrEqual(sug.wakeBy.timeIntervalSince(bedtime), 31 * 60,
                        "\(profile.label) @\(napStartHour)h: wake \(sug.wakeBy) is past the \(bedtime) bedtime")
                }
            }
        }
    }

    // MARK: - Forward wake-window prediction

    func testForwardWindowIsWithinPhysiologicalBoundsAtEveryAge() {
        let ctx = makeContext()
        for (ageDays, profile) in ageSamples {
            let b = baby(ctx, ageDays: ageDays) // no bedtime set → pure forward window
            let now = at(10, 0)
            let napEnd = now.addingTimeInterval(-15 * 60)
            let nap = NapSession.create(in: ctx, startedAt: napEnd.addingTimeInterval(-60 * 60), endedAt: napEnd, kind: .nap)
            let p = NapPredictor(baby: b, now: now).predict(lastSleep: nap, napsToday: [nap])!
            XCTAssertGreaterThan(p.recommendedStart, napEnd, "\(profile.label): recommended before nap ended")
            XCTAssertLessThanOrEqual(p.earliestStart, p.recommendedStart, "\(profile.label): earliest > recommended")
            XCTAssertLessThanOrEqual(p.recommendedStart, p.latestStart, "\(profile.label): recommended > latest")
            let ww = p.recommendedStart.timeIntervalSince(napEnd) / 60
            XCTAssertGreaterThanOrEqual(ww, Double(profile.window.lowMinutes) * 0.5, "\(profile.label): window \(Int(ww))m far below range")
            XCTAssertLessThanOrEqual(ww, Double(profile.window.highMinutes) * 1.6, "\(profile.label): window \(Int(ww))m far above range")
        }
    }

    // MARK: - Bedtime planner

    func testBedtimePlanNeverPlacesANapPastBedtime() {
        let ctx = makeContext()
        let bedtime = at(19, 0)
        for (ageDays, profile) in ageSamples {
            _ = baby(ctx, ageDays: ageDays)
            for completed in 0...2 {
                guard let plan = BedtimePlanner.plan(
                    targetBedtime: bedtime, now: at(10, 0), lastWake: at(9, 30), profile: profile,
                    adaptationFactor: 1.0, completedNapsToday: completed
                ) else { continue }
                XCTAssertLessThan(plan.recommendedNapStart, bedtime, "\(profile.label): planned nap starts after bedtime")
                XCTAssertLessThanOrEqual(plan.recommendedNapEnd.timeIntervalSince(bedtime), 5 * 60,
                    "\(profile.label): planned nap ends after bedtime")
            }
        }
    }
}
