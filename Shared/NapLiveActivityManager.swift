import Foundation
import ActivityKit

/// What a single baby's Live Activity should show.
enum NapLiveActivityIntent: Equatable {
    case napping(start: Date, kind: SleepKind)
    case awake(nextNapAt: Date, lastEndedAt: Date?, latestNapAt: Date?)
    case none
}

@MainActor
final class NapLiveActivityManager {
    static let shared = NapLiveActivityManager()
    private init() {}

    static let lastStatusKey = "perfectnap.liveActivity.lastStatus"
    private static var appGroupDefaults: UserDefaults {
        UserDefaults(suiteName: SharedSnapshotStore.appGroupID) ?? .standard
    }
    static func recordStatus(_ message: String) {
        let f = DateFormatter(); f.dateFormat = "HH:mm:ss"
        appGroupDefaults.set("\(f.string(from: .now)) — \(message)", forKey: lastStatusKey)
    }

    private func staleDate() -> Date {
        Calendar.current.date(byAdding: .hour, value: 6, to: .now) ?? .now.addingTimeInterval(6 * 3600)
    }

    /// Max simultaneous napping Live Activities (lock-screen real estate).
    private let maxNappingActivities = 3

    /// Full reconcile from the app: one napping activity per actively-napping baby (capped), plus a
    /// single wake-window activity for the selected baby. Activities for any other baby are ended.
    func reconcile(
        babies: [UUID],
        napping: [(babyID: UUID, name: String, start: Date, kind: SleepKind)],
        selectedAwake: (babyID: UUID, name: String, nextNapAt: Date, lastEndedAt: Date?, latestNapAt: Date?)?,
        selectedBabyName: String
    ) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            Self.recordStatus("Skipped: Live Activities disabled in iOS Settings.")
            Task { await endAllAndWait() }
            return
        }

        var desired: [String: NapActivityAttributes.ContentState] = [:]
        for n in napping.prefix(maxNappingActivities) {
            desired[n.babyID.uuidString] = NapActivityAttributes.ContentState(
                phase: .napping, sessionStart: n.start, nextNapAt: nil,
                babyName: n.name, sleepKind: n.kind.rawValue
            )
        }
        if let a = selectedAwake, desired[a.babyID.uuidString] == nil {
            desired[a.babyID.uuidString] = NapActivityAttributes.ContentState(
                phase: .awake, sessionStart: nil, nextNapAt: a.nextNapAt,
                babyName: a.name, sleepKind: SleepKind.nap.rawValue, lastEndedAt: a.lastEndedAt, latestNapAt: a.latestNapAt
            )
        }
        Task { await applyDesired(desired) }
    }

    private func applyDesired(_ desired: [String: NapActivityAttributes.ContentState]) async {
        var remaining = desired
        for activity in Activity<NapActivityAttributes>.activities {
            let key = activity.attributes.babyID
            if let state = remaining[key] {
                if activity.content.state != state {
                    await activity.update(ActivityContent(state: state, staleDate: staleDate()))
                }
                remaining[key] = nil
            } else {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
        }
        for (key, state) in remaining {
            let attributes = NapActivityAttributes(babyName: state.babyName, babyID: key)
            do {
                _ = try Activity.request(attributes: attributes, content: ActivityContent(state: state, staleDate: staleDate()), pushType: nil)
                Self.recordStatus("Started activity for \(state.babyName).")
            } catch {
                Self.recordStatus("Activity.request failed: \(error.localizedDescription)")
            }
        }
    }

    /// Single-baby update — used from App Intents (lock-screen buttons) which run in the app process
    /// and may not have a live SleepStore to drive the full reconcile.
    func sync(babyID: String, to intent: NapLiveActivityIntent, babyName: String) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        let state: NapActivityAttributes.ContentState?
        switch intent {
        case .napping(let start, let kind):
            state = .init(phase: .napping, sessionStart: start, nextNapAt: nil, babyName: babyName, sleepKind: kind.rawValue)
        case .awake(let next, let last, let latest):
            state = .init(phase: .awake, sessionStart: nil, nextNapAt: next, babyName: babyName, sleepKind: SleepKind.nap.rawValue, lastEndedAt: last, latestNapAt: latest)
        case .none:
            state = nil
        }
        Task {
            let existing = Activity<NapActivityAttributes>.activities.first { $0.attributes.babyID == babyID }
            guard let state else {
                if let existing { await existing.end(nil, dismissalPolicy: .immediate) }
                return
            }
            if let existing {
                if existing.content.state != state { await existing.update(ActivityContent(state: state, staleDate: staleDate())) }
            } else {
                let attributes = NapActivityAttributes(babyName: babyName, babyID: babyID)
                _ = try? Activity.request(attributes: attributes, content: ActivityContent(state: state, staleDate: staleDate()), pushType: nil)
            }
        }
    }

    func endAll() { Task { await endAllAndWait() } }

    private func endAllAndWait() async {
        for activity in Activity<NapActivityAttributes>.activities {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
    }
}
