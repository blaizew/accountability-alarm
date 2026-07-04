import SwiftUI
import SwiftData

@main
struct AccountabilityAlarmApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @Environment(\.scenePhase) private var scenePhase

    var sharedModelContainer: ModelContainer = {
        guard let container = AppContainer.shared else {
            fatalError("Could not create ModelContainer")
        }
        return container
    }()

    var body: some Scene {
        WindowGroup {
            MainTabView()
                .environment(appDelegate.appState)
        }
        .modelContainer(sharedModelContainer)
        .onChange(of: scenePhase, initial: true) { _, newPhase in
            // Reconcile on EVERY foreground, not once per launch — orphaned
            // AlarmKit alarms and missed firings can appear at any point in a
            // long-lived session. `initial: true` covers the timing where the
            // scene is already .active when the observer attaches, so a cold
            // launch can't skip the pass. Note: a system permission alert
            // (fresh install) holds the scene at .inactive until answered, so
            // the first pass may only run once the user responds — fine,
            // since a fresh install has nothing to reconcile. Re-entrancy-
            // guarded and yields between alarms, so repeat runs are cheap.
            if newPhase == .active {
                Task { @MainActor in
                    let context = sharedModelContainer.mainContext
                    let alarms = (try? context.fetch(FetchDescriptor<Alarm>())) ?? []
                    await AlarmKitService.shared.reconcileOnAppOpen(alarms: alarms, context: context)
                    try? context.save()
                }
            }
        }
    }
}
