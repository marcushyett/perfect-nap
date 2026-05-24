import Foundation

/// Talks to the Perfect Nap push relay (https://perfectnap-push.vercel.app). Registers this device's
/// Live Activity tokens and reports nap events so the *other* parent's lock-screen Live Activity
/// updates instantly even with their app closed. The shared secret comes from the `RelaySharedSecret`
/// Info.plist key, injected from a gitignored xcconfig — never committed to the public repo.
enum RelayClient {
    static let baseURL = URL(string: "https://perfectnap-push.vercel.app")!

    private static var secret: String {
        (Bundle.main.object(forInfoDictionaryKey: "RelaySharedSecret") as? String) ?? ""
    }
    static var isConfigured: Bool { !secret.isEmpty }

    /// Stable per-install id shared by the app + widget extension (app group).
    static var deviceID: String {
        let key = "perfectnap.relay.deviceID"
        let defaults = UserDefaults(suiteName: CoreDataStack.appGroupID) ?? .standard
        if let id = defaults.string(forKey: key) { return id }
        let id = UUID().uuidString
        defaults.set(id, forKey: key)
        return id
    }

    /// Upsert this device's tokens for a baby. `fields` is merged server-side, so send only what
    /// changed: `["pushToStartToken": t]`, `["activityToken": t]`, or `["activityToken": NSNull()]` to
    /// clear it when the activity ends.
    static func register(babyKey: String, fields: [String: Any]) async {
        var body = fields
        body["babyKey"] = babyKey
        body["deviceID"] = deviceID
        await post("register", body)
    }

    /// Report a nap state change. `contentState` must already use Unix-timestamp numbers for dates
    /// (see `liveActivityContentState`). The relay pushes it to the baby's other devices.
    static func napEvent(babyKey: String, contentState: [String: Any], babyName: String, staleSeconds: Int = 6 * 3600) async {
        await post("nap-event", [
            "babyKey": babyKey,
            "deviceID": deviceID,
            "contentState": contentState,
            "attributes": ["babyName": babyName, "babyID": babyKey],
            "attributesType": "NapActivityAttributes",
            "staleSeconds": staleSeconds,
        ])
    }

    private static func post(_ path: String, _ body: [String: Any]) async {
        guard isConfigured else { return }
        var req = URLRequest(url: baseURL.appendingPathComponent("api").appendingPathComponent(path))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(secret, forHTTPHeaderField: "X-Relay-Secret")
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
            if code != 200 {
                perfectNapLog.error("relay \(path, privacy: .public) → \(code): \(String(data: data, encoding: .utf8) ?? "", privacy: .public)")
            }
        } catch {
            perfectNapLog.error("relay \(path, privacy: .public) failed: \(String(describing: error), privacy: .public)")
        }
    }
}

extension NapActivityAttributes.ContentState {
    /// JSON-ready dict with dates as Unix-epoch seconds — the format ActivityKit decodes from a push.
    var relayDictionary: [String: Any] {
        var d: [String: Any] = ["phase": phase.rawValue, "babyName": babyName, "sleepKind": sleepKind]
        if let s = sessionStart { d["sessionStart"] = s.timeIntervalSince1970 }
        if let n = nextNapAt { d["nextNapAt"] = n.timeIntervalSince1970 }
        if let l = lastEndedAt { d["lastEndedAt"] = l.timeIntervalSince1970 }
        if let la = latestNapAt { d["latestNapAt"] = la.timeIntervalSince1970 }
        return d
    }
}
