import Foundation
import SwiftData

@Model
final class AlarmEvent {
    var alarm: Alarm?
    var firedAt: Date = Date()
    var outcome: String = "pending" // complied, snoozed_then_complied, overridden, ignored
    var snoozeCount: Int = 0
    var overrideReason: String?
    var conversationLogData: Data?
    var complianceTimeMinutes: Int = 0
    /// Timestamped snoozes for this chain. Parallel to `snoozeCount`, which
    /// stays the authority for the escalation ladder — events created before
    /// this field existed have a count but no records, and are not migrated.
    var snoozeLogData: Data?

    var conversationLog: [ConversationMessage] {
        get {
            guard let data = conversationLogData else { return [] }
            return (try? JSONDecoder().decode([ConversationMessage].self, from: data)) ?? []
        }
        set {
            conversationLogData = try? JSONEncoder().encode(newValue)
        }
    }

    var snoozeLog: [SnoozeRecord] {
        get {
            guard let data = snoozeLogData else { return [] }
            return (try? JSONDecoder().decode([SnoozeRecord].self, from: data)) ?? []
        }
        set {
            snoozeLogData = try? JSONEncoder().encode(newValue)
        }
    }

    /// Snoozes counted but never timestamped — legacy events from before
    /// `snoozeLog` existed. The timeline accounts for these explicitly rather
    /// than rendering an incomplete list as though it were whole.
    var unrecordedSnoozeCount: Int {
        max(0, snoozeCount - snoozeLog.count)
    }

    /// The ONLY way to register a snooze. Bumps the count and appends the
    /// record together so the two can never drift. Every source counts toward
    /// the escalation ladder without exception; `source` informs the Coach's
    /// tone, never the count.
    func recordSnooze(
        minutes: Int,
        source: SnoozeRecord.Source,
        at: Date = Date(),
        isApproximate: Bool = false
    ) {
        snoozeCount += 1
        snoozeLog.append(
            SnoozeRecord(at: at, minutes: minutes, source: source, isApproximate: isApproximate)
        )
    }

    init(alarm: Alarm) {
        self.alarm = alarm
        self.firedAt = Date()
    }

    /// The alarm's currently-open wake-up chain, if any.
    ///
    /// One AlarmEvent spans the whole chain — first fire through final
    /// outcome — across every snooze, re-ring, and re-opened conversation.
    /// Both the conversation and the system Stop intent MUST reuse this
    /// instead of inserting a fresh event, otherwise `snoozeCount` resets to
    /// 0 on every re-ring and the LLM's skepticism ladder never engages.
    /// Adopts a recent `ignored` verdict if there's no live chain. Reconcile
    /// records `ignored` as its best read at the time it clears a firing;
    /// engagement afterwards is strictly better evidence, so the ledger
    /// changes its mind rather than keeping two rows for one night.
    static func openChain(for alarm: Alarm) -> AlarmEvent? {
        let cutoff = Date().addingTimeInterval(-TimeInterval(Constants.chainWindowHours) * 3600)
        let recent = alarm.events.filter { $0.firedAt > cutoff }

        if let pending = recent
            .filter({ $0.outcome == "pending" })
            .max(by: { $0.firedAt < $1.firedAt }) {
            return pending
        }

        if let ignored = recent
            .filter({ $0.outcome == "ignored" })
            .max(by: { $0.firedAt < $1.firedAt }) {
            ignored.outcome = "pending"
            return ignored
        }

        return nil
    }
}
