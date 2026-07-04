import Observation
import Foundation

@Observable
final class AppState {
    var activeAlarmId: UUID?
    var showConversation = false

    func triggerAlarm(alarmId: UUID) {
        activeAlarmId = alarmId
        showConversation = true
    }

    func dismissAlarm() {
        activeAlarmId = nil
        showConversation = false
    }
}
