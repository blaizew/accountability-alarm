import Foundation
import SwiftData

@Model
final class AlarmEvent {
    var alarm: Alarm?
    var firedAt: Date = Date()
    var outcome: String = "pending" // complied, snoozed_then_complied, overridden, ignored
    var snoozeCount: Int = 0
    var overrideReason: String?
    var conversationLogData: Data?
    var complianceTimeMinutes: Int = 0

    var conversationLog: [ConversationMessage] {
        get {
            guard let data = conversationLogData else { return [] }
            return (try? JSONDecoder().decode([ConversationMessage].self, from: data)) ?? []
        }
        set {
            conversationLogData = try? JSONEncoder().encode(newValue)
        }
    }

    init(alarm: Alarm) {
        self.alarm = alarm
        self.firedAt = Date()
    }

    /// The alarm's currently-open wake-up chain, if any.
    ///
    /// One AlarmEvent spans the whole chain — first fire through final
    /// outcome — across every snooze, re-ring, and re-opened conversation.
    /// Both the conversation and the system Stop intent MUST reuse this
    /// instead of inserting a fresh event, otherwise `snoozeCount` resets to
    /// 0 on every re-ring and the LLM's skepticism ladder never engages.
    static func openChain(for alarm: Alarm) -> AlarmEvent? {
        let cutoff = Date().addingTimeInterval(-TimeInterval(Constants.chainWindowHours) * 3600)
        return alarm.events
            .filter { $0.outcome == "pending" && $0.firedAt > cutoff }
            .max { $0.firedAt < $1.firedAt }
    }
}
