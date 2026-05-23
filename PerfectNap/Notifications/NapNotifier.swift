import Foundation
import UserNotifications

@MainActor
final class NapNotifier {
    static let shared = NapNotifier()
    private init() {}

    private let centre = UNUserNotificationCenter.current()
    private let idealId = "perfectnap.next.ideal"
    private let openWindowId = "perfectnap.next.open"

    func requestAuthorisationIfNeeded() {
        centre.getNotificationSettings { settings in
            guard settings.authorizationStatus == .notDetermined else { return }
            self.centre.requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
        }
    }

    func scheduleNextNap(prediction: NapPrediction?, babyName: String) {
        cancelAll()
        guard let prediction else { return }
        scheduleNotification(
            id: idealId,
            date: prediction.recommendedStart,
            title: "Time for \(babyName)'s nap",
            body: "Based on age + recent sleep, the ideal window is open now."
        )
        if prediction.latestStart > prediction.recommendedStart {
            scheduleNotification(
                id: openWindowId,
                date: prediction.latestStart,
                title: "Sleep window closing",
                body: "Latest recommended start has been reached."
            )
        }
    }

    func cancelAll() {
        centre.removePendingNotificationRequests(withIdentifiers: [idealId, openWindowId])
    }

    private func scheduleNotification(id: String, date: Date, title: String, body: String) {
        guard date > .now else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let trigger = UNTimeIntervalNotificationTrigger(
            timeInterval: max(date.timeIntervalSinceNow, 1),
            repeats: false
        )
        let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)
        centre.add(request)
    }
}
