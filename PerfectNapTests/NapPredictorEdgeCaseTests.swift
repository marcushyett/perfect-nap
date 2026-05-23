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

    func testFreeTierPredictionIgnoresPersonalisation() {
        // A baby with a strong learned factor: Premium applies it; free tier (personalize:false) gives
        // a plain age-based window (baseline × position only).
        let now = Date.now
        let c = ctx()
        let b = baby(c, daysOld: 270)   // 8–10 months, typical 180, firstWindowFactor 0.90
        b.adaptationFactor = 1.25
        let end = now.addingTimeInterval(-30 * 60)
        let night = NapSession.create(in: c, startedAt: end.addingTimeInterval(-10 * 3600), endedAt: end, kind: .night)
        let pred = NapPredictor(baby: b, now: now)
        let premium = pred.predict(lastSleep: night, napsToday: [], personalize: true)!.usedWindowMinutes
        let free = pred.predict(lastSleep: night, napsToday: [], personalize: false)!.usedWindowMinutes
        XCTAssertLessThan(free, premium, "Free tier shouldn't apply the learned ×1.25 adaptation.")
        XCTAssertEqual(free, Int((180.0 * 0.90).rounded()), accuracy: 2, "Free = baseline × first-window factor only.")
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

    func testShortNightFactorIsGentleAndNeedsBased() {
        let now = Date.now
        let c = ctx()
        let b = baby(c, daysOld: 75)   // "2–3 months": night-need band 9–10h, typical 80, first-window ×0.90
        let end = now.addingTimeInterval(-30 * 60)
        let night = NapSession.create(in: c, startedAt: end.addingTimeInterval(-9 * 3600), endedAt: end, kind: .night)
        let pred = NapPredictor(baby: b, now: now)
        func window(_ nightHours: Double) -> Int {
            pred.predict(lastSleep: night, napsToday: [], lastNightTotalSeconds: nightHours * 3600)!.usedWindowMinutes
        }
        let full = window(9.0)   // exactly the needed baseline → no adjustment
        // The key requirement: losing an hour or two (feeds, normal variation) must NOT shorten the
        // first window — it should read as a normal night.
        XCTAssertEqual(window(8.0), full, "An hour short of need = normal night, no penalty.")
        XCTAssertEqual(window(7.0), full, "Two hours short (e.g. feeds) should still be treated as a full night.")
        // A genuinely short night nudges the first nap earlier, but only mildly (<12%).
        let short = window(5.0)   // 4h short → ×0.92
        XCTAssertLessThan(short, full, "A truly short night should pull the first nap a little earlier.")
        XCTAssertGreaterThan(Double(short), Double(full) * 0.88, "Even a 4h-short night should cut less than 12%.")
        // Under ~2h recorded ⇒ a forgotten/partial log, not a near-sleepless night → assume a full night.
        XCTAssertEqual(window(1.5), full, "An almost-empty (<2h) night reads as a full night, not a penalty.")
        // A long night lets the first window stretch a touch.
        XCTAssertGreaterThan(window(12.0), full, "A long night allows a slightly later first nap.")
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

    func testEarlyBedtimeTurnsSleepIntoNight() {
        // Bedtime 7pm: a sleep in the hour before it is an early night, not a late nap.
        let bedtime7pm = 19 * 60
        XCTAssertEqual(SleepKind.classify(start: at(18, 15), bedtimeMinutes: bedtime7pm), .night,
                       "Falling asleep 45 min before a 7pm bedtime = early night.")
        XCTAssertEqual(SleepKind.classify(start: at(16, 30), bedtimeMinutes: bedtime7pm), .nap,
                       "A 4:30pm sleep is still a daytime nap.")

        // Earlier bedtime (6pm) moves the night boundary earlier too.
        let bedtime6pm = 18 * 60
        XCTAssertEqual(SleepKind.classify(start: at(17, 30), bedtimeMinutes: bedtime6pm), .night,
                       "5:30pm with a 6pm bedtime = night.")
        XCTAssertEqual(SleepKind.classify(start: at(16, 30), bedtimeMinutes: bedtime6pm), .nap)
    }

    func testLaterBedtimeNeverPushesTheNightStartPast7pm() {
        // A late bedtime shouldn't make a 7:30pm sleep a "nap" — evening sleep is still night.
        XCTAssertEqual(SleepKind.classify(start: at(19, 30), bedtimeMinutes: 20 * 60 + 30), .night)
    }

    func testNoBedtimeFallsBackToDefaultThreshold() {
        XCTAssertEqual(SleepKind.classify(start: at(18, 15), bedtimeMinutes: 0), .nap, "No bedtime → 7pm default.")
        XCTAssertEqual(SleepKind.classify(start: at(19, 30), bedtimeMinutes: nil), .night)
    }

    func testNightWakingOnlyAfterNightSleepDuringTheNight() {
        // Woke from night sleep, and it's 2am → night waking (resettle, no nap).
        XCTAssertTrue(SleepKind.isNightWaking(lastSleepKind: .night, now: at(2, 0), bedtimeMinutes: nil))
        // Woke from night sleep, but it's 7am → morning, the day has started (not a night waking).
        XCTAssertFalse(SleepKind.isNightWaking(lastSleepKind: .night, now: at(7, 0), bedtimeMinutes: nil))
        // Woke from a nap → never a night waking, even at an odd hour.
        XCTAssertFalse(SleepKind.isNightWaking(lastSleepKind: .nap, now: at(2, 0), bedtimeMinutes: nil))
        // No prior sleep → not a night waking.
        XCTAssertFalse(SleepKind.isNightWaking(lastSleepKind: nil, now: at(2, 0), bedtimeMinutes: nil))
        // Early bedtime: woke at 6:30pm from an early night → still a night waking.
        XCTAssertTrue(SleepKind.isNightWaking(lastSleepKind: .night, now: at(18, 30), bedtimeMinutes: 19 * 60))
    }
}
