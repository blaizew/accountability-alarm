import AlarmKit
import Foundation
import SwiftUI
import AppIntents

/// Local alias so we can reference AlarmKit's `Alarm` type even though our
/// SwiftData model is also called `Alarm`.
private typealias AKAlarm = AlarmKit.Alarm

/// Wraps the iOS 26 AlarmKit API.
///
/// AlarmKit alarms ring through Silent, DnD, and Focus modes at alarm-tier
/// volume — no Critical Alerts entitlement required. Each Alarm in our model
/// is backed by one (or one-per-weekday) AlarmKit alarm. When the alarm fires,
/// the system shows a full-screen alert with two buttons:
///   • "Talk to past-self" — runs OpenConversationIntent, which launches the
///     app and opens the conversation.
///   • Stop — the standard system stop (Apple may force this to exist).
/// The pre-emptive-snooze safety net (scheduled when the conversation opens)
/// catches users who tap the system Stop or never engage.
@MainActor
final class AlarmKitService {
    static let shared = AlarmKitService()
    private init() {}

    private let manager = AlarmManager.shared

    /// Metadata payload attached to every AlarmKit alarm. We don't need much —
    /// the alarmId on the App Intent is sufficient to route into the right
    /// conversation. This empty Metadata satisfies the generic constraint.
    struct Metadata: AlarmMetadata {}

    // MARK: - Observation

    /// Mirror of the set of alarms currently registered with AlarmKit. Updated
    /// by the long-lived task started by `startObserving()`. Used by the
    /// reconcile pass to detect orphaned AlarmKit alarms (those not tied to
    /// any active Alarm in our SwiftData store).
    private var observedAlarmKitIds: Set<UUID> = []
    private var observerTask: Task<Void, Never>?

    /// Begin observing AlarmKit's state. Call once at app launch.
    func startObserving() {
        guard observerTask == nil else { return }
        observerTask = Task { [weak self] in
            guard let self else { return }
            for await alarms in self.manager.alarmUpdates {
                self.observedAlarmKitIds = Set(alarms.map { $0.id })
            }
        }
    }

    // MARK: - Authorization

    var authorizationState: AlarmManager.AuthorizationState {
        manager.authorizationState
    }

    @discardableResult
    func requestAuthorization() async -> Bool {
        do {
            let state = try await manager.requestAuthorization()
            return state == .authorized
        } catch {
            return false
        }
    }

    // MARK: - Scheduling

    /// Schedules an AlarmKit alarm for the user's configured time.
    /// Returns the UUIDs of the scheduled alarms (one per weekday for repeating,
    /// otherwise one). The caller persists them on the Alarm so we can cancel later.
    /// Schedules T+0 (recurring weekly for repeating alarms, or one-shot for
    /// non-repeating) and bootstraps the first T+1 companion. Subsequent T+1
    /// companions are refreshed lazily by `refreshNextCompanion(_:)` whenever
    /// the user interacts with an alarm, so each companion remains
    /// individually cancellable on the next interaction.
    @discardableResult
    func scheduleAlarm(_ alarm: Alarm) async -> [UUID] {
        await cancelAlarm(alarm)
        guard alarm.enabled else { return [] }

        var ids: [UUID] = []

        if alarm.repeatDays.isEmpty {
            let originalDate = nextOccurrence(hour: alarm.hour, minute: alarm.minute)
            if let id = await scheduleOne(alarm: alarm, schedule: AKAlarm.Schedule.fixed(originalDate), isSnooze: false) {
                ids.append(id)
            }
        } else {
            for day in alarm.repeatDays {
                guard let weekday = WeekdayBridge.from(day1Sun: day) else { continue }
                let time = AKAlarm.Schedule.Relative.Time(hour: alarm.hour, minute: alarm.minute)
                let schedule: AKAlarm.Schedule = .relative(
                    .init(time: time, repeats: .weekly([weekday]))
                )
                if let id = await scheduleOne(alarm: alarm, schedule: schedule, isSnooze: false) {
                    ids.append(id)
                }
            }
        }
        return ids
    }

    /// Bootstrap the FIRST T+1 companion. Called at alarm creation / edit /
    /// re-enable time. For one-shot alarms this schedules T+1 for that one
    /// occurrence. For recurring it schedules T+1 for the next upcoming T+0.
    @discardableResult
    func scheduleFirstCompanion(for alarm: Alarm) async -> UUID? {
        let nextT0 = nextRecurringOrUpcomingT0(for: alarm)
        guard let nextT0 else { return nil }
        let t1Date = nextT0.addingTimeInterval(60)
        return await scheduleOne(alarm: alarm, schedule: AKAlarm.Schedule.fixed(t1Date), isSnooze: false)
    }

