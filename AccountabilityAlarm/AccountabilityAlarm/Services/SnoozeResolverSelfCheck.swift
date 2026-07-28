import Foundation

/// TEMPORARY INSTRUMENTATION (spec AC-5.1/AC-5.2). Removed in Phase 7.
///
/// The project has no test target, so `SnoozeResolver` — a pure function whose
/// correctness is the entire point of the fix — would otherwise be verified by
/// reading it. This runs the spec's case table at launch and logs one
/// PASS/FAIL line per case, making it checkable from the device store.
enum SnoozeResolverSelfCheck {

    static func run() async {
        let cal = Calendar.current
        // Fixed reference day so cases are deterministic.
        func at(_ h: Int, _ m: Int) -> Date {
            var c = DateComponents()
            c.year = 2026; c.month = 7; c.day = 27; c.hour = h; c.minute = m; c.second = 0
            return cal.date(from: c)!
        }

        let t2142 = at(21, 42)
        let t2350 = at(23, 50)

        var results: [(String, Bool, String)] = []

        func expectOK(
            _ name: String,
            _ res: SnoozeResolver.Resolution,
            minutes: Int,
            clamped: Bool,
            requestedMinutes: Int? = nil
        ) {
            switch res {
            case let .ok(m, returnsAt, requested):
                let okMinutes = m == minutes
                let okClamp = (requested != nil) == clamped
                let okReq = requestedMinutes == nil || requested?.minutes == requestedMinutes
                let detail = "got \(m) min, returns "
                    + ConversationEngine.clock(returnsAt)
                    + (requested.map { ", requested \($0.minutes)" } ?? "")
                results.append((name, okMinutes && okClamp && okReq, detail))
            case let .invalid(msg):
                results.append((name, false, "expected ok, got invalid: \(msg)"))
            }
        }

        func expectInvalid(_ name: String, _ res: SnoozeResolver.Resolution) {
            switch res {
            case .invalid:
                results.append((name, true, "invalid as expected"))
            case let .ok(m, _, _):
                results.append((name, false, "expected invalid, got \(m) min"))
            }
        }

        expectOK("21:42 until=22:00 -> 18",
                 SnoozeResolver.resolve(minutes: nil, until: "22:00", now: t2142),
                 minutes: 18, clamped: false)

        expectOK("23:50 until=06:00 -> 370 clamped to 30",
                 SnoozeResolver.resolve(minutes: nil, until: "06:00", now: t2350),
                 minutes: 30, clamped: true, requestedMinutes: 370)

        expectOK("21:42 minutes=8 -> 8",
                 SnoozeResolver.resolve(minutes: 8, until: nil, now: t2142),
                 minutes: 8, clamped: false)

        expectOK("21:42 until=21:42 -> floored to 1",
                 SnoozeResolver.resolve(minutes: nil, until: "21:42", now: t2142),
                 minutes: 1, clamped: false)

        expectOK("21:42 until=23:00 -> 78 clamped to 30",
                 SnoozeResolver.resolve(minutes: nil, until: "23:00", now: t2142),
                 minutes: 30, clamped: true, requestedMinutes: 78)

        expectInvalid("neither supplied",
                      SnoozeResolver.resolve(minutes: nil, until: nil, now: t2142))

        expectInvalid("both supplied",
                      SnoozeResolver.resolve(minutes: 5, until: "22:00", now: t2142))

        expectInvalid("unparseable until",
                      SnoozeResolver.resolve(minutes: nil, until: "banana", now: t2142))

        for (name, passed, detail) in results {
            await LogService.shared.log(
                .app,
                "PROBE resolver: \(name) — \(passed ? "PASS" : "FAIL") (\(detail))",
                isError: !passed
            )
        }
    }
}
