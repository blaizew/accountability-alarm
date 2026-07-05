import AlarmKit
import Foundation
import SwiftData
import SwiftUI
import AppIntents

/// Local alias so we can reference AlarmKit's `Alarm` type even though our
/// SwiftData model is also called `Alarm`.
private typealias AKAlarm = AlarmKit.Alarm

/// Wraps the iOS 26 AlarmKit API.
///
/// Each Alarm in our model is backed by one (or one-per-weekday) AlarmKit
/// alarm. When the alarm fires, the system shows a full-screen alert with two
/// buttons:
///   • "Talk to past-self" — secondaryIntent runs `OpenConversationIntent`,
///     which launches the app and opens the conversation. This path requires
///     the app to launch, so it doesn't work under Screen Time Downtime.
///   • "Slide to Stop" — stopIntent runs `SnoozeStopIntent`, which schedules
///     a 5-minute snooze in the background. Critically, this runs WITHOUT
///     launching the app, so it works even when Downtime restricts the app.
///
/// The only way to truly silence the alarm is for the user to engage with the
/// conversation and have the LLM authorize Comply.
@MainActor
final class AlarmKitService {
    static let shared = AlarmKitService()
    private init() {}

    private let manager = AlarmManager.shared

    /// Metadata attached to every AlarmKit alarm. Empty for now — we route
    /// state through SwiftData using the alarmId carried on the intents.
    struct Metadata: AlarmMetadata {}

    // MARK: - Observation

    /// Mirror of the set of alarms currently registered with AlarmKit. Updated
    /// by the long-lived task started by `startObserving()`. Used by the
    /// reconcile pass to detect orphaned AlarmKit alarms (those not tied to
    /// any active Alarm in our SwiftData store).
    ///
    /// Wrapped in an actor so the observer task can run *off* the main actor
    /// and not block the launch path while AlarmKit's daemon initializes.
    private actor ObservedState {
        var ids: Set<UUID> = []
        func update(_ next: Set<UUID>) { ids = next }
        func snapshot() -> Set<UUID> { ids }
    }
    private let observed = ObservedState()

    /// Re-entrancy guard for reconcile — scenePhase can flap .active quickly
    /// (app switcher, notification pull-down) and overlapping passes could
    /// double-insert missed events or race the orphan scan.
    private var isReconciling = false

