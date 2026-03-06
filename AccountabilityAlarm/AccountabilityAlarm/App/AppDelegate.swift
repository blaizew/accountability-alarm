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

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        return [.banner, .sound, .badge]
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let userInfo = response.notification.request.content.userInfo
        guard let alarmIdString = userInfo["alarmId"] as? String,
              let alarmId = UUID(uuidString: alarmIdString),
              let ringRaw = userInfo["ring"] as? Int,
              let ring = EscalationRing(rawValue: ringRaw) else { return }

        appState.triggerAlarm(alarmId: alarmId, ring: ring)
    }
}
