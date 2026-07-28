import UIKit
import UserNotifications

class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    let appState = AppState()

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        registerNotificationCategories()
        // Wire the App Intent bridge so OpenConversationIntent can route into
        // the conversation when "Talk to Coach" is tapped from an AlarmKit alert.
        AlarmRoute.shared.appState = appState
        // Start observing AlarmKit's current alarm set. Used by reconcile to
        // detect orphaned alarms on every app open. The observation runs on
        // a detached background task so the launch path doesn't block.
        AlarmKitService.shared.startObserving()
        Task { await LogService.shared.log(.app, "app didFinishLaunching") }
        return true
    }

    private func registerNotificationCategories() {
        let snoozeAction = UNNotificationAction(
            identifier: Constants.NotificationAction.snooze,
            title: "Snooze 10min",
            options: []
        )
        let dismissAction = UNNotificationAction(
            identifier: Constants.NotificationAction.dismiss,
            title: "I'm up",
            options: .foreground
        )

        let alarmCategory = UNNotificationCategory(
            identifier: Constants.NotificationCategory.alarm,
            actions: [dismissAction, snoozeAction],
            intentIdentifiers: [],
            options: []
        )

        UNUserNotificationCenter.current().setNotificationCategories([alarmCategory])
    }

    /// Called when a notification arrives while the app is already foreground.
    /// For our alarm notifications we don't want iOS's default banner — that's
    /// subtle and auto-dismisses. We want to take over the screen with the
    /// conversation view, same as when the user taps a notification from lock.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        let userInfo = notification.request.content.userInfo
        if let alarmIdString = userInfo["alarmId"] as? String,
           let alarmId = UUID(uuidString: alarmIdString) {
            await MainActor.run {
                appState.triggerAlarm(alarmId: alarmId)
            }
            return []
        }
        return [.banner, .sound, .badge]
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let userInfo = response.notification.request.content.userInfo
        guard let alarmIdString = userInfo["alarmId"] as? String,
              let alarmId = UUID(uuidString: alarmIdString) else { return }

        await MainActor.run {
            appState.triggerAlarm(alarmId: alarmId)
        }
    }
}
