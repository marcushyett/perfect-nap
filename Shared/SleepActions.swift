import Foundation
import SwiftData

extension Notification.Name {
    /// Posted whenever SleepActions mutates state from outside the SleepStore (i.e. App Intents).
    /// The store listens and immediately refreshes so the UI stays in sync.
    static let perfectNapStateChanged = Notification.Name("app.perfectnap.stateChanged")
}

/// Headless start/stop logic that works from both the SwiftUI store and from App Intents
/// (Lock Screen and Dynamic Island buttons). All mutations go through a fresh ModelContext
/// so they're safe to call from background-launched intent processes.
@MainActor
enum SleepActions {
    static let schema = Schema([Baby.self, NapSession.self])

    static func openContainer() throws -> ModelContainer {
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        return try ModelContainer(for: schema, configurations: config)
    }

    /// Returns the started session, or nil if a session is already active.
    @discardableResult
    static func startNap(at date: Date = .now) async -> NapSession? {
        guard let container = try? openContainer() else { return nil }
        let context = container.mainContext

        if let active = fetchActive(context: context) { return active }

        let kind = NapSession.classify(start: date)
        let session = NapSession(startedAt: date, kind: kind)
        context.insert(session)
        try? context.save()

        let babyName = fetchBaby(context: context)?.name ?? "Baby"
        NapLiveActivityManager.shared.startNapActivity(
            babyName: babyName,
            startedAt: date,
            kind: kind
        )
        NotificationCenter.default.post(name: .perfectNapStateChanged, object: nil)
        return session
    }

    /// Returns the stopped session, or nil if none was active.
    @discardableResult
    static func stopNap(at date: Date = .now) async -> NapSession? {
        guard let container = try? openContainer() else { return nil }
        let context = container.mainContext

        guard let session = fetchActive(context: context) else { return nil }
        session.endedAt = date
        try? context.save()

        if let baby = fetchBaby(context: context), session.kind == .nap {
            let prevEnd = previousSleepEnd(before: session, context: context)
            let napsToday = fetchCompletedToday(context: context)
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

        // Update Live Activity to "awake" with the next nap prediction
        if let baby = fetchBaby(context: context) {
            let predictor = NapPredictor(baby: baby)
            let lastCompleted = fetchLastCompleted(context: context)
            let napsToday = fetchCompletedToday(context: context)
            let nightTotal = totalNightSleepEndingAt(date, context: context)
            let prediction = predictor.predict(
                lastSleep: lastCompleted,
                napsToday: napsToday,
                lastNightTotalSeconds: nightTotal
            )
            if let prediction {
                NapLiveActivityManager.shared.endNapActivity(
                    babyName: baby.name,
                    nextNapAt: prediction.recommendedStart
                )
            } else {
                NapLiveActivityManager.shared.endAll()
            }
        }
        NotificationCenter.default.post(name: .perfectNapStateChanged, object: nil)
        return session
    }

    // MARK: - Helpers

    static func fetchActive(context: ModelContext) -> NapSession? {
        let descriptor = FetchDescriptor<NapSession>(
            predicate: #Predicate { $0.endedAt == nil },
            sortBy: [SortDescriptor(\.startedAt, order: .reverse)]
        )
        return (try? context.fetch(descriptor))?.first
    }

    static func fetchBaby(context: ModelContext) -> Baby? {
        let descriptor = FetchDescriptor<Baby>(sortBy: [SortDescriptor(\.createdAt)])
        return (try? context.fetch(descriptor))?.first
    }

    static func fetchLastCompleted(context: ModelContext) -> NapSession? {
        let descriptor = FetchDescriptor<NapSession>(
            predicate: #Predicate { $0.endedAt != nil },
            sortBy: [SortDescriptor(\.startedAt, order: .reverse)]
        )
        return (try? context.fetch(descriptor))?.first
    }

    static func fetchCompletedToday(context: ModelContext) -> [NapSession] {
        let dayStart = Calendar.current.startOfDay(for: .now)
        let descriptor = FetchDescriptor<NapSession>(
            predicate: #Predicate { $0.endedAt != nil && $0.startedAt >= dayStart },
            sortBy: [SortDescriptor(\.startedAt, order: .reverse)]
        )
        return (try? context.fetch(descriptor)) ?? []
    }

    static func previousSleepEnd(before session: NapSession, context: ModelContext) -> Date? {
        let descriptor = FetchDescriptor<NapSession>(
            predicate: #Predicate { $0.endedAt != nil },
            sortBy: [SortDescriptor(\.startedAt, order: .reverse)]
        )
        let all = (try? context.fetch(descriptor)) ?? []
        return all.first(where: { $0.id != session.id && $0.startedAt < session.startedAt })?.endedAt
    }

    /// Sum of all `.night` sessions whose end is within the 18 hours preceding `reference`.
    /// This is "last night's total sleep" — used to refine the morning wake window.
    static func totalNightSleepEndingAt(_ reference: Date, context: ModelContext) -> TimeInterval {
        let earliest = reference.addingTimeInterval(-18 * 3600)
        let descriptor = FetchDescriptor<NapSession>(
            predicate: #Predicate { $0.endedAt != nil && $0.startedAt >= earliest },
            sortBy: [SortDescriptor(\.startedAt)]
        )
        let recent = (try? context.fetch(descriptor)) ?? []
        return recent
            .filter { $0.kind == .night }
            .reduce(0.0) { $0 + $1.duration }
    }
}
