import Foundation
import SwiftData

/// TEMPORARY INSTRUMENTATION (spec AC-1.3, AC-2.4). Removed in Phase 7.
///
/// Exercises the ledger invariants that are pure model logic — the snooze
/// record/count pairing, and `openChain` adopting an `ignored` verdict rather
/// than starting a second row for the same night.
///
/// Runs entirely in an **in-memory** container. It must never touch the real
/// store: that holds Blaize's actual alarms and history, and a self-check that
/// mutates user data is worse than no self-check (spec AC-X1).
enum LedgerSelfCheck {

    @MainActor
    static func run() async {
        var checks: [(String, Bool, String)] = []

        do {
            let config = ModelConfiguration(isStoredInMemoryOnly: true)
            let container = try ModelContainer(
                for: Alarm.self, AlarmEvent.self,
                configurations: config
            )
            let ctx = container.mainContext

            // AC-1.3 — recordSnooze bumps the count and appends a record together.
            do {
                let alarm = Alarm(label: "check", hour: 21, minute: 30)
                ctx.insert(alarm)
                let event = AlarmEvent(alarm: alarm)
                ctx.insert(event)

                let countBefore = event.snoozeCount
                let logBefore = event.snoozeLog.count
                event.recordSnooze(minutes: 5, source: .countdown, isApproximate: true)
                event.recordSnooze(minutes: 3, source: .coach)

                let countOK = event.snoozeCount == countBefore + 2
                let logOK = event.snoozeLog.count == logBefore + 2
                let roundTripOK = event.snoozeLog.first?.source == .countdown
                    && event.snoozeLog.first?.minutes == 5
                    && event.snoozeLog.first?.isApproximate == true
                    && event.snoozeLog.last?.source == .coach
                    && event.snoozeLog.last?.isApproximate == false
                checks.append((
                    "AC-1.3 recordSnooze pairs count+record",
                    countOK && logOK && roundTripOK,
                    "count \(event.snoozeCount), log \(event.snoozeLog.count)"
                ))

                // AC-4.3 — counted-but-untimestamped legacy snoozes.
                event.snoozeCount += 1
                checks.append((
                    "AC-4.3 unrecordedSnoozeCount",
                    event.unrecordedSnoozeCount == 1,
                    "got \(event.unrecordedSnoozeCount)"
                ))
            }

            // AC-2.4 — openChain adopts a recent `ignored` and reopens it.
            do {
                let alarm = Alarm(label: "adopt", hour: 21, minute: 30)
                ctx.insert(alarm)
                let ignored = AlarmEvent(alarm: alarm)
                ignored.firedAt = Date().addingTimeInterval(-600)
                ignored.outcome = "ignored"
                ctx.insert(ignored)
                alarm.events = [ignored]

                let adopted = AlarmEvent.openChain(for: alarm)
                checks.append((
                    "AC-2.4 adopts recent ignored",
                    adopted === ignored && ignored.outcome == "pending",
                    "returned \(adopted == nil ? "nil" : ignored.outcome)"
                ))
            }

            // A live pending chain wins over any ignored row.
            do {
                let alarm = Alarm(label: "prefer-pending", hour: 21, minute: 30)
                ctx.insert(alarm)
                let ignored = AlarmEvent(alarm: alarm)
                ignored.firedAt = Date().addingTimeInterval(-900)
                ignored.outcome = "ignored"
                let pending = AlarmEvent(alarm: alarm)
                pending.firedAt = Date().addingTimeInterval(-300)
                ctx.insert(ignored); ctx.insert(pending)
                alarm.events = [ignored, pending]

                let chosen = AlarmEvent.openChain(for: alarm)
                checks.append((
                    "AC-2.4 prefers pending over ignored",
                    chosen === pending && ignored.outcome == "ignored",
                    "ignored stayed \(ignored.outcome)"
                ))
            }

            // An ancient ignored row is NOT resurrected — the chain window
            // bounds adoption, so last week's miss can't become tonight.
            do {
                let alarm = Alarm(label: "stale", hour: 21, minute: 30)
                ctx.insert(alarm)
                let old = AlarmEvent(alarm: alarm)
                old.firedAt = Date().addingTimeInterval(-TimeInterval(Constants.chainWindowHours + 2) * 3600)
                old.outcome = "ignored"
                ctx.insert(old)
                alarm.events = [old]

                let chosen = AlarmEvent.openChain(for: alarm)
                checks.append((
                    "AC-2.4 ignores stale ignored rows",
                    chosen == nil && old.outcome == "ignored",
                    "returned \(chosen == nil ? "nil" : "an event")"
                ))
            }

        } catch {
            checks.append(("in-memory container", false, "\(error)"))
        }

        for (name, passed, detail) in checks {
            await LogService.shared.log(
                .app,
                "PROBE ledger: \(name) — \(passed ? "PASS" : "FAIL") (\(detail))",
                isError: !passed
            )
        }
    }
}
