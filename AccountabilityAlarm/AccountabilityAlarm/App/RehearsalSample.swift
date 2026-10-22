import Foundation

/// The built-in alarm used to try the Coach without any real alarm.
/// Built in code and never saved. Before noon it is a morning run;
/// from noon on it is a bedtime alarm.
enum RehearsalSample {
    static func makeAlarm(now: Date = Date()) -> Alarm {
        let cal = Calendar.current
        let hour = cal.component(.hour, from: now)
        let minute = cal.component(.minute, from: now)
        return hour < 12 ? morningRun(hour: hour, minute: minute)
                         : lightsOut(hour: hour, minute: minute)
    }

    private static func morningRun(hour: Int, minute: Int) -> Alarm {
        let alarm = Alarm(label: "Morning run", hour: hour, minute: minute)
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

    private static func lightsOut(hour: Int, minute: Int) -> Alarm {
        let alarm = Alarm(label: "Lights out", hour: hour, minute: minute)
        alarm.snoozeMinutes = 5
        alarm.reasonText = "Put the phone on the charger in the kitchen and get into bed."
        alarm.desiredBehavior = alarm.reasonText
        alarm.whyWantThis = "I wake up clear when I am asleep by eleven."
        alarm.positiveOutcome = "A full night and an easy morning."
        alarm.negativeOutcome = "I scroll until one and drag through tomorrow."
        alarm.longTermImpact = "Sleeping on time is how I keep my energy for the things I care about."
        alarm.exceptionCases = ""
        return alarm
    }
}
