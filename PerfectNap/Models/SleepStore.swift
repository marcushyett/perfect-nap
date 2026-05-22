import Foundation
import CoreData
import Observation
import WidgetKit

@MainActor
@Observable
final class SleepStore {
    private(set) var babies: [Baby] = []
    private(set) var baby: Baby?              // currently selected baby
    private(set) var activeSession: NapSession?
    private(set) var lastCompletedSleep: NapSession?
    private(set) var napsToday: [NapSession] = []
    private(set) var prediction: NapPrediction?
    private(set) var lastNightTotalSeconds: TimeInterval = 0
    /// Set when the wake window is implausibly long — likely an unlogged nap to backdate.
    private(set) var skippedNapInference: SkippedNapInference?

    private let context: NSManagedObjectContext
    nonisolated(unsafe) private var refreshTask: Task<Void, Never>?
    nonisolated(unsafe) private var debounceTask: Task<Void, Never>?
    private var lastSnapshot: SharedSnapshot?

    static let defaultBedtimeMinutes: Int = 19 * 60  // 7:00 PM

    init(context: NSManagedObjectContext) {
        self.context = context
        refresh()
        startTicking()
        NotificationCenter.default.addObserver(forName: .perfectNapStateChanged, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.scheduleRefresh() }
        }
        NotificationCenter.default.addObserver(forName: .NSPersistentStoreRemoteChange, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.scheduleRefresh() }
        }
    }

    deinit { refreshTask?.cancel(); debounceTask?.cancel() }

    /// Coalesce bursts of change notifications (CloudKit's initial sync fires many remote-change
    /// posts) into a single refresh, so the UI settles once instead of flickering through every
    /// intermediate merge state.
    private func scheduleRefresh() {
        debounceTask?.cancel()
        debounceTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            self?.refresh()
        }
    }

    // MARK: - Babies

    /// True if this baby was shared to us (lives in the shared store) rather than owned by us.
    func isShared(_ baby: Baby) -> Bool {
        baby.objectID.persistentStore == CoreDataStack.shared.sharedPersistentStore
    }

    func selectBaby(_ baby: Baby) {
        TrackingState.selectedBabyID = baby.id
        refresh()
    }

    /// Creates a new baby (bedtime optimisation on by default) and selects it.
    func addBaby(name: String, birthDate: Date) {
        let new = Baby.create(in: context, name: name.isEmpty ? "Baby" : name, birthDate: birthDate)
        new.targetBedtimeMinutes = Int64(SleepStore.defaultBedtimeMinutes)
        try? context.save()
        TrackingState.selectedBabyID = new.id
        refresh()
    }

    /// Removes a baby. An owned baby (and its naps) is deleted; a shared baby is left/purged locally.
    func removeBaby(_ baby: Baby) {
        let removedID = baby.id
        if isShared(baby) {
            // Don't delete the owner's record — just drop our local participation copy.
            context.delete(baby)
        } else {
            if let id = baby.id {
                let req = NapSession.fetchRequest()
                req.predicate = NSPredicate(format: "babyID == %@", id as NSUUID)
                for nap in (try? context.fetch(req)) ?? [] { context.delete(nap) }
            }
            context.delete(baby)
        }
        try? context.save()
        if TrackingState.selectedBabyID == removedID { TrackingState.selectedBabyID = nil }
        refresh()
    }

    // MARK: - Baby setup / settings

    /// First-run onboarding: create the first baby if none exists, else rename the selected one.
    func setupBaby(name: String, birthDate: Date) {
        if let existing = baby {
            existing.name = name
            existing.birthDate = birthDate
            try? context.save()
            refresh()
        } else {
            addBaby(name: name, birthDate: birthDate)
        }
    }

    func setTargetBedtime(minutesFromMidnight: Int) {
        guard let baby else { return }
        baby.targetBedtimeMinutes = Int64(max(0, minutesFromMidnight))
        try? context.save()
        refresh()
    }

    // MARK: - Nap actions (operate on the selected baby)

    func startNap(at date: Date = .now) {
        guard let babyID = baby?.id, activeSession == nil else { return }
        TrackingState.isPaused = false
        let kind = NapSession.classify(start: date)
        NapSession.create(in: context, startedAt: date, kind: kind, babyID: babyID)
        try? context.save()
        refresh()
    }

    /// Ends any active nap for the selected baby and stops its tracking until a new nap is started.
    func stopTracking(at date: Date = .now) {
        if let session = activeSession {
            session.endedAt = date
            try? context.save()
        }
        TrackingState.isPaused = true
        NapNotifier.shared.cancelAll()
        refresh()
    }

    func stopNap(at date: Date = .now) {
        guard let session = activeSession else { return }
        session.endedAt = date
        try? context.save()

        if let baby, session.kind == .nap {
            let prevEnd = previousSleepEnd(before: session)
            if let updated = AdaptiveModel.update(baby: baby, endingNap: session, previousSleepEnd: prevEnd, napsToday: napsToday) {
                baby.adaptationFactor = updated.factor
                baby.adaptationConfidence = updated.confidence
                try? context.save()
            }
        }
        refresh()
        NapNotifier.shared.scheduleNextNap(prediction: prediction, babyName: baby?.displayName ?? "Baby")
    }

    func adjustActiveStart(to date: Date) {
        guard let session = activeSession else { return }
        session.startedAt = date
        session.kind = NapSession.classify(start: date)
        try? context.save()
        refresh()
    }

    func updateSession(_ session: NapSession, start: Date, end: Date?, kind: SleepKind) {
        session.startedAt = start
        session.endedAt = end
        session.kind = kind
        try? context.save()
        refresh()
    }

    func delete(_ session: NapSession) {
        context.delete(session)
        try? context.save()
        refresh()
    }

    func addNap(start: Date, end: Date, kind: SleepKind? = nil) {
        guard end > start, let babyID = baby?.id else { return }
        NapSession.create(in: context, startedAt: start, endedAt: end, kind: kind ?? NapSession.classify(start: start), babyID: babyID)
        try? context.save()
        refresh()
    }

    @discardableResult
    func splitSession(_ session: NapSession, awakeStart: Date, awakeEnd: Date) -> Bool {
        guard let plan = SleepSplit.plan(start: session.start, end: session.endedAt, awakeStart: awakeStart, awakeEnd: awakeEnd) else { return false }
        NapSession.create(
            in: context,
            startedAt: plan.second.0,
            endedAt: plan.second.1,
            kind: NapSession.classify(start: plan.second.0),
            note: session.note ?? "",
            babyID: session.babyID
        )
        session.endedAt = plan.first.1
        session.kind = NapSession.classify(start: plan.first.0)
        try? context.save()
        refresh()
        return true
    }

    func resetBaby() {
        for object in (try? context.fetch(Baby.fetchRequest())) ?? [] { context.delete(object) }
        for object in (try? context.fetch(NapSession.fetchRequest())) ?? [] { context.delete(object) }
        try? context.save()
        TrackingState.selectedBabyID = nil
        NapLiveActivityManager.shared.endAll()
        NapNotifier.shared.cancelAll()
        refresh()
    }

    // MARK: - Refresh

    func refresh() {
        babies = fetchBabies()
        baby = resolveSelectedBaby()

        guard let babyID = baby?.id else {
            activeSession = nil; lastCompletedSleep = nil; napsToday = []
            prediction = nil; skippedNapInference = nil; lastNightTotalSeconds = 0
            writeSnapshotIfChanged()
            NapLiveActivityManager.shared.reconcile(babies: [], napping: [], selectedAwake: nil, selectedBabyName: "Baby")
            return
        }

        let activeReq = NapSession.fetchRequest()
        activeReq.predicate = NSPredicate(format: "endedAt == nil AND babyID == %@", babyID as NSUUID)
        activeReq.sortDescriptors = [NSSortDescriptor(key: "startedAt", ascending: false)]
        activeSession = (try? context.fetch(activeReq))?.first

        let completedReq = NapSession.fetchRequest()
        completedReq.predicate = NSPredicate(format: "endedAt != nil AND babyID == %@", babyID as NSUUID)
        completedReq.sortDescriptors = [NSSortDescriptor(key: "startedAt", ascending: false)]
        let completed = (try? context.fetch(completedReq)) ?? []
        lastCompletedSleep = completed.first

        let dayStart = Calendar.current.startOfDay(for: .now)
        napsToday = completed.filter { $0.start >= dayStart }
        lastNightTotalSeconds = computeLastNightTotal(completed: completed)

        if let baby, activeSession == nil, !TrackingState.isPaused {
            let predictor = NapPredictor(baby: baby)
            let newPrediction = predictor.predict(lastSleep: lastCompletedSleep, napsToday: napsToday, lastNightTotalSeconds: lastNightTotalSeconds)
            if prediction != newPrediction { prediction = newPrediction }  // skip no-op churn → no flicker
            let newInference = lastCompletedSleep?.endedAt.flatMap {
                SkippedNapDetector.detect(lastWake: $0, now: .now,
                    profile: WakeWindowTable.profile(forAgeDays: baby.ageInDays), adaptationFactor: baby.adaptationFactor)
            }
            if skippedNapInference != newInference { skippedNapInference = newInference }
        } else {
            if prediction != nil { prediction = nil }
            if skippedNapInference != nil { skippedNapInference = nil }
        }

        writeSnapshotIfChanged()
        reconcileLiveActivities()
    }

    private func fetchBabies() -> [Baby] {
        let req = Baby.fetchRequest()
        req.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: true)]
        return (try? context.fetch(req)) ?? []
    }

    private func resolveSelectedBaby() -> Baby? {
        if let sel = TrackingState.selectedBabyID, let match = babies.first(where: { $0.id == sel }) {
            return match
        }
        let first = babies.first
        TrackingState.selectedBabyID = first?.id
        return first
    }

    /// One napping Live Activity per baby with an active nap (capped); the wake-window activity
    /// shows for the selected baby only.
    private func reconcileLiveActivities() {
        var napping: [(babyID: UUID, name: String, start: Date, kind: SleepKind)] = []
        for b in babies {
            guard let id = b.id else { continue }
            let req = NapSession.fetchRequest()
            req.predicate = NSPredicate(format: "endedAt == nil AND babyID == %@", id as NSUUID)
            req.fetchLimit = 1
            if let active = (try? context.fetch(req))?.first {
                napping.append((id, b.displayName, active.start, active.kind))
            }
        }
        var selectedAwake: (nextNapAt: Date, lastEndedAt: Date?, latestNapAt: Date?)?
        if activeSession == nil, !TrackingState.isPaused, let prediction {
            selectedAwake = (prediction.recommendedStart, lastCompletedSleep?.endedAt, prediction.latestStart)
        }
        NapLiveActivityManager.shared.reconcile(
            babies: babies.compactMap(\.id),
            napping: napping,
            selectedAwake: selectedAwake.map { (baby?.id ?? UUID(), baby?.displayName ?? "Baby", $0.nextNapAt, $0.lastEndedAt, $0.latestNapAt) },
            selectedBabyName: baby?.displayName ?? "Baby"
        )
    }

    private func computeLastNightTotal(completed: [NapSession]) -> TimeInterval {
        guard let lastEnd = lastCompletedSleep?.endedAt else { return 0 }
        let earliest = lastEnd.addingTimeInterval(-18 * 3600)
        return completed
            .filter { $0.kind == .night && $0.start >= earliest && ($0.endedAt ?? lastEnd) <= lastEnd.addingTimeInterval(60) }
            .reduce(0.0) { $0 + $1.duration }
    }

    private func writeSnapshotIfChanged() {
        guard let baby else {
            if lastSnapshot != nil {
                SharedSnapshotStore.clear(); lastSnapshot = nil; WidgetCenter.shared.reloadAllTimelines()
            }
            return
        }
        let snapshot = SharedSnapshot(
            babyName: baby.displayName,
            ageDescription: baby.ageDescription,
            activeStartedAt: activeSession?.startedAt,
            activeKind: activeSession?.kind.rawValue,
            nextNapAt: prediction?.recommendedStart,
            earliestNapAt: prediction?.earliestStart,
            latestNapAt: prediction?.latestStart,
            napsTodayCount: napsToday.filter { $0.kind == .nap }.count,
            lastNapEndedAt: lastCompletedSleep?.endedAt,
            lastNapDurationMinutes: lastCompletedSleep?.durationMinutes ?? 0,
            generatedAt: lastSnapshot?.generatedAt ?? .now
        )
        if let prior = lastSnapshot, prior == snapshot { return }
        var stamped = snapshot
        stamped.generatedAt = .now
        SharedSnapshotStore.write(stamped)
        lastSnapshot = stamped
        WidgetCenter.shared.reloadAllTimelines()
    }

    private func previousSleepEnd(before session: NapSession) -> Date? {
        guard let babyID = session.babyID else { return nil }
        let req = NapSession.fetchRequest()
        req.predicate = NSPredicate(format: "endedAt != nil AND babyID == %@", babyID as NSUUID)
        req.sortDescriptors = [NSSortDescriptor(key: "startedAt", ascending: false)]
        let all = (try? context.fetch(req)) ?? []
        return all.first(where: { $0.objectID != session.objectID && $0.start < session.start })?.endedAt
    }

    private func startTicking() {
        refreshTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30))
                self?.refresh()
            }
        }
    }
}
