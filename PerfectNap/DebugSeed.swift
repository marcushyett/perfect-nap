#if DEBUG
import Foundation
import CoreData

/// Seeds a sample baby + recent sleep when the app is launched with `-seedSampleData`, so the home
/// screen can be exercised/screenshotted without tapping through onboarding (the simulator has no
/// tap automation here). DEBUG-only; never in the shipped app.
enum DebugSeed {
    @MainActor
    static func seedIfRequested(into ctx: NSManagedObjectContext) {
        let args = ProcessInfo.processInfo.arguments
        guard args.contains("-seedSampleData") else { return }
        guard ((try? ctx.count(for: Baby.fetchRequest())) ?? 0) == 0 else { return }

        let cal = Calendar.current
        // Age scenarios for the manual-test sweep.
        let (name, months): (String, Int) =
            args.contains("-seedNewborn") ? ("Wren", 0) :
            args.contains("-seedToddler") ? ("Max", 20) : ("Rosie", 9)
        let birth = months == 0
            ? cal.date(byAdding: .day, value: -21, to: .now)!   // 3-week newborn
            : cal.date(byAdding: .month, value: -months, to: .now)!
        let baby = Baby.create(in: ctx, name: name, birthDate: birth)
        baby.targetBedtimeMinutes = 19 * 60
        guard let id = baby.id else { return }

        // Anchored relative to "now" so the screenshot is sensible whatever the simulator clock says.
        func ago(_ hours: Double) -> Date { Date.now.addingTimeInterval(-hours * 3600) }
        // Last night (ended ~2.5h ago = morning wake) + a nap yesterday for estimate history.
        NapSession.create(in: ctx, startedAt: ago(13), endedAt: ago(2.5), kind: .night, babyID: id)
        NapSession.create(in: ctx, startedAt: ago(26), endedAt: ago(24.5), kind: .nap, babyID: id)

        if args.contains("-seedNapping") {
            // Currently napping (active session, started 40 min ago) → exercises the napping UI.
            NapSession.create(in: ctx, startedAt: ago(0.67), endedAt: nil, kind: .nap, babyID: id)
        } else if args.contains("-seedOvertired") {
            // Last nap ended ~7h ago → well past the window for any age → overtired state.
            NapSession.create(in: ctx, startedAt: ago(8), endedAt: ago(7), kind: .nap, babyID: id)
        } else if args.contains("-seedResettle") {
            // A short nap (~30 min) that ended ~6 min ago → should be inside the resettle window.
            NapSession.create(in: ctx, startedAt: ago(0.6), endedAt: ago(0.1), kind: .nap, babyID: id)
            // Simulates having ended the nap via "Stop tracking" (which pauses) — resettle must still show.
            if args.contains("-seedPaused") { TrackingState.isPaused = true }
        } else {
            NapSession.create(in: ctx, startedAt: ago(2.0), endedAt: ago(1.0), kind: .nap, babyID: id)
        }

        // Optional second baby to exercise the switcher / multi-baby UI.
        if args.contains("-seedSecondBaby") {
            let sib = Baby.create(in: ctx, name: "Theo", birthDate: cal.date(byAdding: .month, value: -4, to: .now)!)
            sib.targetBedtimeMinutes = 19 * 60
            if let sid = sib.id {
                NapSession.create(in: ctx, startedAt: ago(12), endedAt: ago(3), kind: .night, babyID: sid)
                NapSession.create(in: ctx, startedAt: ago(1.5), endedAt: ago(0.8), kind: .nap, babyID: sid)
            }
        }

        // Optional: seed an in-progress eastward trip so the jet-lag banner can be screenshotted.
        if ProcessInfo.processInfo.arguments.contains("-forceJetLag") {
            Trip.create(in: ctx,
                        originTZ: "America/Los_Angeles", destinationTZ: "Europe/London",
                        departure: ago(24), arrival: ago(22),
                        returnDate: Date.now.addingTimeInterval(11 * 86_400),
                        strategy: .adaptAfter, alreadyLanded: true)
        }

        try? ctx.save()
        TrackingState.selectedBabyID = id
    }
}
#endif
