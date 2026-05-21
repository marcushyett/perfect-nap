import Foundation
import ActivityKit

@MainActor
final class NapLiveActivityManager {
    static let shared = NapLiveActivityManager()
    private init() {}

    private var current: Activity<NapActivityAttributes>? {
        Activity<NapActivityAttributes>.activities.first
    }

    func startNapActivity(babyName: String, startedAt: Date, kind: SleepKind) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        endAll()
        let attributes = NapActivityAttributes(babyName: babyName)
        let state = NapActivityAttributes.ContentState(
            phase: .napping,
            sessionStart: startedAt,
            nextNapAt: nil,
            babyName: babyName,
            sleepKind: kind.rawValue
        )
        let content = ActivityContent(
            state: state,
            staleDate: Calendar.current.date(byAdding: .hour, value: 6, to: .now)
        )
        do {
            _ = try Activity.request(attributes: attributes, content: content, pushType: nil)
        } catch {
            #if DEBUG
            print("Live Activity start failed: \(error)")
            #endif
        }
    }

    func endNapActivity(babyName: String, nextNapAt: Date) {
        Task {
            let state = NapActivityAttributes.ContentState(
                phase: .awake,
                sessionStart: nil,
                nextNapAt: nextNapAt,
                babyName: babyName,
                sleepKind: SleepKind.nap.rawValue
            )
            let staleDate = max(nextNapAt.addingTimeInterval(30 * 60), Date.now.addingTimeInterval(60))
            let content = ActivityContent(state: state, staleDate: staleDate)
            if let current {
                await current.update(content)
            } else if ActivityAuthorizationInfo().areActivitiesEnabled {
                let attributes = NapActivityAttributes(babyName: babyName)
                _ = try? Activity.request(attributes: attributes, content: content, pushType: nil)
            }
        }
    }

    func endAll() {
        Task {
            for activity in Activity<NapActivityAttributes>.activities {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
        }
    }
}
