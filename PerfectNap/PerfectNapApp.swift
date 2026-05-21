import SwiftUI
import SwiftData

@main
struct PerfectNapApp: App {
    let modelContainer: ModelContainer
    @State private var store: SleepStore

    init() {
        let schema = Schema([Baby.self, NapSession.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        do {
            let container = try ModelContainer(for: schema, configurations: config)
            self.modelContainer = container
            self._store = State(wrappedValue: SleepStore(context: container.mainContext))
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
                .onAppear {
                    NapNotifier.shared.requestAuthorisationIfNeeded()
                }
        }
        .modelContainer(modelContainer)
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
