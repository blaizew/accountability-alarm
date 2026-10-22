import Foundation

/// The built-in alarm used to try the Coach without any real alarm.
/// Built in code and never saved.
enum RehearsalSample {
    static func makeAlarm(now: Date = Date()) -> Alarm {
        let cal = Calendar.current
        let alarm = Alarm(
            label: "Morning run",
            hour: cal.component(.hour, from: now),
            minute: cal.component(.minute, from: now)
        )
        alarm.snoozeMinutes = 5
        alarm.reasonText = "Get up, put on my shoes, and run 5k before work."
        alarm.desiredBehavior = alarm.reasonText
        alarm.whyWantThis = "I feel sharp all day when I run first thing."
        alarm.positiveOutcome = "A calm, focused morning and a clear head at work."
        alarm.negativeOutcome = "I skip it, feel sluggish, and resent myself by noon."
        alarm.longTermImpact = "Running four mornings a week is how I stay healthy for the people who count on me."
        alarm.exceptionCases = ""
        return alarm
    }
}