    /// Begin observing AlarmKit's state. Call once at app launch. The task
    /// runs detached so the initial `alarmUpdates` await doesn't block main.
    nonisolated func startObserving() {
        Task.detached(priority: .background) { [weak self] in
            guard let self else { return }
            for await alarms in AlarmManager.shared.alarmUpdates {
                let ids = Set(alarms.map { $0.id })
                await self.observed.update(ids)
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
            await LogService.shared.log(.alarmkit, "requestAuthorization failed: \(error.localizedDescription)", isError: true)
            return false
        }
    }

    // MARK: - Scheduling

    /// Schedules an AlarmKit alarm for the user's configured time.
    /// Returns the UUIDs of the scheduled alarms (one per weekday for repeating,
    /// otherwise one). The caller persists them on the Alarm so we can cancel later.
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
            // One AlarmKit alarm covering all selected weekdays. `.weekly()`
            // accepts an array — passing all weekdays in a single schedule
            // beats N separate alarms (N IDs to track, N chances to orphan).
            let weekdays = alarm.repeatDays.compactMap { WeekdayBridge.from(day1Sun: $0) }
            if !weekdays.isEmpty {
                let time = AKAlarm.Schedule.Relative.Time(hour: alarm.hour, minute: alarm.minute)
                let schedule: AKAlarm.Schedule = .relative(
                    .init(time: time, repeats: .weekly(weekdays))
                )
                if let id = await scheduleOne(alarm: alarm, schedule: schedule, isSnooze: false) {
                    ids.append(id)
                }
            }
        }
        await LogService.shared.log(.alarmkit, "scheduleAlarm: \(ids.count) alarm(s) for \(alarm.label.isEmpty ? "(no label)" : alarm.label) @ \(alarm.hour):\(String(format: "%02d", alarm.minute)) on \(alarm.repeatDays.count) day(s)", alarmId: alarm.id.uuidString)
        return ids
    }

    /// Schedules a one-shot snooze alarm `minutes` from now. Returns the UUID.
    @discardableResult
    func scheduleSnooze(alarm: Alarm, minutes: Int) async -> UUID? {
        let date = Date().addingTimeInterval(TimeInterval(minutes * 60))
        return await scheduleOne(alarm: alarm, schedule: AKAlarm.Schedule.fixed(date), isSnooze: true)
    }

    /// Called from `SnoozeStopIntent` when the user taps the system Stop
    /// button. Cancels any prior pending snooze and schedules a fresh one.
    /// Single source of truth for "Stop tapped — re-ring in N minutes."
    /// Mutates `alarm.pendingSnoozeIdString` and `alarm.snoozedUntil`;
    /// caller is expected to save the context.
    func handleStopSnooze(alarm: Alarm, minutes: Int) async {
        // Never re-arm a disabled alarm — Stop on a still-ringing alert for
        // an alarm the user just toggled off must not schedule anything.
        guard alarm.enabled else {
            await LogService.shared.log(.alarmkit, "handleStopSnooze: alarm disabled — skipping", alarmId: alarm.id.uuidString)
            return
        }
        await LogService.shared.log(.alarmkit, "handleStopSnooze: \(minutes) min", alarmId: alarm.id.uuidString)

        if let s = alarm.pendingSnoozeIdString, let oldId = UUID(uuidString: s) {
            await cancel(alarmKitId: oldId)
        }
        if let newId = await scheduleSnooze(alarm: alarm, minutes: minutes) {
            alarm.pendingSnoozeIdString = newId.uuidString
            alarm.snoozedUntil = Date().addingTimeInterval(TimeInterval(minutes * 60))
        }
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
            stopIntent: SnoozeStopIntent(alarmId: alarm.id.uuidString),
            secondaryIntent: OpenConversationIntent(alarmId: alarm.id.uuidString)
        )
        let id = UUID()
        do {
            _ = try await manager.schedule(id: id, configuration: config)
            return id
        } catch {
            await LogService.shared.log(.alarmkit, "schedule failed: \(error.localizedDescription)", alarmId: alarm.id.uuidString, isError: true)
            return nil
        }
    }

    /// Cancels a scheduled alarm. No-op if already cancelled/fired.
    func cancel(alarmKitId: UUID) async {
        do {
            try manager.cancel(id: alarmKitId)
            await LogService.shared.log(.alarmkit, "cancel \(alarmKitId.uuidString.prefix(8))", alarmKitId: alarmKitId.uuidString)
        } catch {
            // Already cancelled or fired — fine.
        }
    }

    /// Stops a currently-ringing alarm. Different from cancel — stop silences
    /// an actively-firing alarm, cancel removes a scheduled future alarm.
    /// Idempotent and error-tolerant.
    func stop(alarmKitId: UUID) async {
        do {
            try manager.stop(id: alarmKitId)
            await LogService.shared.log(.alarmkit, "stop \(alarmKitId.uuidString.prefix(8))", alarmKitId: alarmKitId.uuidString)
        } catch {
            // Not currently ringing — fine, that's the common case.
        }
    }

    /// Stops every AlarmKit alarm associated with this Alarm record. Called
    /// when the conversation opens to silence anything actively ringing —
    /// covers the Downtime-collision case where the secondary button tap
    /// didn't dispatch the intent in time to silence the original alarm.
    func stopAllActive(_ alarm: Alarm) async {
        for s in alarm.alarmKitIdStrings {
            if let id = UUID(uuidString: s) { await stop(alarmKitId: id) }
        }
        if let s = alarm.pendingSnoozeIdString, let id = UUID(uuidString: s) {
            await stop(alarmKitId: id)
        }
        await stopAnyAlerting()
    }

    /// Stop every alarm AlarmKit reports as actively alerting. Every alarm
    /// in the manager's list belongs to this app, so this is always safe —
    /// and it's the only way to silence a ringer whose ID we lost track of
    /// (orphans from older builds, clobbered pendingSnooze records). A
    /// ringing phone with no working Stop affordance forces the user to
    /// reboot; this sweep is the backstop against that.
    func stopAnyAlerting() async {
        guard let live = try? manager.alarms else { return }
        for a in live where a.state == .alerting {
            await LogService.shared.log(.alarmkit, "stopAnyAlerting: stopping alerting \(a.id.uuidString.prefix(8))", alarmKitId: a.id.uuidString)
            await stop(alarmKitId: a.id)
        }
    }

    // MARK: - Reconciliation

    /// Run on every app open / scene becoming active. Does three things:
    ///   1. For each disabled alarm, ensure all of its AlarmKit IDs are
    ///      cancelled (cleans up any straggler from a previous bad shutdown).
    ///   2. Cross-reference AlarmKit's current alarm set against the
    ///      SwiftData store and cancel any orphans — AlarmKit alarms not
    ///      tracked by any Alarm record. This handles the "user deleted an
    ///      alarm but cancellation didn't complete" case.
    ///   3. Record firings the user never engaged with as "ignored" ledger
    ///      entries, and close out abandoned wake-up chains. No re-ring is
    ///      scheduled — by design a firing nobody touches ends the chain —
    ///      but the ledger has to tell the truth about it.
    ///
    /// The caller is expected to `try? context.save()` afterwards.
    @MainActor
    func reconcileOnAppOpen(alarms: [Alarm], context: ModelContext) async {
        guard !isReconciling else { return }
        isReconciling = true
        defer { isReconciling = false }

        await LogService.shared.log(.app, "reconcileOnAppOpen: \(alarms.count) alarms")

        var trackedIds: Set<UUID> = []
        for alarm in alarms {
            await Task.yield()

            if !alarm.enabled {
                let hasDanglers = !alarm.alarmKitIdStrings.isEmpty
                    || alarm.pendingSnoozeIdString != nil
                if hasDanglers {
                    await cancelAlarm(alarm)
                    alarm.alarmKitIdStrings = []
                    alarm.pendingSnoozeIdString = nil
                }
                continue
            }

            for s in alarm.alarmKitIdStrings {
                if let u = UUID(uuidString: s) { trackedIds.insert(u) }
            }
            if let s = alarm.pendingSnoozeIdString, let u = UUID(uuidString: s) {
                trackedIds.insert(u)
            }
        }

        // Orphan cleanup. Query AlarmKit directly — the alarmUpdates observer
        // may not have emitted yet this early in a launch, and skipping the
        // pass on an empty snapshot left orphans alive for the whole session.
        let observedIds: Set<UUID>
        if let live = try? manager.alarms {
            observedIds = Set(live.map(\.id))
        } else {
            observedIds = await observed.snapshot()
        }
        let orphans = observedIds.subtracting(trackedIds)
        if !orphans.isEmpty {
            await LogService.shared.log(.app, "reconcile: cancelling \(orphans.count) orphan AlarmKit alarms")
        }
        for orphanId in orphans {
            await Task.yield()
            await cancel(alarmKitId: orphanId)
        }

        await recordMissedFirings(alarms: alarms, context: context)
        await closeAbandonedChains(context: context)

        // A ghost ringer (alerting alarm nobody can stop) should die the
        // moment the app is opened, whatever else is going on.
        await stopAnyAlerting()
    }

    /// A firing counts as engaged if ANY AlarmEvent exists near the due time
    /// — both opening the conversation and tapping the system Stop button
    /// create (or reuse) the chain's event. No event, no live snooze, and
    /// we're past the grace window ⇒ the user slept through it, muted it
    /// with a hardware button, or swiped the alert away. None of those are
    /// detectable in the moment (AlarmKit gives no callback), so this is
    /// where the ledger learns the day was missed.
    private func recordMissedFirings(alarms: [Alarm], context: ModelContext) async {
        let now = Date()
        for alarm in alarms {
            guard alarm.enabled else { continue }
            // A live snooze means the chain is still in flight — not missed.
            if let until = alarm.snoozedUntil, until > now { continue }
            guard let due = lastDueFireDate(for: alarm, now: now) else { continue }
            guard due > alarm.createdAt else { continue }

            let graceEnd = due.addingTimeInterval(TimeInterval(Constants.missedGraceMinutes) * 60)
            let lookbackEnd = due.addingTimeInterval(TimeInterval(Constants.missedLookbackHours) * 3600)
            guard now > graceEnd, now < lookbackEnd else { continue }

            // Any event at/after (or shortly before) the due time — pending,
            // resolved, or an earlier "ignored" from a previous pass — means
            // this firing is already accounted for.
            let window = due.addingTimeInterval(-3600)
            if alarm.events.contains(where: { $0.firedAt > window }) { continue }

            let missed = AlarmEvent(alarm: alarm)
            missed.firedAt = due
            missed.outcome = "ignored"
            context.insert(missed)
            await LogService.shared.log(
                .app,
                "reconcile: recorded ignored firing (no engagement) due=\(due)",
                alarmId: alarm.id.uuidString
            )
        }
    }

    /// Close wake-up chains that started (Stop tapped or conversation
    /// opened) but were then abandoned — the pending event would otherwise
    /// sit unresolved forever and silently vanish from compliance stats.
    private func closeAbandonedChains(context: ModelContext) async {
        let cutoff = Date().addingTimeInterval(-TimeInterval(Constants.chainWindowHours) * 3600)
        let predicate = #Predicate<AlarmEvent> {
            $0.outcome == "pending" && $0.firedAt < cutoff
        }
        guard let stale = try? context.fetch(FetchDescriptor(predicate: predicate)) else { return }
        for event in stale {
            // Chain snoozed into the future is still alive; leave it.
            if let until = event.alarm?.snoozedUntil, until > Date() { continue }
            event.outcome = "ignored"
            await LogService.shared.log(
                .app,
                "reconcile: closed abandoned chain as ignored (fired \(event.firedAt))",
                alarmId: event.alarm?.id.uuidString
            )
        }
    }

    /// The most recent scheduled fire time that is in the past, or nil if
    /// this alarm hasn't been due yet.
    ///
    /// Repeating alarms are exact (weekday + hour:minute). One-shots are an
    /// approximation — the first hour:minute occurrence after creation —
    /// because the original scheduled date isn't persisted; the caller's
    /// createdAt/grace/lookback guards bound the error.
    private func lastDueFireDate(for alarm: Alarm, now: Date) -> Date? {
        let cal = Calendar.current

        if alarm.repeatDays.isEmpty {
            var comps = cal.dateComponents([.year, .month, .day], from: alarm.createdAt)
            comps.hour = alarm.hour
            comps.minute = alarm.minute
            comps.second = 0
            guard var candidate = cal.date(from: comps) else { return nil }
            if candidate <= alarm.createdAt {
                candidate = cal.date(byAdding: .day, value: 1, to: candidate) ?? candidate
            }
            return candidate <= now ? candidate : nil
        }

        // Walk back day by day to the latest scheduled weekday occurrence.
        for back in 0..<8 {
            guard let day = cal.date(byAdding: .day, value: -back, to: now) else { continue }
            var comps = cal.dateComponents([.year, .month, .day], from: day)
            comps.hour = alarm.hour
            comps.minute = alarm.minute
            comps.second = 0
            guard let candidate = cal.date(from: comps), candidate <= now else { continue }
            let weekday = cal.component(.weekday, from: candidate) // 1=Sun matches repeatDays
            if alarm.repeatDays.contains(weekday) { return candidate }
        }
        return nil
    }

    func cancelAlarm(_ alarm: Alarm) async {
        for s in alarm.alarmKitIdStrings {
            if let id = UUID(uuidString: s) { await cancel(alarmKitId: id) }
        }
        if let s = alarm.pendingSnoozeIdString, let id = UUID(uuidString: s) {
            await cancel(alarmKitId: id)
        }
    }

    // MARK: - Helpers

    private func alertContent(for alarm: Alarm, isSnooze: Bool = false) -> AlarmPresentation.Alert {
        // Title = the alarm's label. AlarmKit renders this large; long
        // instructional text gets truncated and is unreadable.
        let title = LocalizedStringResource(
            stringLiteral: alarm.label.isEmpty ? "Alarm" : alarm.label
        )

        let talkButton = AlarmButton(
            text: "Talk to past-self",
            textColor: .white,
            systemImageName: "bubble.left.and.bubble.right"
        )

        // iOS 26.1+: the stopButton parameter is deprecated. The system now
        // owns the stop affordance — we supply behavior via `stopIntent` on
        // the AlarmConfiguration.
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
}
