import Foundation

/// TEMPORARY INSTRUMENTATION (spec AC-4.2/AC-4.3). Removed in Phase 7.
///
/// Renders `buildTimeContext` against a synthetic chain with known snoozes so
/// the output can be checked against fixed inputs, rather than waiting on a
/// live conversation and eyeballing whatever times happen to occur.
///
/// The synthetic chain reproduces the 2026-07-26 incident: a 9:30 PM alarm,
/// three snoozes, and a conversation opened at 9:42.
enum TimeContextSelfCheck {

    @MainActor
    static func run() async {
        let cal = Calendar.current
        func at(_ h: Int, _ m: Int) -> Date {
            var c = DateComponents()
            c.year = 2026; c.month = 7; c.day = 26; c.hour = h; c.minute = m; c.second = 0
            return cal.date(from: c)!
        }

        let alarm = Alarm(label: "Meditate and start bedtime routine", hour: 21, minute: 30)
        let event = AlarmEvent(alarm: alarm)
        event.firedAt = at(21, 31)
        event.recordSnooze(minutes: 5, source: .countdown, at: at(21, 33), isApproximate: true)
        event.recordSnooze(minutes: 5, source: .safetyNet, at: at(21, 36), isApproximate: true)
        event.recordSnooze(minutes: 3, source: .coach, at: at(21, 39))
        // Simulate a legacy event: counted but never timestamped.
        event.snoozeCount += 1

        let rendered = ConversationEngine().buildTimeContext(
            alarm: alarm,
            event: event,
            now: at(21, 42)
        )

        // Content assertions from AC-4.2 / AC-4.3.
        var checks: [(String, Bool)] = []
        checks.append(("has CURRENT TIME", rendered.contains("CURRENT TIME: 9:42 PM")))
        checks.append(("has TIMELINE header", rendered.contains("TIMELINE (this wake-up chain):")))
        checks.append(("scheduled row", rendered.contains("9:30 PM   alarm scheduled")))
        checks.append(("rang row", rendered.contains("9:31 PM   alarm rang")))
        checks.append(("approximate marker", rendered.contains("~9:33 PM")))
        checks.append(("exact coach snooze unmarked", rendered.contains(" 9:39 PM") && !rendered.contains("~9:39 PM")))
        checks.append(("unrecorded line", rendered.contains("(1 earlier snooze(s), times not recorded)")))
        checks.append(("elapsed note", rendered.contains("11 min past the alarm")))
        checks.append(("no-manual-arithmetic instruction", rendered.contains("do NOT convert it to minutes yourself")))

        // Ascending order: 9:31 rang, then 9:33, 9:36, 9:39.
        let order = ["9:31 PM", "9:33 PM", "9:36 PM", "9:39 PM"]
            .compactMap { rendered.range(of: $0)?.lowerBound }
        checks.append(("ascending timeline", order.count == 4 && zip(order, order.dropFirst()).allSatisfy { $0 < $1 }))

        for (name, passed) in checks {
            await LogService.shared.log(
                .app,
                "PROBE timeContext: \(name) — \(passed ? "PASS" : "FAIL")",
                isError: !passed
            )
        }
        await LogService.shared.log(.app, "PROBE timeContext rendered:\n\(rendered)")
    }
}
