import Foundation
import SwiftData

@Model
final class Alarm {
    var id: UUID = UUID()
    var label: String = ""
    var hour: Int = 22
    var minute: Int = 0
    var repeatDays: [Int] = [] // 1=Sun, 2=Mon, ..., 7=Sat
    /// Legacy single "Why this matters" field. Kept for backward compat with
    /// alarms created before the five-box commitment model. On edit, content
    /// here migrates to `desiredBehavior` if the new fields are empty.
    var reasonText: String = ""
    var reasonAudioPath: String?

    /// Five-box commitment fields. Each is passed verbatim to the LLM along
    /// with its title so the conversation has rich context for accountability.
    var desiredBehavior: String = ""
    var whyWantThis: String = ""
    var positiveOutcome: String = ""
    var negativeOutcome: String = ""
    var longTermImpact: String = ""
    /// Acceptable reasons to skip this alarm, written by the user when they
    /// set it. The Coach accepts a skip that matches one of these without
    /// pushback. Not one of the five commitment boxes — it is the user's
    /// pre-approved list of legitimate exceptions.
    var exceptionCases: String = ""
    var targetSleepHours: Double?
    var nextMorningEvent: String?
    var nextMorningEventHour: Int?
    var nextMorningEventMinute: Int?
    /// When non-nil and in the future, the alarm is currently snoozed and
    /// will re-fire at this date. Cleared (or left stale) once the snooze
    /// notification fires.
    var snoozedUntil: Date?
    /// AlarmKit alarm IDs we own for this alarm config. For repeating alarms
    /// this can hold one UUID per scheduled weekday; for one-shot just one.
    /// We store the UUIDs so we can later call `AlarmManager.cancel(id:)`.
    var alarmKitIdStrings: [String] = []
    /// AlarmKit ID of the currently-pending snooze, if any. Set by the
    /// system Stop button (via SnoozeStopIntent) and by the conversation's
    /// safety-net path. Cleared on comply/override. Re-set on each new
    /// snooze so we only ever have one pending at a time.
    var pendingSnoozeIdString: String?
    /// User-configurable snooze interval, in minutes. Used for the
    /// conversation's in-app Snooze button default. The system Stop button
    /// always uses `Constants.stopButtonSnoozeMinutes` (5 min) regardless.
    var snoozeMinutes: Int = 10

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

extension Alarm {
    /// A new, un-inserted Alarm for rehearsal: same commitment text, firing
    /// time set to `now`. Excludes events, AlarmKit ids, and snooze state.
    func rehearsalCopy(now: Date = Date()) -> Alarm {
        let cal = Calendar.current
        let copy = Alarm(
            label: label,
            hour: cal.component(.hour, from: now),
            minute: cal.component(.minute, from: now)
        )
        copy.reasonText = reasonText
        copy.reasonAudioPath = reasonAudioPath
        copy.desiredBehavior = desiredBehavior
        copy.whyWantThis = whyWantThis
        copy.positiveOutcome = positiveOutcome
        copy.negativeOutcome = negativeOutcome
        copy.longTermImpact = longTermImpact
        copy.exceptionCases = exceptionCases
        copy.targetSleepHours = targetSleepHours
        copy.nextMorningEvent = nextMorningEvent
        copy.nextMorningEventHour = nextMorningEventHour
        copy.nextMorningEventMinute = nextMorningEventMinute
        copy.snoozeMinutes = snoozeMinutes
        copy.repeatDays = repeatDays
        return copy
    }
}
