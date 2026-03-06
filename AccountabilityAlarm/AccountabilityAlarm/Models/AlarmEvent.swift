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
}
