import Foundation

enum Constants {
    /// How long the "Slide to Stop" button snoozes the alarm. The alarm will
    /// re-fire after this interval. The only way to truly silence the alarm
    /// is via in-app Comply.
    static let stopButtonSnoozeMinutes = 5

    /// How long the conversation's pre-emptive safety-net snooze waits before
    /// re-firing — for the "user opened the conversation but closed the app
    /// without resolving" path.
    static let conversationSafetyNetMinutes = 5

    /// How long a wake-up chain stays "open". Within this window, re-rings
    /// and new conversations reuse the same AlarmEvent (so snoozeCount
    /// accumulates and the LLM's skepticism ladder engages). Past it, a
    /// still-pending event is closed as "ignored" by reconcile.
    static let chainWindowHours = 6

    /// Missed-firing detection (reconcile): how long after the scheduled fire
    /// time we wait before calling a never-engaged firing "ignored". Covers
    /// the system alert's own ring window plus a buffer.
    static let missedGraceMinutes = 30

    /// Missed-firing detection: only the most recent scheduled firing within
    /// this lookback is considered. Bounds the error window for one-shot
    /// alarms, whose original fire date we can only approximate.
    static let missedLookbackHours = 24

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

    /// UserDefaults key for whether the user has seen the Downtime/Always
    /// Allowed onboarding notice. Set to true once they dismiss the modal or
    /// the banner.
    static let downtimeNoticeAcknowledgedKey = "downtimeNoticeAcknowledged"

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
