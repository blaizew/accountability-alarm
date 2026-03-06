import Foundation

enum Constants {
    static let snoozeIntervalMinutes = 10
    static let maxRings = 4
    static let apiEndpoint = "https://api.anthropic.com/v1/messages"
    static let apiModel = "claude-haiku-4-5-20251001"
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
