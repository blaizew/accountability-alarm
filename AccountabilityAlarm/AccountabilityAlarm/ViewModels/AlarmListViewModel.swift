import SwiftUI
import SwiftData

@Observable
final class AlarmListViewModel {
    var showingAddAlarm = false

    func toggleAlarm(_ alarm: Alarm) {
        alarm.enabled.toggle()
        alarm.snoozedUntil = nil
        Task { @MainActor in
            if alarm.enabled {
                let ids = await AlarmKitService.shared.scheduleAlarm(alarm)
                alarm.alarmKitIdStrings = ids.map(\.uuidString)
            } else {
                await AlarmKitService.shared.cancelAlarm(alarm)
                alarm.alarmKitIdStrings = []
                alarm.pendingSnoozeIdString = nil
            }
        }
    }

    func deleteAlarm(_ alarm: Alarm, context: ModelContext) {
        Task { @MainActor in
            await AlarmKitService.shared.cancelAlarm(alarm)
        }
        context.delete(alarm)
    }

    func requestNotificationPermission() async {
        // Kept for legacy non-alarm notifications.
        _ = await NotificationService.shared.requestPermission()
        // Authorize AlarmKit so alarms ring through Silent/DnD/Focus.
        _ = await AlarmKitService.shared.requestAuthorization()
    }
}
