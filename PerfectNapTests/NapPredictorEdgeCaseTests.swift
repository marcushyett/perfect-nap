import XCTest
import CoreData
@testable import PerfectNap

/// Edge cases the main NapPredictorTests don't cover: a brand-new newborn with no history, continuity
/// across an age-band boundary, and the first-window-of-day shape. These complement the per-age sweep
/// in PredictionRealismTests with targeted contracts.
final class NapPredictorEdgeCaseTests: XCTestCase {
    private func ctx() -> NSManagedObjectContext {
        let c = NSPersistentContainer(name: "Test", managedObjectModel: CoreDataStack.model)
        let d = NSPersistentStoreDescription(); d.type = NSInMemoryStoreType
        c.persistentStoreDescriptions = [d]
        c.loadPersistentStores { _, e in if let e { fatalError("\(e)") } }
        return c.viewContext
    }
    private func baby(_ c: NSManagedObjectContext, daysOld: Int) -> Baby {
        Baby.create(in: c, name: "T", birthDate: Calendar.current.date(byAdding: .day, value: -daysOld, to: .now)!)
    }

    func testNewbornColdStartGivesAShortRealisticWindow() {
        let now = Date.now
        let predictor = NapPredictor(baby: baby(ctx(), daysOld: 5), now: now)
        let p = predictor.predict(lastSleep: nil, napsToday: [])
        XCTAssertNotNil(p)
        XCTAssertGreaterThan(p!.recommendedStart, now)
        let mins = p!.recommendedStart.timeIntervalSince(now) / 60
        XCTAssertTrue((20...75).contains(mins), "Newborn cold-start window should be short (~30–60 min), got \(mins).")
    }

    func testNoAbsurdJumpAcrossAnAgeBandBoundary() {
        // 89d ("2–3 months") vs 91d ("3–4 months"). Anchor from a night wake (isolates the position
        // factor + baseline step from nap-quality noise). The step should be gradual, not a cliff.
        func morningWindow(daysOld: Int) -> Double {
            let context = ctx()   // hold the context strongly (the MOC back-reference is weak)
            let now = Date.now
            let nightEnd = now.addingTimeInterval(-30 * 60)
            let night = NapSession.create(in: context, startedAt: nightEnd.addingTimeInterval(-10 * 3600),
                                          endedAt: nightEnd, kind: .night)
            let pred = NapPredictor(baby: baby(context, daysOld: daysOld), now: now)
            return Double(pred.predict(lastSleep: night, napsToday: [])!.usedWindowMinutes)
        }
        let younger = morningWindow(daysOld: 89)
        let older = morningWindow(daysOld: 91)
        let ratio = older / younger
        XCTAssertTrue((0.6...1.6).contains(ratio), "Window jumped \(ratio)× across the 90-day boundary — too abrupt.")
    }

    func testFirstWakeWindowIsShorterThanMiddayForAMultiNapBaby() {
        let now = Date.now
        let end = now.addingTimeInterval(-30 * 60)
        let c = ctx()
        // First-of-day: anchored on a night wake.
        let night = NapSession.create(in: c, startedAt: end.addingTimeInterval(-10 * 3600), endedAt: end, kind: .night)
        let firstWindow = NapPredictor(baby: baby(c, daysOld: 180), now: now)
            .predict(lastSleep: night, napsToday: [])!.usedWindowMinutes
        // Midday: anchored on an age-typical-length nap (so nap-quality ≈ 1.0).
        let c2 = ctx()
        let nap = NapSession.create(in: c2, startedAt: end.addingTimeInterval(-70 * 60), endedAt: end, kind: .nap)
        let middayWindow = NapPredictor(baby: baby(c2, daysOld: 180), now: now)
            .predict(lastSleep: nap, napsToday: [])!.usedWindowMinutes
        XCTAssertLessThan(firstWindow, middayWindow,
            "A 6-month-old's first wake window should be shorter than the midday one.")
    }
}

final class SleepKindTests: XCTestCase {
    private func at(_ hour: Int, _ minute: Int = 0) -> Date {
        Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: .now)!
    }

    func testNightThresholdBoundaries() {
        // Night = 19:00 (inclusive) through 04:59; daytime nap = 05:00 through 18:59.
        XCTAssertEqual(SleepKind.classify(start: at(18, 59)), .nap, "18:59 is still a nap.")
        XCTAssertEqual(SleepKind.classify(start: at(19, 0)), .night, "19:00 flips to night.")
        XCTAssertEqual(SleepKind.classify(start: at(23, 30)), .night)
        XCTAssertEqual(SleepKind.classify(start: at(0, 0)), .night, "Midnight is night.")
        XCTAssertEqual(SleepKind.classify(start: at(4, 59)), .night, "Pre-dawn is night.")
        XCTAssertEqual(SleepKind.classify(start: at(5, 0)), .nap, "05:00 is the morning — a nap.")
        XCTAssertEqual(SleepKind.classify(start: at(12, 0)), .nap)
    }
}
