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
    /// When non-nil and in the future, the alarm is currently snoozed and
    /// will re-fire at this date. Cleared (or left stale) once the snooze
    /// notification fires.
    var snoozedUntil: Date?
    /// AlarmKit alarm IDs we own for this alarm config. For repeating alarms
    /// this can hold one UUID per scheduled weekday; for one-shot just one.
    /// We store the UUIDs so we can later call `AlarmManager.cancel(id:)`.
    var alarmKitIdStrings: [String] = []
    /// AlarmKit ID of the currently-pending pre-emptive snooze, if any.
    /// Cleared on comply/override. Re-set on snooze duration changes.
    var pendingSnoozeIdString: String?
    /// AlarmKit ID of the next-occurrence T+1 companion alarm. T+0 alarms are
    /// recurring weekly; T+1 companions are one-shot, refreshed each time the
    /// user interacts with the alarm so they remain individually cancellable.
    var nextT1IdString: String?

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
