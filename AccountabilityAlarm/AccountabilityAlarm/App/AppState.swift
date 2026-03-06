import Observation
import Foundation

@Observable
final class AppState {
    var activeAlarmId: UUID?
    var activeRing: EscalationRing?
    var showConversation = false

    func triggerAlarm(alarmId: UUID, ring: EscalationRing) {
        activeAlarmId = alarmId
        activeRing = ring
        showConversation = true
    }

    func dismissAlarm() {
        activeAlarmId = nil
        activeRing = nil
        showConversation = false
    }
}
