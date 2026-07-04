import Foundation
import SwiftData

/// The single shared SwiftData stack for the whole process.
///
/// The app scene, App Intents (SnoozeStopIntent runs in this same process,
/// launched in the background if needed), and LogService must all go through
/// ONE container. Opening a second container over the same store means the
/// running app keeps stale in-memory objects — e.g. it can't see the
/// `pendingSnoozeIdString` the Stop intent just wrote, so cancel paths miss
/// the pending snooze, and a later app-side save clobbers the intent's write.
enum AppContainer {
    static let shared: ModelContainer? = {
        let schema = Schema([
            Alarm.self,
            AlarmEvent.self,
            MorningCheckin.self,
            AlarmLogEntry.self,
        ])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        return try? ModelContainer(for: schema, configurations: [config])
    }()
}
