import Foundation

/// Turns a snooze request into a concrete number of minutes.
///
/// The LLM may express a snooze either way: `minutes` ("give me 8") or `until`
/// ("until 10"). Clock arithmetic stays HERE rather than in the model, because
/// the model doesn't reliably know what time it is and gets it wrong in a way
/// nobody notices — a 9:30 alarm, a 9:42 conversation, "until 10", and a
/// 30-minute snooze that lands at 10:12.
enum SnoozeResolver {

    enum Resolution: Equatable {
        /// `minutes` is what to schedule; `returnsAt` is the absolute time that
        /// produces. `requested` is non-nil ONLY when the ask was clamped, and
        /// carries what the user actually asked for so the tool result can name
        /// both numbers instead of quietly substituting one.
        case ok(minutes: Int, returnsAt: Date, requested: (minutes: Int, at: Date)?)
        /// Neither or both parameters supplied, or `until` didn't parse.
        case invalid(String)

        static func == (a: Resolution, b: Resolution) -> Bool {
            switch (a, b) {
            case let (.ok(m1, r1, q1), .ok(m2, r2, q2)):
                return m1 == m2
                    && abs(r1.timeIntervalSince(r2)) < 1
                    && q1?.minutes == q2?.minutes
            case let (.invalid(x), .invalid(y)):
                return x == y
            default:
                return false
            }
        }
    }

    /// - Parameters:
    ///   - minutes: relative duration, or nil
    ///   - until: 24-hour "HH:mm" local clock time, or nil
    ///   - now: injected for testability
    static func resolve(minutes: Int?, until: String?, now: Date = Date()) -> Resolution {
        switch (minutes, until?.trimmingCharacters(in: .whitespaces)) {

        case (nil, nil):
            return .invalid("Supply either `minutes` or `until` — neither was given.")

        case let (.some(m), nil):
            return clamp(requestedMinutes: m, now: now)

        case let (nil, .some(u)):
            guard let target = nextOccurrence(of: u, after: now) else {
                return .invalid("Could not parse `until` value \"\(u)\". Use 24-hour \"HH:mm\", e.g. \"22:00\".")
            }
            // Ceil so "until 10:00" at 9:42:30 gives 18 minutes, not 17.
            let raw = Int(ceil(target.timeIntervalSince(now) / 60))
            return clamp(requestedMinutes: raw, now: now)

        case (.some, .some):
            return .invalid("Supply either `minutes` or `until`, not both.")
        }
    }

    /// Floor at 1 (a target that just passed must never schedule a zero or
    /// negative snooze) and cap at `maxSnoozeMinutes`. A clamped result keeps
    /// the original ask so the Coach can tell the user the truth about when
    /// the alarm is actually coming back.
    private static func clamp(requestedMinutes: Int, now: Date) -> Resolution {
        let floored = max(1, requestedMinutes)
        let capped = min(Constants.maxSnoozeMinutes, floored)
        let returnsAt = now.addingTimeInterval(TimeInterval(capped * 60))

        guard capped < floored else {
            return .ok(minutes: capped, returnsAt: returnsAt, requested: nil)
        }
        return .ok(
            minutes: capped,
            returnsAt: returnsAt,
            requested: (minutes: floored, at: now.addingTimeInterval(TimeInterval(floored * 60)))
        )
    }

    /// The next time the clock reads `hhmm`, at or after `now`. This is a
    /// bedtime app — "until 6:00" at 23:50 means tomorrow morning, so rolling
    /// forward past midnight is the normal case, not an edge case.
    private static func nextOccurrence(of hhmm: String, after now: Date) -> Date? {
        let parts = hhmm.split(separator: ":")
        guard parts.count == 2,
              let hour = Int(parts[0]), let minute = Int(parts[1]),
              (0...23).contains(hour), (0...59).contains(minute) else { return nil }

        let cal = Calendar.current
        var components = cal.dateComponents([.year, .month, .day], from: now)
        components.hour = hour
        components.minute = minute
        components.second = 0
        guard let today = cal.date(from: components) else { return nil }

        if today >= now { return today }
        return cal.date(byAdding: .day, value: 1, to: today)
    }
}
