import Foundation
import SwiftData
import Observation
import WidgetKit

@MainActor
@Observable
final class SleepStore {
    private(set) var baby: Baby?
    private(set) var activeSession: NapSession?
    private(set) var lastCompletedSleep: NapSession?
    private(set) var napsToday: [NapSession] = []
    private(set) var prediction: NapPrediction?
    private(set) var lastNightTotalSeconds: TimeInterval = 0

    private let context: ModelContext
    nonisolated(unsafe) private var refreshTask: Task<Void, Never>?
    private var lastSnapshot: SharedSnapshot?

    init(context: ModelContext) {
        self.context = context
        refresh()
        startTicking()
        NotificationCenter.default.addObserver(
            forName: .perfectNapStateChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    deinit {
        refreshTask?.cancel()
    }

    // MARK: - Public actions

    func setupBaby(name: String, birthDate: Date) {
        if let existing = baby {
            existing.name = name
            existing.birthDate = birthDate
        } else {
            let new = Baby(name: name, birthDate: birthDate)
            context.insert(new)
        }
        try? context.save()
        refresh()
    }

    func startNap(at date: Date = .now) {
        guard activeSession == nil else { return }
        let kind = NapSession.classify(start: date)
        let session = NapSession(startedAt: date, kind: kind)
        context.insert(session)
        try? context.save()
        refresh()
        NapLiveActivityManager.shared.startNapActivity(
            babyName: baby?.name ?? "Baby",
            startedAt: date,
            kind: kind
        )
    }

    func stopNap(at date: Date = .now) {
        guard let session = activeSession else { return }
        session.endedAt = date
        try? context.save()

        if let baby, session.kind == .nap {
            let prevEnd = previousSleepEnd(before: session)
            if let updated = AdaptiveModel.update(
                baby: baby,
                endingNap: session,
                previousSleepEnd: prevEnd,
                napsToday: napsToday
            ) {
                baby.adaptationFactor = updated.factor
                baby.adaptationConfidence = updated.confidence
                try? context.save()
            }
        }
        refresh()
        if let baby, let prediction {
            NapLiveActivityManager.shared.endNapActivity(
                babyName: baby.name,
                nextNapAt: prediction.recommendedStart
            )
        } else {
            NapLiveActivityManager.shared.endAll()
        }
        NapNotifier.shared.scheduleNextNap(prediction: prediction, babyName: baby?.name ?? "Baby")
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

    func resetBaby() {
        if let baby { context.delete(baby) }
        let allSessions = (try? context.fetch(FetchDescriptor<NapSession>())) ?? []
        for session in allSessions { context.delete(session) }
        try? context.save()
        NapLiveActivityManager.shared.endAll()
        NapNotifier.shared.cancelAll()
        refresh()
    }

    // MARK: - Refresh

    func refresh() {
        baby = fetchBaby()

        let activeDescriptor = FetchDescriptor<NapSession>(
            predicate: #Predicate { $0.endedAt == nil },
            sortBy: [SortDescriptor(\.startedAt, order: .reverse)]
        )
        activeSession = (try? context.fetch(activeDescriptor))?.first

        let completedDescriptor = FetchDescriptor<NapSession>(
            predicate: #Predicate { $0.endedAt != nil },
            sortBy: [SortDescriptor(\.startedAt, order: .reverse)]
        )
        let completed = (try? context.fetch(completedDescriptor)) ?? []
        lastCompletedSleep = completed.first

        let calendar = Calendar.current
        let dayStart = calendar.startOfDay(for: .now)
        napsToday = completed.filter { $0.startedAt >= dayStart }
        lastNightTotalSeconds = computeLastNightTotal(completed: completed)

        if let baby, activeSession == nil {
            let predictor = NapPredictor(baby: baby)
            prediction = predictor.predict(
                lastSleep: lastCompletedSleep,
                napsToday: napsToday,
                lastNightTotalSeconds: lastNightTotalSeconds
            )
        } else {
            prediction = nil
        }

        writeSnapshotIfChanged()
    }

    private func computeLastNightTotal(completed: [NapSession]) -> TimeInterval {
        guard let lastEnd = lastCompletedSleep?.endedAt else { return 0 }
        let earliest = lastEnd.addingTimeInterval(-18 * 3600)
        return completed
            .filter { $0.kind == .night && $0.startedAt >= earliest && ($0.endedAt ?? lastEnd) <= lastEnd.addingTimeInterval(60) }
            .reduce(0.0) { $0 + $1.duration }
    }

    private func writeSnapshotIfChanged() {
        guard let baby else {
            if lastSnapshot != nil {
                SharedSnapshotStore.clear()
                lastSnapshot = nil
                WidgetCenter.shared.reloadAllTimelines()
            }
            return
        }
        let snapshot = SharedSnapshot(
            babyName: baby.name,
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

    private func fetchBaby() -> Baby? {
        let descriptor = FetchDescriptor<Baby>(sortBy: [SortDescriptor(\.createdAt)])
        return (try? context.fetch(descriptor))?.first
    }

    private func previousSleepEnd(before session: NapSession) -> Date? {
        let descriptor = FetchDescriptor<NapSession>(
            predicate: #Predicate { $0.endedAt != nil },
            sortBy: [SortDescriptor(\.startedAt, order: .reverse)]
        )
        let all = (try? context.fetch(descriptor)) ?? []
        return all.first(where: { $0.id != session.id && $0.startedAt < session.startedAt })?.endedAt
    }

    // MARK: - Ticking

    private func startTicking() {
        refreshTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30))
                self?.refresh()
            }
        }
    }
}
