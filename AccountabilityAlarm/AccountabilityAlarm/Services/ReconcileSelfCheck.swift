import Foundation
import SwiftData

/// TEMPORARY INSTRUMENTATION (spec AC-3.1/AC-3.3 logic half). Removed in Phase 7.
///
/// Regression test for the ordering hazard: `detectCountdownSnoozes` MUST run
/// before `recordMissedFirings`. Get it wrong and a snoozed night is logged
/// `ignored` while the event materialises a moment later — the app's own UI
/// looks correct and only the store is wrong, which is exactly the kind of bug
/// that survives a casual check.
///
/// Runs in an **in-memory** container against synthetic AlarmKit state. It does
/// not replace the device tests (a real alert, a real tap, a suspended
/// process); it catches the logic and ordering errors without needing them.
enum ReconcileSelfCheck {

    @MainActor
    static func run() async {
        var checks: [(String, Bool, String)] = []

        func makeStore() throws -> ModelContext {
            let config = ModelConfiguration(isStoredInMemoryOnly: true)
            return ModelContext(try ModelContainer(for: Alarm.self, AlarmEvent.self, configurations: config))
        }

        /// An alarm that fired earlier today and is now counting down.
        func fixture(_ ctx: ModelContext, now: Date) -> (Alarm, Set<UUID>) {
            let cal = Calendar.current
            let due = cal.date(byAdding: .minute, value: -40, to: now)!
            let comps = cal.dateComponents([.hour, .minute], from: due)

            let alarm = Alarm(label: "reconcile-check", hour: comps.hour!, minute: comps.minute!)
            // Repeating, so lastDueFireDate resolves to today's occurrence 40
            // minutes ago. A one-shot alarm derives its due date from
            // createdAt's day, which would put it outside missedLookbackHours
            // and make every case below vacuously pass.
            alarm.repeatDays = [1, 2, 3, 4, 5, 6, 7]
            alarm.createdAt = cal.date(byAdding: .day, value: -3, to: now)!
            let akId = UUID()
            alarm.alarmKitIdStrings = [akId.uuidString]
            ctx.insert(alarm)
            return (alarm, [akId])
        }

        let service = AlarmKitService.shared
        let now = Date()

        // 1. Correct order: detect, THEN record misses. One pending event with
        //    the snooze on it, and no "ignored".
        do {
            let ctx = try makeStore()
            let (alarm, countingDown) = fixture(ctx, now: now)

            await service.detectCountdownSnoozes(
                alarms: [alarm], countingDown: countingDown, context: ctx, now: now
            )
            await service.recordMissedFirings(
                alarms: [alarm], countingDown: countingDown, context: ctx, now: now
            )

            let events = alarm.events
            let onlyOne = events.count == 1
            let pending = events.first?.outcome == "pending"
            let counted = (events.first?.snoozeCount ?? 0) == 1
            let isCountdown = events.first?.snoozeLog.first?.source == .countdown
            let noIgnored = !events.contains { $0.outcome == "ignored" }
            checks.append((
                "AC-3.3 correct order: 1 pending event, no ignored",
                onlyOne && pending && counted && isCountdown && noIgnored,
                "events=\(events.count) outcome=\(events.first?.outcome ?? "-") count=\(events.first?.snoozeCount ?? -1)"
            ))
        } catch { checks.append(("AC-3.3 correct order", false, "\(error)")) }

        // 2. Run them in the WRONG order. This was written expecting a false
        //    "ignored" to survive — it doesn't, and the reason matters:
        //    recordMissedFirings does write one, then detectCountdownSnoozes
        //    calls openChain, which ADOPTS that row and reopens it as pending.
        //    The two fixes compose, so the ordering hazard is self-healing.
        //
        //    Ordering is kept anyway: it avoids a transient wrong state and a
        //    redundant write, and adoption is bounded by the chain window, so
        //    it is not guaranteed to cover every future case. Defence in
        //    depth, not redundancy. Asserted here so the interaction is
        //    recorded rather than rediscovered.
        do {
            let ctx = try makeStore()
            let (alarm, countingDown) = fixture(ctx, now: now)

            await service.recordMissedFirings(
                alarms: [alarm], countingDown: [], context: ctx, now: now
            )
            await service.detectCountdownSnoozes(
                alarms: [alarm], countingDown: countingDown, context: ctx, now: now
            )

            let repaired = alarm.events.count == 1
                && alarm.events.first?.outcome == "pending"
                && !alarm.events.contains { $0.outcome == "ignored" }
            checks.append((
                "AC-3.3 wrong order is repaired by adoption",
                repaired,
                "events=\(alarm.events.count) outcomes=\(alarm.events.map(\.outcome).joined(separator: ","))"
            ))
        } catch { checks.append(("AC-3.3 wrong-order control", false, "\(error)")) }

        // 3. Repeated snoozes accumulate on ONE event rather than fragmenting.
        do {
            let ctx = try makeStore()
            let (alarm, countingDown) = fixture(ctx, now: now)

            for i in 0..<3 {
                let t = now.addingTimeInterval(TimeInterval(i) * 300)
                alarm.snoozedUntil = nil  // the previous snooze has elapsed
                await service.detectCountdownSnoozes(
                    alarms: [alarm], countingDown: countingDown, context: ctx, now: t
                )
            }

            let onlyOne = alarm.events.count == 1
            let counted = (alarm.events.first?.snoozeCount ?? 0) == 3
            checks.append((
                "AC-3.3 three snoozes accumulate on one event",
                onlyOne && counted,
                "events=\(alarm.events.count) count=\(alarm.events.first?.snoozeCount ?? -1)"
            ))
        } catch { checks.append(("AC-3.3 accumulation", false, "\(error)")) }

        // 4. No countdown, no engagement ⇒ the firing IS recorded ignored.
        //    Without this, check 1 would also pass if we simply never recorded
        //    anything.
        do {
            let ctx = try makeStore()
            let (alarm, _) = fixture(ctx, now: now)

            await service.detectCountdownSnoozes(
                alarms: [alarm], countingDown: [], context: ctx, now: now
            )
            await service.recordMissedFirings(
                alarms: [alarm], countingDown: [], context: ctx, now: now
            )

            let ignored = alarm.events.filter { $0.outcome == "ignored" }
            checks.append((
                "AC-2.6 untouched firing is recorded ignored",
                ignored.count == 1,
                "events=\(alarm.events.count) ignored=\(ignored.count)"
            ))
        } catch { checks.append(("AC-2.6 untouched firing", false, "\(error)")) }

        for (name, passed, detail) in checks {
            await LogService.shared.log(
                .app,
                "PROBE reconcile: \(name) — \(passed ? "PASS" : "FAIL") (\(detail))",
                isError: !passed
            )
        }
    }
}
