import Foundation
import AppIntents

/// Start a nap from a Live Activity button (Lock Screen / Dynamic Island).
/// LiveActivityIntent runs in the main app's process, so it can mutate SwiftData directly.
@available(iOS 17.0, *)
struct StartNapIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Start nap"
    static var description = IntentDescription("Begin a nap timer from the Lock Screen.")
    static var isDiscoverable: Bool = false
    static var openAppWhenRun: Bool = false

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult {
        await SleepActions.startNap()
        return .result()
    }
}

@available(iOS 17.0, *)
struct StopNapIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Stop nap"
    static var description = IntentDescription("End the active nap from the Lock Screen.")
    static var isDiscoverable: Bool = false
    static var openAppWhenRun: Bool = false

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult {
        await SleepActions.stopNap()
        return .result()
    }
}