    /// Refresh the T+1 companion when the user is interacting with an
    /// already-fired T+0. Cancels the imminent T+1 (today's — about to fire
    /// or just fired) and, for recurring alarms, schedules a fresh one-shot
    /// for the next future T+0. For one-shot alarms returns nil — there's
    /// no "next instance" once the T+0 has been consumed.
    @discardableResult
    func refreshNextCompanion(for alarm: Alarm) async -> UUID? {
        if let s = alarm.nextT1IdString, let oldId = UUID(uuidString: s) {
            await cancel(alarmKitId: oldId)
        }
        guard !alarm.repeatDays.isEmpty else { return nil }
        guard let nextT0 = nextRecurringT0(for: alarm) else { return nil }
        let t1Date = nextT0.addingTimeInterval(60)
        return await scheduleOne(alarm: alarm, schedule: AKAlarm.Schedule.fixed(t1Date), isSnooze: false)
    }

    /// Next T+0 datetime: for recurring, the next weekday match; for one-shot,
    /// the next hour:minute occurrence (rolls forward if today's time is past).
    private func nextRecurringOrUpcomingT0(for alarm: Alarm) -> Date? {
        if alarm.repeatDays.isEmpty {
            return nextOccurrence(hour: alarm.hour, minute: alarm.minute)
        }
        return nextRecurringT0(for: alarm)
    }

    /// Next future T+0 datetime for a *recurring* alarm. Nil if no weekday
    /// in the next 7 days matches. Past today's time-of-day on a matching
    /// weekday is correctly skipped.
    private func nextRecurringT0(for alarm: Alarm) -> Date? {
        let cal = Calendar.current
        let now = Date()
        var earliest: Date?
        for offset in 0...7 {
            guard let day = cal.date(byAdding: .day, value: offset, to: now) else { continue }
            let weekday = cal.component(.weekday, from: day)
            guard alarm.repeatDays.contains(weekday) else { continue }
            var comps = cal.dateComponents([.year, .month, .day], from: day)
            comps.hour = alarm.hour
            comps.minute = alarm.minute
            comps.second = 0
            guard let datetime = cal.date(from: comps), datetime > now else { continue }
            if earliest == nil || datetime < earliest! {
                earliest = datetime
            }
        }
        return earliest
    }

    /// Schedules a one-shot snooze alarm `minutes` from now. Returns the UUID.
    @discardableResult
    func scheduleSnooze(alarm: Alarm, minutes: Int) async -> UUID? {
        let date = Date().addingTimeInterval(TimeInterval(minutes * 60))
        return await scheduleOne(alarm: alarm, schedule: AKAlarm.Schedule.fixed(date), isSnooze: true)
    }

    /// Single schedule-call helper. The explicit type annotation pins down the
    /// generic `Metadata` parameter so type inference doesn't fail.
    private func scheduleOne(alarm: Alarm, schedule: AKAlarm.Schedule, isSnooze: Bool) async -> UUID? {
        let attributes = AlarmAttributes<Metadata>(
            presentation: AlarmPresentation(alert: alertContent(for: alarm, isSnooze: isSnooze)),
            metadata: Metadata(),
            tintColor: Color.orange
        )
        let config: AlarmManager.AlarmConfiguration<Metadata> = .init(
            schedule: schedule,
            attributes: attributes,
            secondaryIntent: OpenConversationIntent(alarmId: alarm.id.uuidString)
        )
        let id = UUID()
        do {
            _ = try await manager.schedule(id: id, configuration: config)
            return id
        } catch {
            NSLog("AlarmKit schedule failed: \(error.localizedDescription)")
            return nil
        }
    }

    func cancel(alarmKitId: UUID) async {
        do {
            try manager.cancel(id: alarmKitId)
        } catch {
            // Already cancelled or fired — fine.
        }
    }

    // MARK: - Reconciliation

