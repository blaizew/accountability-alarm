import AppIntents
import Foundation
import ActivityKit

/// App Intent fired when the user taps the "Talk to past-self" button on
/// the AlarmKit alarm UI. It opens the app and routes into the conversation
/// for the alarm whose UUID is carried in the intent.
///
/// The intent runs in the app process (`openAppWhenRun = true`), which means
/// the app launches if it's not already running. By the time `perform()`
/// returns, `AppState.activeAlarmId` has been set and `MainTabView` will
/// present the fullScreenCover with the conversation.
struct OpenConversationIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Talk to past-self"
    static var description = IntentDescription(
        "Opens the accountability conversation for an alarm so you can argue with past-you."
    )

    /// AlarmKit only persists string-shaped intent parameters reliably across
    /// the system UI → app launch boundary.
    @Parameter(title: "Alarm ID")
    var alarmId: String

    static var openAppWhenRun: Bool = true

    init() {}
    init(alarmId: String) {
        self.alarmId = alarmId
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        await LogService.shared.log(.intent, "OpenConversationIntent fired", alarmId: alarmId)
        if let uuid = UUID(uuidString: alarmId) {
            AlarmRoute.shared.openConversation(alarmId: uuid)
        } else {
            await LogService.shared.log(.intent, "OpenConversationIntent: bad alarmId \(alarmId)", isError: true)
        }
        return .result()
    }
}

/// Bridge between the App Intent (which runs in a non-SwiftUI context at
/// launch) and the SwiftUI environment's `AppState`. The AppDelegate wires
/// `AlarmRoute.shared.appState` at startup so the intent can call into it.
final class AlarmRoute: @unchecked Sendable {
    static let shared = AlarmRoute()
    private init() {}

    weak var appState: AppState?

    /// Called by the App Intent. Triggers the conversation flow. The
    /// pre-emptive snooze scheduling lives in `ConversationViewModel.setup`,
    /// so all we do here is flip the navigation state.
    func openConversation(alarmId: UUID) {
        appState?.triggerAlarm(alarmId: alarmId)
    }
}
