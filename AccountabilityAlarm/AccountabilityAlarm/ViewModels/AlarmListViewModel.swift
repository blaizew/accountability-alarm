import SwiftUI
import SwiftData

@Observable
final class AlarmListViewModel {
    var showingAddAlarm = false

    func toggleAlarm(_ alarm: Alarm) {
        alarm.enabled.toggle()
        if alarm.enabled {
            NotificationService.shared.scheduleAlarm(alarm)
        } else {
            NotificationService.shared.cancelAlarm(alarm)
        }
    }

    func deleteAlarm(_ alarm: Alarm, context: ModelContext) {
        NotificationService.shared.cancelAlarm(alarm)
        context.delete(alarm)
    }

    func requestNotificationPermission() async {
        _ = await NotificationService.shared.requestPermission()
    }
}
