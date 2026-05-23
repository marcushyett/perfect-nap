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
    /// Set in the morning when last night wasn't recorded — nudge to log it (we assume a baseline night).
    private(set) var missingNightInference: MissingNightInference?
    /// Set just after an early wake from a short nap — suggest resettling before the next window.
    private(set) var resettle: ResettleWindow?
    /// True when the baby has woken from night sleep but it's still night — they don't nap at night,
    /// so the UI shows a simple "resettle" (no nap timing) rather than a next-nap countdown.
    private(set) var isNightWaking: Bool = false
    /// Estimated length of the next/current nap (by time of day, with a confidence score). nil until
    /// there's at least a day of history.
    private(set) var estimatedNap: NapLengthEstimate?
    /// During an active nap: suggested time to wake to protect bedtime / day-sleep balance.
    private(set) var wakeSuggestion: WakeSuggestion?
    /// Gauge bases (completed): current day's nap minutes, most-recent night minutes. The view adds
    /// the live elapsed for an in-progress nap/night.
    private(set) var dayNapBaseMinutes: Double = 0
    private(set) var nightSleepBaseMinutes: Double = 0
    /// Projected remaining naps for the rest of today (for the timeline chart).
    private(set) var dayForecast: [ForecastNap] = []
    /// While napping: the projected end of the current nap (for the chart's live forecast tail).
    private(set) var activeNapProjectedEnd: Date?
    /// Set in the days around a daylight-saving change — drives the auto-adjust banner.
    private(set) var dstAdjustment: DSTAdjustment?
    /// Active travel trip (most recent, not stale), if any — drives the manual jet-lag flow.
    private(set) var trip: Trip?
    /// Current jet-lag easing for the active trip — drives the banner and the schedule shift.
    private(set) var jetLagPlan: JetLagPlan?

    /// Premium unlocks the smart features. True if this user subscribes (or is a complimentary
    /// tester/dev build), OR the selected baby was shared by a Premium owner (one sub per family).
    var isPremium: Bool {
        SubscriptionManager.shared.isPremium || (baby?.ownerHasPremium ?? false)
    }

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
    /// Free tier is limited to one baby; Premium unlocks multiple. (The first baby is always allowed.)
    var canAddBaby: Bool { isPremium || babies.isEmpty }

    func addBaby(name: String, birthDate: Date) {
        guard canAddBaby else { return }
        let new = Baby.create(in: context, name: name.isEmpty ? "Baby" : name, birthDate: birthDate)
        new.targetBedtimeMinutes = Int64(SleepStore.defaultBedtimeMinutes)
        new.ownerHasPremium = SubscriptionManager.shared.isPremium
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

    /// Weeks born before the due date — drives corrected age for prematurity.
    func setWeeksPremature(_ weeks: Int) {
        guard let baby else { return }
        baby.weeksPremature = Int64(max(0, min(weeks, 20)))
        try? context.save()
        refresh()
    }

    /// Set a custom nap schedule (nap start minutes-from-midnight); empty clears it (→ automatic).
    func setCustomSchedule(napMinutes: [Int]) {
        guard let baby else { return }
        baby.customNapMinutes = napMinutes.filter { $0 >= 0 && $0 < 1440 }
        try? context.save()
        refresh()
    }

    // MARK: - Travel / jet lag

    /// Start (or replace) a travel trip. Clears any previous trip so there's only one active at a time.
    func createTrip(originTZ: String, destinationTZ: String, departure: Date, arrival: Date,
                    returnDate: Date?, strategy: TripStrategy, alreadyLanded: Bool) {
        for existing in (try? context.fetch(Trip.fetchRequest())) ?? [] { context.delete(existing) }
        Trip.create(in: context, originTZ: originTZ, destinationTZ: destinationTZ,
                    departure: departure, arrival: arrival, returnDate: returnDate,
                    strategy: strategy, alreadyLanded: alreadyLanded)
        try? context.save()
        refresh()
    }

    func clearTrip() {
        for existing in (try? context.fetch(Trip.fetchRequest())) ?? [] { context.delete(existing) }
        try? context.save()
        refresh()
    }

    // MARK: - Nap actions (operate on the selected baby)

    func startNap(at date: Date = .now) {
        guard let babyID = baby?.id, activeSession == nil else { return }
        TrackingState.isPaused = false
        let kind = NapSession.classify(start: date, bedtimeMinutes: Int(baby?.targetBedtimeMinutes ?? 0))
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
        session.kind = NapSession.classify(start: date, bedtimeMinutes: Int(baby?.targetBedtimeMinutes ?? 0))
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
        NapSession.create(in: context, startedAt: start, endedAt: end, kind: kind ?? NapSession.classify(start: start, bedtimeMinutes: Int(baby?.targetBedtimeMinutes ?? 0)), babyID: babyID)
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
            prediction = nil; skippedNapInference = nil; missingNightInference = nil; lastNightTotalSeconds = 0; estimatedNap = nil; wakeSuggestion = nil; dayForecast = []; resettle = nil; activeNapProjectedEnd = nil; dstAdjustment = nil; trip = nil; jetLagPlan = nil; isNightWaking = false
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

        let sessions = completed.compactMap { s -> SleepTotals.Session? in
            guard let end = s.endedAt else { return nil }
            return SleepTotals.Session(start: s.start, end: end, kind: s.kind)
        }
        let bases = SleepTotals.bases(sessions)
        if dayNapBaseMinutes != bases.day { dayNapBaseMinutes = bases.day }
        if nightSleepBaseMinutes != bases.night { nightSleepBaseMinutes = bases.night }

        if let baby, activeSession == nil {
            let premium = isPremium
            // The owner mirrors their Premium status onto owned babies so a shared partner inherits
            // it (one subscription per family — travels through the CloudKit share).
            if !isShared(baby), baby.ownerHasPremium != SubscriptionManager.shared.isPremium {
                baby.ownerHasPremium = SubscriptionManager.shared.isPremium
                try? context.save()
            }

            // Resettle (Premium) — advice about the nap that just ended, independent of pause state.
            let newResettle = premium ? ResettleAdvisor.suggestion(
                lastNapEnd: lastCompletedSleep?.endedAt,
                lastNapMinutes: lastCompletedSleep.map { Double($0.durationMinutes) },
                lastNapKind: lastCompletedSleep?.kind,
                profile: WakeWindowTable.profile(forAgeDays: baby.adjustedAgeInDays),
                now: .now
            ) : nil
            if resettle != newResettle { resettle = newResettle }

            // Night waking: woke from night sleep while it's still night → simple resettle, no nap.
            var nightWaking = SleepKind.isNightWaking(
                lastSleepKind: lastCompletedSleep?.kind, now: .now,
                bedtimeMinutes: Int(baby.targetBedtimeMinutes))
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("-forceNightWaking") { nightWaking = true }
            #endif
            if isNightWaking != nightWaking { isNightWaking = nightWaking }

            if !TrackingState.isPaused {
                let predictor = NapPredictor(baby: baby)
                if premium {
                    let profile = WakeWindowTable.profile(forAgeDays: baby.adjustedAgeInDays)
                    let morningWake = computeMorningWake(completed: completed, profile: profile)
                    let custom = baby.customNapMinutes
                    var anchors: [Date]
                    if !custom.isEmpty {
                        let dayStart = Calendar.current.startOfDay(for: .now)
                        anchors = custom.map { dayStart.addingTimeInterval(Double($0) * 60) }
                    } else {
                        anchors = ScheduleLearner.anchors(
                            history: completed.map { (start: $0.start, kind: $0.kind) },
                            today: .now, morningWake: morningWake, profile: profile)
                    }
                    // Daylight-saving easing: nudge the whole schedule in the days around the change.
                    var dst = DSTAdjuster.current()
                    #if DEBUG
                    if ProcessInfo.processInfo.arguments.contains("-forceDST") {
                        dst = DSTAdjustment(shiftMinutes: -40, transitionDate: Calendar.current.date(byAdding: .day, value: 2, to: .now)!, springsForward: true)
                    }
                    #endif
                    if let dst { anchors = anchors.map { $0.addingTimeInterval(Double(dst.shiftMinutes) * 60) } }
                    if dstAdjustment != dst { dstAdjustment = dst }
                    // Manual jet-lag easing: shift the schedule toward the destination across the trip.
                    let activeTrip = fetchActiveTrip()
                    if trip !== activeTrip { trip = activeTrip }
                    let plan = activeTrip.flatMap { jetLagPlan(for: $0, baby: baby) }
                    if let plan { anchors = anchors.map { $0.addingTimeInterval(Double(plan.scheduleOffsetMinutes) * 60) } }
                    if jetLagPlan != plan { jetLagPlan = plan }
                    let newPrediction = predictor.predict(lastSleep: lastCompletedSleep, napsToday: napsToday, lastNightTotalSeconds: lastNightTotalSeconds, scheduleAnchors: anchors)
                    if prediction != newPrediction { prediction = newPrediction }  // skip no-op churn → no flicker
                } else {
                    // Free tier: a plain age-based countdown, with the smart schedule/travel features off.
                    if dstAdjustment != nil { dstAdjustment = nil }
                    if trip != nil { trip = nil }
                    if jetLagPlan != nil { jetLagPlan = nil }
                    let basic = predictor.predict(lastSleep: lastCompletedSleep, napsToday: napsToday, lastNightTotalSeconds: nil, scheduleAnchors: nil, personalize: false)
                    if prediction != basic { prediction = basic }
                }
                // Missing-night nudge: it's morning and last night wasn't recorded. Takes precedence
                // over the skipped-nap nudge — when both could fire, an unlogged night is the likelier
                // story (and avoids double-nudging).
                let profileForNudges = WakeWindowTable.profile(forAgeDays: baby.adjustedAgeInDays)
                var newMissingNight = MissingNightDetector.detect(
                    lastSleepKind: lastCompletedSleep?.kind, lastSleepEnd: lastCompletedSleep?.endedAt,
                    now: .now, profile: profileForNudges)
                #if DEBUG
                if ProcessInfo.processInfo.arguments.contains("-forceMissingNight"), newMissingNight == nil {
                    let band = profileForNudges.totalNightSleepHours
                    let h = (band.lowerBound + band.upperBound) / 2
                    newMissingNight = MissingNightInference(suggestedStart: Date.now.addingTimeInterval(-h * 3600), suggestedEnd: .now, assumedHours: h)
                }
                #endif
                if missingNightInference != newMissingNight { missingNightInference = newMissingNight }
                // Skipped-nap nudge is a basic safety net — available on the free tier too.
                let newInference = newMissingNight != nil ? nil : lastCompletedSleep?.endedAt.flatMap {
                    SkippedNapDetector.detect(lastWake: $0, now: .now,
                        profile: profileForNudges, adaptationFactor: baby.adaptationFactor)
                }
                if skippedNapInference != newInference { skippedNapInference = newInference }
            } else {
                if prediction != nil { prediction = nil }
                if skippedNapInference != nil { skippedNapInference = nil }
                if missingNightInference != nil { missingNightInference = nil }
            }
        } else {
            if prediction != nil { prediction = nil }
            if skippedNapInference != nil { skippedNapInference = nil }
            if missingNightInference != nil { missingNightInference = nil }
            if resettle != nil { resettle = nil }
            if isNightWaking { isNightWaking = false }
        }

        // Nap-length estimate, wake suggestion, and the day forecast are Premium insights.
        if let baby, isPremium {
            let history = completed.filter { $0.kind == .nap }.map { (start: $0.start, minutes: Double($0.durationMinutes)) }
            let targetStart = activeSession?.start ?? prediction?.recommendedStart ?? .now
            let est = NapLengthEstimator.estimate(
                naps: history, targetStart: targetStart, now: .now,
                profile: WakeWindowTable.profile(forAgeDays: baby.adjustedAgeInDays)
            )
            if estimatedNap != est { estimatedNap = est }
        } else if estimatedNap != nil { estimatedNap = nil }

        if isPremium, let baby, let active = activeSession, active.kind == .nap {
            let todaysNaps = napsToday.filter { $0.kind == .nap }
            let sug = NapCapPlanner.suggest(
                napStart: active.start,
                bedtime: baby.targetBedtime(on: .now),
                profile: WakeWindowTable.profile(forAgeDays: baby.adjustedAgeInDays),
                adaptationFactor: baby.adaptationFactor,
                completedNapMinutesToday: todaysNaps.reduce(0.0) { $0 + Double($1.durationMinutes) },
                completedNapsToday: todaysNaps.count
            )
            if wakeSuggestion != sug { wakeSuggestion = sug }
        } else if wakeSuggestion != nil {
            wakeSuggestion = nil
        }

        let forecast = isPremium ? computeForecast() : []
        if dayForecast != forecast { dayForecast = forecast }

        if let baby, let active = activeSession, active.kind == .nap {
            let napDur = Double(estimatedNap?.minutes ?? Int(BedtimePlanner.typicalNapMinutes(WakeWindowTable.profile(forAgeDays: baby.adjustedAgeInDays))))
            let projEnd = max(active.start.addingTimeInterval(napDur * 60), Date.now)
            if activeNapProjectedEnd != projEnd { activeNapProjectedEnd = projEnd }
        } else if activeNapProjectedEnd != nil {
            activeNapProjectedEnd = nil
        }

        writeSnapshotIfChanged()
        // Live Activities are a Premium feature — free tier doesn't drive the lock-screen timer.
        if isPremium { reconcileLiveActivities() } else { NapLiveActivityManager.shared.endAll() }
    }

    private func fetchBabies() -> [Baby] {
        let req = Baby.fetchRequest()
        req.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: true)]
        return (try? context.fetch(req)) ?? []
    }

    /// Most recent trip that isn't stale (household-wide; a trip applies to whoever's selected).
    private func fetchActiveTrip() -> Trip? {
        let req = Trip.fetchRequest()
        req.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: false)]
        let trips = (try? context.fetch(req)) ?? []
        return trips.first { !$0.isStale() }
    }

    private func jetLagPlan(for trip: Trip, baby: Baby) -> JetLagPlan? {
        guard let origin = trip.originTimeZone, let destination = trip.destinationTimeZone,
              let departure = trip.departureDate, let arrival = trip.arrivalDate else { return nil }
        return JetLagPlanner.plan(
            originTZ: origin, destinationTZ: destination,
            departure: departure, arrival: arrival, returnDate: trip.returnDate,
            strategy: trip.strategy, ageDays: baby.adjustedAgeInDays)
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

    /// Chains the wake-window → nap pattern forward from the next predicted nap to bedtime.
    private func computeForecast() -> [ForecastNap] {
        guard let baby else { return [] }
        let profile = WakeWindowTable.profile(forAgeDays: baby.adjustedAgeInDays)
        let adapt = min(max(baby.adaptationFactor, 0.75), 1.25)
        let napDur = Double(estimatedNap?.minutes ?? Int(BedtimePlanner.typicalNapMinutes(profile)))
        let wakeWW = prediction.map { Double($0.usedWindowMinutes) } ?? (Double(profile.window.typicalMinutes) * adapt)
        let typicalNaps = max(1, (profile.napsPerDay.lowerBound + profile.napsPerDay.upperBound) / 2)
        let completedNaps = napsToday.filter { $0.kind == .nap }.count
        let now = Date.now
        let bedtime = baby.targetBedtime(on: now)

        let firstStart: Date
        let remaining: Int
        if let active = activeSession, active.kind == .nap {
            let currentEnd = max(active.start.addingTimeInterval(napDur * 60), now)
            firstStart = currentEnd.addingTimeInterval(wakeWW * 60)
            remaining = max(0, typicalNaps - completedNaps - 1)
        } else if let prediction {
            firstStart = max(prediction.recommendedStart, now)
            remaining = max(0, typicalNaps - completedNaps)
        } else {
            return []
        }
        return DayForecast.naps(
            firstNapStart: firstStart, napDurationMinutes: napDur, wakeWindowMinutes: wakeWW,
            bedtime: bedtime, maxNaps: remaining
        )
    }

    /// Best estimate of this morning's wake (the schedule anchors hang off it): the most recent
    /// night sleep's end, else today's first nap minus a first wake window, else ~7am.
    private func computeMorningWake(completed: [NapSession], profile: AgeProfile) -> Date {
        let cal = Calendar.current
        let todayStart = cal.startOfDay(for: .now)
        if let lastNightEnd = completed.first(where: { $0.kind == .night })?.endedAt,
           lastNightEnd >= todayStart.addingTimeInterval(-6 * 3600) {
            return lastNightEnd
        }
        if let firstNapToday = completed.filter({ $0.kind == .nap && $0.start >= todayStart }).map({ $0.start }).min() {
            return firstNapToday.addingTimeInterval(-Double(profile.window.typicalMinutes) * profile.firstWindowFactor * 60)
        }
        return cal.date(bySettingHour: 7, minute: 0, second: 0, of: .now) ?? .now
    }

    private func computeLastNightTotal(completed: [NapSession]) -> TimeInterval {
        guard let lastEnd = lastCompletedSleep?.endedAt else { return 0 }
        let earliest = lastEnd.addingTimeInterval(-18 * 3600)
        let cutoff = lastEnd.addingTimeInterval(60)
        // Explicit loop (not a filter/reduce chain) — keeps Swift's type-checker fast and avoids the
        // "expression too complex to type-check in reasonable time" failures.
        var total: TimeInterval = 0
        for session in completed where session.kind == .night {
            let end = session.endedAt ?? lastEnd
            if session.start >= earliest && end <= cutoff { total += session.duration }
        }
        return total
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
