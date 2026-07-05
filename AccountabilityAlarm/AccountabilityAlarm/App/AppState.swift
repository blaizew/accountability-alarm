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
    }

    var activeSession: ConversationSession?
    private var sessionCounter = 0

    var activeAlarmId: UUID? { activeSession?.alarmId }

    func triggerAlarm(alarmId: UUID) {
        sessionCounter += 1
        activeSession = ConversationSession(id: sessionCounter, alarmId: alarmId)
    }

    func dismissAlarm() {
        activeSession = nil
    }
}
