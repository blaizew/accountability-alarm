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

    // `missedGraceMinutes` used to live here. Deleted 2026-07-27: it was a
    // time-based proxy for "is this chain still in flight?", and reconcile now
    // reads AlarmKit's actual state instead. Every candidate threshold was
    // arbitrary — 30 minutes silently became a six-tap snooze budget once
    // alarm-screen snoozes stopped creating events, and the alert's 15-minute
    // ring duration marks only when the sound stops, not when the firing ends.

    /// Ceiling on any single snooze, in minutes. Also the `maximum` in both
    /// snooze tool schemas. A request past this is clamped and the Coach is
    /// told to say so — silently granting less than asked is the class of bug
    /// this whole feature exists to remove.
    static let maxSnoozeMinutes = 30

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

    /// Fist bump settings. Picker values store the raw enum value, or "random".
    static let bumpHapticKey = "bumpHaptic"
    static let bumpRemovalKey = "bumpRemoval"
    static let bumpConfettiPatternKey = "bumpConfettiPattern"
    static let bumpConfettiShapesKey = "bumpConfettiShapes"
    /// Fist width as a fraction of screen width (Double, default 0.65).
    static let bumpFistWidthKey = "bumpFistWidth"
    /// Raw value of the previous bump removal, to avoid repeating it.
    static let bumpLastRemovalKey = "bumpLastRemoval"

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
