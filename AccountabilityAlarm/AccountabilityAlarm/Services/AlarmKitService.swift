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
///   • "Slide to Stop" — stopIntent runs `OpenConversationIntent`, which
///     launches the app and opens the conversation. This path requires the
///     app to launch, so it doesn't work under Screen Time Downtime.
///   • "Snooze 5 min" — secondaryButtonBehavior `.countdown`, handled
///     entirely by the system via `countdownDuration.postAlert`. No intent of
///     ours runs, so it works even when Downtime restricts the app — and,
///     unlike the `SnoozeStopIntent` it replaced, the re-ring is scheduled by
///     AlarmKit itself rather than by us.
///
/// Note the consequence: because no intent of ours fires on that snooze, the
/// chain's `AlarmEvent.snoozeCount` is NOT incremented by it.
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

                // TEMPORARY INSTRUMENTATION (spec §3.4). Logs every update
                // with each alarm's state so we can establish whether this
                // observer fires while the app is suspended — i.e. whether
                // an .alerting → .countdown transition (the user tapping
                // "Snooze 5 min" from the lock screen) is observable at the
                // moment it happens, or only on resume. Remove once answered.
                let desc = alarms
                    .map { "\($0.id.uuidString.prefix(8))=\(Self.stateName($0.state))" }
                    .sorted()
                    .joined(separator: " ")
                await LogService.shared.log(
                    .alarmkit,
                    "PROBE observer: \(alarms.count) alarm(s) [\(desc.isEmpty ? "none" : desc)]"
                )
            }
        }
    }

    /// TEMPORARY INSTRUMENTATION (spec §3.4). `Alarm.State` is Codable but has
    /// no display form; this keeps the probe readable in the log.
    nonisolated private static func stateName(_ state: AKAlarm.State) -> String {
        switch state {
        case .scheduled: return "scheduled"
        case .countdown: return "countdown"
        case .paused:    return "paused"
        case .alerting:  return "alerting"
        @unknown default: return "unknown"
        }
    }

    /// TEMPORARY INSTRUMENTATION (spec §3.4). Synchronous read of
    /// `AlarmManager.alarms` — the fallback path, which does not depend on the
    /// observer having run. Called at app open to confirm a countdown snooze
    /// taken while the app was suspended is still visible after the fact.
    func probeCurrentAlarmStates(tag: String) async {
        let current: [AKAlarm]
        do {
            current = try manager.alarms
        } catch {
            await LogService.shared.log(
                .alarmkit,
                "PROBE syncPoll[\(tag)]: threw \(error.localizedDescription)",
                isError: true
            )
            return
        }
        let desc = current
            .map { "\($0.id.uuidString.prefix(8))=\(Self.stateName($0.state))" }
            .sorted()
            .joined(separator: " ")
        await LogService.shared.log(
            .alarmkit,
            "PROBE syncPoll[\(tag)]: \(current.count) alarm(s) [\(desc.isEmpty ? "none" : desc)]"
        )
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
            presentation: AlarmPresentation(
                alert: alertContent(for: alarm, isSnooze: isSnooze),
                countdown: AlarmPresentation.Countdown(title: "Snoozing…")
            ),
            metadata: Metadata(),
            tintColor: L.Palette.accent
        )
        let config: AlarmManager.AlarmConfiguration<Metadata> = .init(
            countdownDuration: AKAlarm.CountdownDuration(
                preAlert: nil,
                postAlert: TimeInterval(Constants.stopButtonSnoozeMinutes * 60)
            ),
            schedule: schedule,
            attributes: attributes,
            stopIntent: OpenConversationIntent(alarmId: alarm.id.uuidString),
            secondaryIntent: nil
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
    ///
    /// Deliberately scoped to THIS alarm. It used to end with a blanket
    /// `stopAnyAlerting()`, which meant opening the Coach for one alarm
    /// silenced any other alarm that happened to be ringing — the app, rather
    /// than the user, deciding the other one was abandoned. Two alarms ringing
    /// is two commitments to answer. The blanket sweep now lives only on the
    /// orphan path in `reconcileOnAppOpen`, which is what it was written for.
    func stopAllActive(_ alarm: Alarm) async {
        for s in alarm.alarmKitIdStrings {
            if let id = UUID(uuidString: s) { await stop(alarmKitId: id) }
        }
        if let s = alarm.pendingSnoozeIdString, let id = UUID(uuidString: s) {
            await stop(alarmKitId: id)
        }
    }

    /// Stop alerting alarms that no `Alarm` record claims — the ghost-ringer
    /// backstop. A ringing phone with no working Stop affordance forces the
    /// user to reboot; this sweep is the guard against that.
    ///
    /// `trackedIds` is every AlarmKit ID our store still accounts for. Alarms
    /// in that set are left alone even while alerting: they belong to a real
    /// commitment, and silencing them for free is exactly what `stopAllActive`
    /// stopped doing.
    /// Every AlarmKit ID the store still accounts for, across all alarms.
    /// Used by callers that need the ghost-ringer sweep but have no single
    /// alarm to scope it to.
    @MainActor
    static func trackedAlarmKitIds(in context: ModelContext) -> Set<UUID> {
        guard let alarms = try? context.fetch(FetchDescriptor<Alarm>()) else { return [] }
        var ids: Set<UUID> = []
        for alarm in alarms where alarm.enabled {
            for s in alarm.alarmKitIdStrings {
                if let u = UUID(uuidString: s) { ids.insert(u) }
            }
            if let s = alarm.pendingSnoozeIdString, let u = UUID(uuidString: s) {
                ids.insert(u)
            }
        }
        return ids
    }

    func stopUntrackedAlerting(trackedIds: Set<UUID>) async {
        guard let live = try? manager.alarms else { return }
        for a in live where a.state == .alerting && !trackedIds.contains(a.id) {
            await LogService.shared.log(
                .alarmkit,
                "stopUntrackedAlerting: stopping orphan \(a.id.uuidString.prefix(8))",
                alarmKitId: a.id.uuidString
            )
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
        // TEMPORARY INSTRUMENTATION (spec §3.4). Remove once answered.
        await probeCurrentAlarmStates(tag: "reconcileOnAppOpen")

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

        // MUST run before recordMissedFirings. A countdown snooze executes no
        // code of ours, so the chain event doesn't exist until this creates
        // it — and recordMissedFirings treats "no event" as "nobody engaged".
        // Run these in the wrong order and a snoozed night is logged ignored
        // while the event materialises a moment later, so the app's own UI
        // looks correct and only the store is wrong. AC-3.3 guards this.
        let countingDown: Set<UUID>
        if let live = try? manager.alarms {
            countingDown = Set(live.filter { $0.state == .countdown }.map(\.id))
        } else {
            countingDown = []
        }
        await detectCountdownSnoozes(alarms: alarms, countingDown: countingDown, context: context)

        await recordMissedFirings(alarms: alarms, countingDown: countingDown, context: context)
        await closeAbandonedChains(context: context)

        // Ghost ringers — alerting alarms no Alarm record claims — die the
        // moment the app opens. Alarms we still track are left ringing; they
        // represent a real commitment the user hasn't answered yet.
        await stopUntrackedAlerting(trackedIds: trackedIds)
    }

    /// Detect snoozes taken from the alarm screen and enter them in the ledger.
    ///
    /// AlarmKit's native countdown snooze runs no code of ours — no intent, no
    /// callback — so this is the only place the app can learn it happened.
    /// Called at app open, keyed on the alarm's *current* state rather than on
    /// an observed transition: the observer's in-memory state doesn't survive
    /// a cold launch, and background delivery is unreliable (spec §3.4).
    ///
    /// `.countdown` means a snooze is running right now. If the chain has no
    /// event, or has one whose recorded snoozes don't reach this countdown,
    /// the user snoozed without us seeing it.
    /// `countingDown` is injected rather than read from `manager` so the
    /// ordering hazard above can be regression-tested against synthetic state
    /// instead of only on a physical device (spec AC-3.3).
    @MainActor
    func detectCountdownSnoozes(
        alarms: [Alarm],
        countingDown: Set<UUID>,
        context: ModelContext,
        now: Date = Date()
    ) async {
        guard !countingDown.isEmpty else { return }
        for alarm in alarms where alarm.enabled {
            await Task.yield()

            let ids = Set(
                (alarm.alarmKitIdStrings + [alarm.pendingSnoozeIdString].compactMap { $0 })
                    .compactMap(UUID.init(uuidString:))
            )
            guard !ids.isDisjoint(with: countingDown) else { continue }

            // A snooze we granted ourselves already set snoozedUntil and was
            // recorded when granted. Only an unaccounted countdown is new.
            if let until = alarm.snoozedUntil, until > now { continue }

            let event: AlarmEvent
            if let existing = AlarmEvent.openChain(for: alarm) {
                event = existing
            } else {
                let fresh = AlarmEvent(alarm: alarm)
                // The chain began when the alarm rang, not when we noticed.
                if let due = lastDueFireDate(for: alarm, now: now) { fresh.firedAt = due }
                context.insert(fresh)
                // Maintain the inverse relationship explicitly. `insert` alone
                // does not make the event visible via `alarm.events` until the
                // context saves — and recordMissedFirings, running later in
                // this same pass, decides "nobody engaged" by reading exactly
                // that. Without this the ordering fix silently does nothing.
                if !alarm.events.contains(where: { $0 === fresh }) {
                    alarm.events.append(fresh)
                }
                event = fresh
            }

            // Exact timing is unrecoverable — the snooze happened while we
            // were suspended. Bound it: no earlier than the alarm rang, and no
            // more than one countdown before now.
            let minutes = Constants.stopButtonSnoozeMinutes
            let earliest = max(
                lastDueFireDate(for: alarm, now: now) ?? .distantPast,
                now.addingTimeInterval(-TimeInterval(minutes * 60))
            )
            event.recordSnooze(
                minutes: minutes,
                source: .countdown,
                at: earliest,
                isApproximate: true
            )
            alarm.snoozedUntil = now.addingTimeInterval(TimeInterval(minutes * 60))

            await LogService.shared.log(
                .alarmkit,
                "detectCountdownSnoozes: recorded countdown snooze (count now \(event.snoozeCount))",
                alarmId: alarm.id.uuidString
            )
        }
    }

    /// Record firings nothing ever engaged with.
    ///
    /// There is deliberately **no time threshold** here. The old
    /// `missedGraceMinutes` was a proxy for "is this chain still in flight?",
    /// and we can read the real signal instead: AlarmKit's state, available
    /// synchronously. Every threshold tried was arbitrary — 30 minutes was
    /// 30 minutes, and the 15-minute ring duration turned out to mark only
    /// when the *sound* stops, while the alert stays on screen and engageable.
    ///
    /// The verdict comes from state plus the firing's lifecycle:
    ///
    ///   .countdown  the user snoozed ⇒ engaged, never ignored, however long
    ///   .alerting   still open, but reconcile is about to end it (the
    ///               untracked sweep, or the user dealing with it) ⇒ ignored
    ///               if nothing engaged
    ///   .scheduled  the firing is over ⇒ ignored if nothing engaged
    ///
    /// An `ignored` verdict is not final: `AlarmEvent.openChain` adopts and
    /// reopens it if the user engages afterwards. Recording early is safe
    /// because the ledger can change its mind.
    /// `countingDown` is injected for the same reason as
    /// `detectCountdownSnoozes` — see AC-3.3.
    func recordMissedFirings(
        alarms: [Alarm],
        countingDown: Set<UUID>,
        context: ModelContext,
        now: Date = Date()
    ) async {
        for alarm in alarms {
            guard alarm.enabled else { continue }
            // A live snooze means the chain is still in flight — not missed.
            if let until = alarm.snoozedUntil, until > now { continue }
            guard let due = lastDueFireDate(for: alarm, now: now) else { continue }
            guard due > alarm.createdAt else { continue }

            // Still bounded on the far side: don't backfill ancient firings.
            let lookbackEnd = due.addingTimeInterval(TimeInterval(Constants.missedLookbackHours) * 3600)
            guard now < lookbackEnd else { continue }

            // Any event at/after (or shortly before) the due time — pending,
            // resolved, or an earlier "ignored" from a previous pass — means
            // this firing is already accounted for.
            let window = due.addingTimeInterval(-3600)
            if alarm.events.contains(where: { $0.firedAt > window }) { continue }

            // A countdown in progress is engagement. detectCountdownSnoozes
            // runs first and normally creates the event, so this is a
            // belt-and-braces guard against ever calling a snooze a miss.
            let ids = Set(
                (alarm.alarmKitIdStrings + [alarm.pendingSnoozeIdString].compactMap { $0 })
                    .compactMap(UUID.init(uuidString:))
            )
            if !ids.isDisjoint(with: countingDown) { continue }

            let missed = AlarmEvent(alarm: alarm)
            missed.firedAt = due
            missed.outcome = "ignored"
            context.insert(missed)
            // Same reason as in detectCountdownSnoozes: keep `alarm.events`
            // truthful within this pass, so a later alarm in the loop (or a
            // repeat pass) doesn't record the same firing twice.
            if !alarm.events.contains(where: { $0 === missed }) {
                alarm.events.append(missed)
            }
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

        let snoozeButton = AlarmButton(
            text: "Snooze \(Constants.stopButtonSnoozeMinutes) min",
            textColor: .white,
            systemImageName: "zzz"
        )

        // iOS 26.1+: the stopButton parameter is deprecated. The system now
        // owns the stop affordance — we supply behavior via `stopIntent` on
        // the AlarmConfiguration.
        return AlarmPresentation.Alert(
            title: title,
            secondaryButton: snoozeButton,
            secondaryButtonBehavior: .countdown
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
