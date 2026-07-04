import AppIntents
import Foundation
import SwiftData

/// Fired when the user taps the system "Stop" button (or "Slide to Stop") on
/// any AlarmKit alert for one of our alarms. Runs in a background context —
/// does NOT launch the app — which means it works even when Downtime restricts
/// the app itself.
///
/// Behavior: schedules a fresh 5-minute snooze for this alarm, cancelling any
/// existing pending snooze. Net effect: the alarm sound stops (system handles
/// that as part of Stop), and the alarm re-rings 5 minutes later. The only
/// way out of the cycle is for the user to actually engage via "Talk to
/// past-self" and have the LLM authorize Comply.
struct SnoozeStopIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Snooze"
    static var description = IntentDescription(
        "Snoozes the alarm for 5 minutes. The only way to truly stop the alarm is to engage with past-you."
    )

    @Parameter(title: "Alarm ID")
    var alarmId: String

    /// Critical: keep this false. We deliberately want this intent to run in
    /// the background without launching the app, so it works under Downtime.
    static var openAppWhenRun: Bool = false

    init() {}
    init(alarmId: String) {
        self.alarmId = alarmId
    }

    func perform() async throws -> some IntentResult {
        await LogService.shared.log(.intent, "SnoozeStopIntent fired", alarmId: alarmId)

        guard let uuid = UUID(uuidString: alarmId) else {
            await LogService.shared.log(.intent, "SnoozeStopIntent: bad alarmId \(alarmId)", isError: true)
            return .result()
        }

        await IntentSwiftData.snooze(alarmId: uuid, minutes: Constants.stopButtonSnoozeMinutes)
        return .result()
    }
}

/// Helper that runs the snooze flow on the main actor. Factored out so the
/// perform() method stays a thin shim — the heavy lifting is testable on its
/// own.
private enum IntentSwiftData {
    @MainActor
    static func snooze(alarmId: UUID, minutes: Int) async {
        // The intent runs in the app process, so it MUST use the same
        // container (and mainContext) as the UI. A private second container
        // here left the running app blind to the pendingSnoozeIdString this
        // writes — disable/cancel paths then missed the snooze entirely.
        guard let container = AppContainer.shared else {
            await LogService.shared.log(
                .intent,
                "SnoozeStopIntent: shared ModelContainer unavailable",
                isError: true
            )
            return
        }

        let context = container.mainContext
        let predicate = #Predicate<Alarm> { $0.id == alarmId }
        guard let alarm = try? context.fetch(FetchDescriptor(predicate: predicate)).first else {
            await LogService.shared.log(
                .intent,
                "SnoozeStopIntent: alarm \(alarmId) not found",
                alarmId: alarmId.uuidString,
                isError: true
            )
            return
        }

        // The user can toggle the alarm off while its alert is still ringing.
        // Stop on a disabled alarm must NOT re-arm it — without this guard
        // the "off" alarm re-rings every 5 minutes indefinitely.
        guard alarm.enabled else {
            await LogService.shared.log(
                .intent,
                "SnoozeStopIntent: alarm disabled — not scheduling snooze",
                alarmId: alarmId.uuidString
            )
            return
        }

        await AlarmKitService.shared.handleStopSnooze(alarm: alarm, minutes: minutes)

        // Stop-button snoozes count toward the chain's snooze ladder just
        // like in-conversation ones. Find-or-create the open chain event so
        // the next conversation's system prompt sees the real count.
        let event: AlarmEvent
        if let existing = AlarmEvent.openChain(for: alarm) {
            event = existing
        } else {
            event = AlarmEvent(alarm: alarm)
            context.insert(event)
        }
        event.snoozeCount += 1

        try? context.save()
    }
}
