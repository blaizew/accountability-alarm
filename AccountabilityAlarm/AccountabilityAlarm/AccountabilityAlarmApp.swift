import SwiftUI
import SwiftData

@main
struct AccountabilityAlarmApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @Environment(\.scenePhase) private var scenePhase

    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Alarm.self,
            AlarmEvent.self,
            MorningCheckin.self,
        ])
        let modelConfiguration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false
        )
        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            MainTabView()
                .environment(appDelegate.appState)
        }
        .modelContainer(sharedModelContainer)
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                Task { @MainActor in
                    let context = sharedModelContainer.mainContext
                    let alarms = (try? context.fetch(FetchDescriptor<Alarm>())) ?? []
                    await AlarmKitService.shared.reconcileOnAppOpen(alarms: alarms)
                    try? context.save()
                }
            }
        }
    }
}
