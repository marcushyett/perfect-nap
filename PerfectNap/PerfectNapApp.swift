import SwiftUI
import CoreData

@main
struct PerfectNapApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    private let stack = CoreDataStack.shared
    @State private var store: SleepStore

    init() {
        let ctx = CoreDataStack.shared.viewContext
        LegacyMigration.runIfNeeded(into: ctx)
        DefaultSettings.applyDefaultBedtimeIfNeeded(in: ctx)
        DefaultSettings.assignOrphanNapsIfNeeded(in: ctx)
        #if DEBUG
        DebugSeed.seedIfRequested(into: ctx)
        #endif
        _store = State(wrappedValue: SleepStore(context: ctx))
        #if DEBUG
        CoreDataStack.shared.initializeCloudKitSchemaForDevelopment()
        #endif
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
                .environment(\.managedObjectContext, stack.viewContext)
                .onAppear {
                    #if DEBUG
                    if ProcessInfo.processInfo.arguments.contains("-seedSampleData") { return }
                    #endif
                    NapNotifier.shared.requestAuthorisationIfNeeded()
                }
        }
    }
}

struct RootView: View {
    @Environment(SleepStore.self) private var store

    var body: some View {
        Group {
            if store.baby == nil {
                OnboardingView()
            } else {
                HomeView()
            }
        }
        .animation(.easeInOut, value: store.baby != nil)
    }
}
