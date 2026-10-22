import Observation
import Foundation

@Observable
final class AppState {
    /// One presented conversation. A NEW session (fresh id) is minted on
    /// every trigger — even when a conversation is already on screen — so a
    /// re-ring always rebuilds a fresh ConversationView whose setup() stops
    /// the ringing alarm. Re-using the presented view was the
    /// "alarm keeps ringing until reboot" bug (2026-07-04): trigger was a
    /// no-op against the stale cover, setup() never re-ran, and
    /// stopAllActive never fired.
    struct ConversationSession: Identifiable, Equatable {
        let id: Int
        let alarmId: UUID
        let isRehearsal: Bool
    }

    var activeSession: ConversationSession?
    private var sessionCounter = 0

    /// In-memory copy of an alarm being rehearsed. Never inserted into a
    /// ModelContext. Cleared when the conversation is dismissed.
    private(set) var rehearsalAlarm: Alarm?

    var activeAlarmId: UUID? { activeSession?.alarmId }

    func triggerAlarm(alarmId: UUID) {
        sessionCounter += 1
        activeSession = ConversationSession(id: sessionCounter, alarmId: alarmId, isRehearsal: false)
    }

    func rehearse(alarm: Alarm) {
        startRehearsal(with: alarm.rehearsalCopy())
    }

    func rehearseSample() {
        startRehearsal(with: RehearsalSample.makeAlarm())
    }

    private func startRehearsal(with copy: Alarm) {
        rehearsalAlarm = copy
        sessionCounter += 1
        activeSession = ConversationSession(id: sessionCounter, alarmId: copy.id, isRehearsal: true)
    }

    func dismissAlarm() {
        activeSession = nil
        rehearsalAlarm = nil
    }
}
