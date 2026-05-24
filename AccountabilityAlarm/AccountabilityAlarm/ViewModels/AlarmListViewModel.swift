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
                // Bootstrap the first T+1 companion. From here on it's
                // refreshed each time the user interacts with the alarm.
                let t1 = await AlarmKitService.shared.scheduleFirstCompanion(for: alarm)
                alarm.nextT1IdString = t1?.uuidString
            } else {
                await AlarmKitService.shared.cancelAlarm(alarm)
                alarm.alarmKitIdStrings = []
                alarm.pendingSnoozeIdString = nil
                alarm.nextT1IdString = nil
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
