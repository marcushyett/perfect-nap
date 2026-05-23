#if DEBUG
import Foundation
import CoreData

/// Seeds a sample baby + recent sleep when the app is launched with `-seedSampleData`, so the home
/// screen can be exercised/screenshotted without tapping through onboarding (the simulator has no
/// tap automation here). DEBUG-only; never in the shipped app.
enum DebugSeed {
    @MainActor
    static func seedIfRequested(into ctx: NSManagedObjectContext) {
        guard ProcessInfo.processInfo.arguments.contains("-seedSampleData") else { return }
        guard ((try? ctx.count(for: Baby.fetchRequest())) ?? 0) == 0 else { return }

        let cal = Calendar.current
        let baby = Baby.create(in: ctx, name: "Rosie", birthDate: cal.date(byAdding: .month, value: -9, to: .now)!)
        baby.targetBedtimeMinutes = 19 * 60
        guard let id = baby.id else { return }

        // Anchored relative to "now" so the screenshot is sensible whatever the simulator clock says.
        func ago(_ hours: Double) -> Date { Date.now.addingTimeInterval(-hours * 3600) }
        // Last night (ended ~2.5h ago = morning wake), two naps earlier today, one ended ~1h ago.
        NapSession.create(in: ctx, startedAt: ago(13), endedAt: ago(2.5), kind: .night, babyID: id)
        NapSession.create(in: ctx, startedAt: ago(26), endedAt: ago(24.5), kind: .nap, babyID: id) // yesterday, for estimate history
        NapSession.create(in: ctx, startedAt: ago(2.0), endedAt: ago(1.0), kind: .nap, babyID: id)

        try? ctx.save()
        TrackingState.selectedBabyID = id
    }
}
#endif
