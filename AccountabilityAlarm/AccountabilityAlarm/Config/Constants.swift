import Foundation

enum Constants {
    static let snoozeIntervalMinutes = 3
    /// Flip to `true` after Apple grants the Critical Alerts entitlement and
    /// you enable the capability in Xcode. Until then, NotificationService
    /// uses .timeSensitive + plain custom sound so notifications actually fire.
    static let hasCriticalAlertsEntitlement = false

    /// How many back-to-back notifications make up one alarm/snooze burst.
    /// Each notification plays up to 30s of sound; 6 spaced 10s apart = ~60s
    /// of nearly-continuous ringing on the lock screen until the user engages.
    static let burstNotificationCount = 6
    static let burstSpacingSeconds: TimeInterval = 10
    static let maxRings = 4
    static let apiEndpoint = "https://api.anthropic.com/v1/messages"
    static let apiModel = "claude-sonnet-4-6"
    static let apiVersion = "2023-06-01"
    static let maxConversationTurns = 6

    enum NotificationCategory {
        static let alarm = "ALARM_CATEGORY"
        static let morningCheckin = "MORNING_CHECKIN"
    }

    enum NotificationAction {
        static let snooze = "SNOOZE_ACTION"
        static let dismiss = "DISMISS_ACTION"
        static let open = "OPEN_ACTION"
    }
}
