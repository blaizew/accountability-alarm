import Foundation
import SwiftData

@Model
final class Alarm {
    var id: UUID = UUID()
    var label: String = ""
    var hour: Int = 22
    var minute: Int = 0
    var repeatDays: [Int] = [] // 1=Sun, 2=Mon, ..., 7=Sat
    var reasonText: String = ""
    var reasonAudioPath: String?
    var targetSleepHours: Double?
    var nextMorningEvent: String?
    var nextMorningEventHour: Int?
    var nextMorningEventMinute: Int?
    var escalationLevelRaw: String = "firm"

    var escalationLevel: EscalationLevel {
        get { EscalationLevel(rawValue: escalationLevelRaw) ?? .firm }
        set { escalationLevelRaw = newValue.rawValue }
    }
    var enabled: Bool = true
    var createdAt: Date = Date()

    @Relationship(deleteRule: .cascade, inverse: \AlarmEvent.alarm)
    var events: [AlarmEvent] = []

    var timeString: String {
        let h = hour % 12 == 0 ? 12 : hour % 12
        let ampm = hour < 12 ? "AM" : "PM"
        return String(format: "%d:%02d %@", h, minute, ampm)
    }

    var repeatDescription: String {
        if repeatDays.isEmpty { return "One time" }
        if repeatDays.count == 7 { return "Every day" }
        let names = ["", "Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
        return repeatDays.sorted().map { names[$0] }.joined(separator: ", ")
    }

    init(label: String = "", hour: Int = 22, minute: Int = 0) {
        self.id = UUID()
        self.label = label
        self.hour = hour
        self.minute = minute
        self.createdAt = Date()
    }
}
