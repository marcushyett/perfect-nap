import Foundation
import ActivityKit
import CoreData

/// Bridges ActivityKit push tokens to the relay so a partner's device can update *this* device's
/// lock-screen Live Activity. Observes:
///  - the app-level **push-to-start** token (iOS 17.2+) → registered under every baby, so a partner
///    can start a fresh napping activity here even when the app is closed;
///  - each running activity's **update token** → registered under that activity's baby, so a partner
///    can update the live timer; cleared when the activity ends.
@MainActor
final class PushSyncManager {
    static let shared = PushSyncManager()
    private init() {}

    private var started = false
    private var latestPushToStartToken: String?

    func start() {
        guard !started, RelayClient.isConfigured else { return }
        started = true

        if #available(iOS 17.2, *) {
            Task {
                for await tokenData in Activity<NapActivityAttributes>.pushToStartTokenUpdates {
                    let token = hex(tokenData)
                    latestPushToStartToken = token
                    for id in babyIDs() {
                        await RelayClient.register(babyKey: id, fields: ["pushToStartToken": token])
                    }
                }
            }
        }

        Task {
            for activity in Activity<NapActivityAttributes>.activities { observe(activity) }
            for await activity in Activity<NapActivityAttributes>.activityUpdates { observe(activity) }
        }
    }

    /// Re-publish the (cached) push-to-start token for all current babies — call when a baby is added
    /// or a share is accepted, so a freshly-shared baby can receive push-to-start here.
    func refreshBabyRegistrations() {
        guard started, RelayClient.isConfigured, let token = latestPushToStartToken else { return }
        Task {
            for id in babyIDs() { await RelayClient.register(babyKey: id, fields: ["pushToStartToken": token]) }
        }
    }

    private func observe(_ activity: Activity<NapActivityAttributes>) {
        let babyKey = activity.attributes.babyID
        guard !babyKey.isEmpty else { return }
        Task {
            for await tokenData in activity.pushTokenUpdates {
                await RelayClient.register(babyKey: babyKey, fields: ["activityToken": hex(tokenData)])
            }
            // The loop ends when the activity ends → clear the stale activity token so the relay
            // falls back to push-to-start next time.
            await RelayClient.register(babyKey: babyKey, fields: ["activityToken": NSNull()])
        }
    }

    private func hex(_ data: Data) -> String { data.map { String(format: "%02x", $0) }.joined() }

    private func babyIDs() -> [String] {
        let req = Baby.fetchRequest()
        return ((try? CoreDataStack.shared.viewContext.fetch(req)) ?? []).compactMap { $0.id?.uuidString }
    }
}
