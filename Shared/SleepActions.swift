import Foundation
import CoreData

extension Notification.Name {
    /// Posted whenever SleepActions mutates state from outside the SleepStore (App Intents).
    static let perfectNapStateChanged = Notification.Name("app.perfectnap.stateChanged")
}

/// Headless start/stop logic for App Intents (Lock Screen / Dynamic Island buttons), scoped to a
/// specific baby. Runs in the app's process and updates that baby's Live Activity directly.
@MainActor
enum SleepActions {
    private static var context: NSManagedObjectContext { CoreDataStack.shared.viewContext }

    private static func resolveBabyID(_ explicit: UUID?) -> UUID? {
        explicit ?? TrackingState.selectedBabyID ?? fetchFirstBaby(context: context)?.id
    }

    @discardableResult
    static func startNap(babyID explicitID: UUID? = nil, at date: Date = .now) async -> NapSession? {
        let ctx = context
        guard let babyID = resolveBabyID(explicitID) else { return nil }
        if let active = fetchActive(babyID: babyID, context: ctx) { return active }

        TrackingState.isPaused = false   // starting a nap resumes tracking (mirrors SleepStore.startNap)
        let baby = fetchBaby(id: babyID, context: ctx)
        let kind = NapSession.classify(start: date, bedtimeMinutes: Int(baby?.targetBedtimeMinutes ?? 0))
        let session = NapSession.create(in: ctx, startedAt: date, kind: kind, babyID: babyID, baby: baby)
        try? ctx.save()

        let name = baby?.displayName ?? "Baby"
        NapLiveActivityManager.shared.sync(babyID: babyID.uuidString, to: .napping(start: date, kind: kind), babyName: name)
        let cs = NapActivityAttributes.ContentState(phase: .napping, sessionStart: date, nextNapAt: nil, babyName: name, sleepKind: kind.rawValue)
        await RelayClient.napEvent(babyKey: babyID.uuidString, contentState: cs.relayDictionary, babyName: name)
        NotificationCenter.default.post(name: .perfectNapStateChanged, object: nil)
        return session
    }

    @discardableResult
    static func stopNap(babyID explicitID: UUID? = nil, at date: Date = .now) async -> NapSession? {
        let ctx = context
        guard let babyID = resolveBabyID(explicitID),
              let session = fetchActive(babyID: babyID, context: ctx) else { return nil }
        session.endedAt = date
        try? ctx.save()

        let baby = fetchBaby(id: babyID, context: ctx)
        if let baby, session.kind == .nap {
            let prevEnd = previousSleepEnd(before: session, babyID: babyID, context: ctx)
            let napsToday = fetchCompletedToday(babyID: babyID, context: ctx)
            if let updated = AdaptiveModel.update(baby: baby, endingNap: session, previousSleepEnd: prevEnd, napsToday: napsToday) {
                baby.adaptationFactor = updated.factor
                baby.adaptationConfidence = updated.confidence
                try? ctx.save()
            }
        }

        let name = baby?.displayName ?? "Baby"
        if let baby {
            let prediction = NapPredictor(baby: baby).predict(
                lastSleep: fetchLastCompleted(babyID: babyID, context: ctx),
                napsToday: fetchCompletedToday(babyID: babyID, context: ctx),
                lastNightTotalSeconds: totalNightSleepEndingAt(date, babyID: babyID, context: ctx)
            )
            if let prediction {
                NapLiveActivityManager.shared.sync(babyID: babyID.uuidString, to: .awake(nextNapAt: prediction.recommendedStart, lastEndedAt: date, latestNapAt: prediction.latestStart), babyName: name)
                let cs = NapActivityAttributes.ContentState(phase: .awake, sessionStart: nil, nextNapAt: prediction.recommendedStart, babyName: name, sleepKind: SleepKind.nap.rawValue, lastEndedAt: date, latestNapAt: prediction.latestStart)
                await RelayClient.napEvent(babyKey: babyID.uuidString, contentState: cs.relayDictionary, babyName: name)
            } else {
                NapLiveActivityManager.shared.sync(babyID: babyID.uuidString, to: .none, babyName: name)
            }
        }
        NotificationCenter.default.post(name: .perfectNapStateChanged, object: nil)
        return session
    }

    // MARK: - Helpers (baby-scoped)

    static func fetchActive(babyID: UUID, context: NSManagedObjectContext) -> NapSession? {
        let req = NapSession.fetchRequest()
        req.predicate = NSPredicate(format: "endedAt == nil AND babyID == %@", babyID as NSUUID)
        req.sortDescriptors = [NSSortDescriptor(key: "startedAt", ascending: false)]
        req.fetchLimit = 1
        return (try? context.fetch(req))?.first
    }

    static func fetchFirstBaby(context: NSManagedObjectContext) -> Baby? {
        let req = Baby.fetchRequest()
        req.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: true)]
        req.fetchLimit = 1
        return (try? context.fetch(req))?.first
    }

    static func fetchBaby(id: UUID, context: NSManagedObjectContext) -> Baby? {
        let req = Baby.fetchRequest()
        req.predicate = NSPredicate(format: "id == %@", id as NSUUID)
        req.fetchLimit = 1
        return (try? context.fetch(req))?.first
    }

    static func fetchLastCompleted(babyID: UUID, context: NSManagedObjectContext) -> NapSession? {
        let req = NapSession.fetchRequest()
        req.predicate = NSPredicate(format: "endedAt != nil AND babyID == %@", babyID as NSUUID)
        req.sortDescriptors = [NSSortDescriptor(key: "startedAt", ascending: false)]
        req.fetchLimit = 1
        return (try? context.fetch(req))?.first
    }

    static func fetchCompletedToday(babyID: UUID, context: NSManagedObjectContext) -> [NapSession] {
        let dayStart = Calendar.current.startOfDay(for: .now)
        let req = NapSession.fetchRequest()
        req.predicate = NSPredicate(format: "endedAt != nil AND babyID == %@ AND startedAt >= %@", babyID as NSUUID, dayStart as NSDate)
        req.sortDescriptors = [NSSortDescriptor(key: "startedAt", ascending: false)]
        return (try? context.fetch(req)) ?? []
    }

    static func previousSleepEnd(before session: NapSession, babyID: UUID, context: NSManagedObjectContext) -> Date? {
        let req = NapSession.fetchRequest()
        req.predicate = NSPredicate(format: "endedAt != nil AND babyID == %@", babyID as NSUUID)
        req.sortDescriptors = [NSSortDescriptor(key: "startedAt", ascending: false)]
        let all = (try? context.fetch(req)) ?? []
        return all.first(where: { $0.objectID != session.objectID && $0.start < session.start })?.endedAt
    }

    static func totalNightSleepEndingAt(_ reference: Date, babyID: UUID, context: NSManagedObjectContext) -> TimeInterval {
        let earliest = reference.addingTimeInterval(-18 * 3600)
        let req = NapSession.fetchRequest()
        req.predicate = NSPredicate(format: "endedAt != nil AND babyID == %@ AND startedAt >= %@", babyID as NSUUID, earliest as NSDate)
        req.sortDescriptors = [NSSortDescriptor(key: "startedAt", ascending: true)]
        return ((try? context.fetch(req)) ?? []).filter { $0.kind == .night }.reduce(0.0) { $0 + $1.duration }
    }
}