    /// Run on every app open / scene becoming active. Does three things:
    ///   1. For each enabled recurring alarm, refresh the T+1 companion so
    ///      it always points at the next upcoming occurrence.
    ///   2. For each disabled alarm, ensure all of its AlarmKit IDs are
    ///      cancelled (cleans up any straggler from a previous bad shutdown).
    ///   3. Cross-reference AlarmKit's current alarm set (from the
    ///      `alarmUpdates` observer) against the SwiftData store and cancel
    ///      any orphans — AlarmKit alarms not tracked by any Alarm record.
    ///      This handles the "user deleted an alarm but cancellation didn't
    ///      complete" case.
    ///
    /// The caller is expected to `try? context.save()` afterwards.
    @MainActor
    func reconcileOnAppOpen(alarms: [Alarm]) async {
        // 1 & 2: SwiftData-driven reconcile.
        var trackedIds: Set<UUID> = []
        for alarm in alarms {
            if !alarm.enabled {
                await cancelAlarm(alarm)
                alarm.alarmKitIdStrings = []
                alarm.nextT1IdString = nil
                alarm.pendingSnoozeIdString = nil
                continue
            }
            // For recurring alarms, refresh the T+1 companion. (No-op for
            // one-shots, which can't have a "next instance".)
            if !alarm.repeatDays.isEmpty {
                let newT1 = await refreshNextCompanion(for: alarm)
                alarm.nextT1IdString = newT1?.uuidString
            }
            // Collect all IDs this alarm still owns.
            for s in alarm.alarmKitIdStrings {
                if let u = UUID(uuidString: s) { trackedIds.insert(u) }
            }
            if let s = alarm.nextT1IdString, let u = UUID(uuidString: s) {
                trackedIds.insert(u)
            }
            if let s = alarm.pendingSnoozeIdString, let u = UUID(uuidString: s) {
                trackedIds.insert(u)
            }
        }

        // 3: Orphan cleanup. `observedAlarmKitIds` is populated by the
        // alarmUpdates observer. If observation hasn't emitted yet (first
        // launch before any state change), this set is empty and the
        // orphan pass is a no-op — which is fine; nothing to clean up.
        let orphans = observedAlarmKitIds.subtracting(trackedIds)
        for orphanId in orphans {
            await cancel(alarmKitId: orphanId)
        }
    }

    func cancelAlarm(_ alarm: Alarm) async {
        for s in alarm.alarmKitIdStrings {
            if let id = UUID(uuidString: s) { await cancel(alarmKitId: id) }
        }
        if let s = alarm.pendingSnoozeIdString, let id = UUID(uuidString: s) {
            await cancel(alarmKitId: id)
        }
        if let s = alarm.nextT1IdString, let id = UUID(uuidString: s) {
            await cancel(alarmKitId: id)
        }
    }

    // MARK: - Helpers

    private func alertContent(for alarm: Alarm, isSnooze: Bool = false) -> AlarmPresentation.Alert {
        // Every alarm fire — original or companion — uses the same title so
        // the user can't tell from the UI whether they've already missed one.
        let title: LocalizedStringResource = "Talk to Past Self or alarm will sound again in 1 minute"

        let talkButton = AlarmButton(
            text: "Talk to past-self",
            textColor: .white,
            systemImageName: "bubble.left.and.bubble.right"
        )

        // iOS 26.1+: the stopButton parameter is deprecated. The system now
        // owns the stop affordance — we only supply the secondary action.
        return AlarmPresentation.Alert(
            title: title,
            secondaryButton: talkButton,
            secondaryButtonBehavior: .custom
        )
    }

    /// Compute the next Date matching the given hour:minute. If today's
    /// time has already passed, rolls to tomorrow.
    private func nextOccurrence(hour: Int, minute: Int) -> Date {
        let cal = Calendar.current
        let now = Date()
        var components = cal.dateComponents([.year, .month, .day], from: now)
        components.hour = hour
        components.minute = minute
        components.second = 0
        guard let candidate = cal.date(from: components) else {
            return now.addingTimeInterval(60)
        }
        if candidate <= now {
            return cal.date(byAdding: .day, value: 1, to: candidate) ?? candidate
        }
        return candidate
    }
}

// MARK: - Weekday bridging

private enum WeekdayBridge {
    /// Our model uses 1=Sun ... 7=Sat. Returns the AlarmKit weekday or nil.
    static func from(day1Sun: Int) -> Locale.Weekday? {
        switch day1Sun {
        case 1: return .sunday
        case 2: return .monday
        case 3: return .tuesday
        case 4: return .wednesday
        case 5: return .thursday
        case 6: return .friday
        case 7: return .saturday
        default: return nil
        }
    }

    /// Next weekday in calendar order. Used for the companion alarm when it
    /// crosses midnight relative to the original.
    static func next(_ day: Locale.Weekday) -> Locale.Weekday {
        switch day {
        case .sunday:    return .monday
        case .monday:    return .tuesday
        case .tuesday:   return .wednesday
        case .wednesday: return .thursday
        case .thursday:  return .friday
        case .friday:    return .saturday
        case .saturday:  return .sunday
        @unknown default: return day
        }
    }
}
