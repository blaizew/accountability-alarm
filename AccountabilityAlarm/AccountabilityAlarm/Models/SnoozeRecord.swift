import Foundation

/// One snooze taken within a wake-up chain, with the time it happened and
/// where it came from.
///
/// `AlarmEvent.snoozeCount` alone can't answer "when did you snooze?", which
/// is what the Coach needs to reason about elapsed time. These records are the
/// timeline's data source.
///
/// `at` is not always exact. A snooze taken from the alarm screen runs no code
/// of ours (AlarmKit handles the countdown natively), so it can only be
/// detected after the fact when the app next opens — see `isApproximate`.
struct SnoozeRecord: Codable, Sendable, Hashable {
    let at: Date
    let minutes: Int
    let source: Source

    /// True when `at` was inferred rather than observed. Bounded by
    /// `[max(scheduledRing, observation - countdown), observation]`, so it is
    /// never off by more than the countdown duration — but the timeline must
    /// render it as approximate ("~9:48 PM") rather than claiming precision.
    let isApproximate: Bool

    enum Source: String, Codable, Sendable {
        /// System "Snooze N min" button — AlarmKit `.countdown`, no code of
        /// ours runs. Always approximate.
        case countdown
        /// The in-conversation Snooze button.
        case snoozeButton
        /// The LLM's `snooze_alarm` tool.
        case coach
        /// Automatic reschedule after the conversation was opened and the app
        /// closed without resolving.
        case safetyNet
    }

    init(at: Date, minutes: Int, source: Source, isApproximate: Bool = false) {
        self.at = at
        self.minutes = minutes
        self.source = source
        self.isApproximate = isApproximate
    }

    /// How the timeline names this snooze to the Coach.
    var sourceDescription: String {
        switch source {
        case .countdown:    return "system Snooze button"
        case .snoozeButton: return "in-app Snooze button"
        case .coach:        return "you gave them this"
        case .safetyNet:    return "opened the conversation, closed the app without resolving"
        }
    }
}
