import Foundation
import UserNotifications

final class NotificationService {
    static let shared = NotificationService()

    private init() {}

    func requestPermission() async -> Bool {
        do {
            return try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound, .badge])
        } catch {
            return false
        }
    }

    func scheduleAlarm(_ alarm: Alarm) {
        cancelAlarm(alarm)
        guard alarm.enabled else { return }

        for ring in EscalationRing.allCases {
            scheduleRing(for: alarm, ring: ring)
        }
    }

    private func scheduleRing(for alarm: Alarm, ring: EscalationRing) {
        let content = UNMutableNotificationContent()
        content.title = alarm.label.isEmpty ? "Alarm" : alarm.label
        content.body = ringNotificationBody(ring: ring)
        content.sound = UNNotificationSound(named: UNNotificationSoundName("alarm-sound.caf"))
        content.categoryIdentifier = Constants.NotificationCategory.alarm
        content.interruptionLevel = .timeSensitive
        content.userInfo = [
            "alarmId": alarm.id.uuidString,
            "ring": ring.rawValue,
        ]

        let totalMinutes = alarm.hour * 60 + alarm.minute + ring.minutesAfterAlarm
        var dateComponents = DateComponents()
        dateComponents.hour = (totalMinutes / 60) % 24
        dateComponents.minute = totalMinutes % 60

        if alarm.repeatDays.isEmpty {
            // One-shot alarm
            let trigger = UNCalendarNotificationTrigger(
                dateMatching: dateComponents, repeats: false
            )
            let id = notificationId(alarm: alarm, ring: ring)
            let request = UNNotificationRequest(
                identifier: id, content: content, trigger: trigger
            )
            UNUserNotificationCenter.current().add(request)
        } else {
            // Repeating: one trigger per weekday
            for day in alarm.repeatDays {
                var dayComponents = dateComponents
                dayComponents.weekday = day
                let trigger = UNCalendarNotificationTrigger(
                    dateMatching: dayComponents, repeats: true
                )
                let id = notificationId(alarm: alarm, ring: ring, weekday: day)
                let request = UNNotificationRequest(
                    identifier: id, content: content, trigger: trigger
                )
                UNUserNotificationCenter.current().add(request)
            }
        }
    }

    func cancelAlarm(_ alarm: Alarm) {
        var ids: [String] = []
        for ring in EscalationRing.allCases {
            ids.append(notificationId(alarm: alarm, ring: ring))
            for day in 1...7 {
                ids.append(notificationId(alarm: alarm, ring: ring, weekday: day))
            }
        }
        UNUserNotificationCenter.current().removePendingNotificationRequests(
            withIdentifiers: ids
        )
    }

    func cancelRemainingRings(alarm: Alarm, afterRing: EscalationRing) {
        var ids: [String] = []
        for ring in EscalationRing.allCases where ring.rawValue > afterRing.rawValue {
            ids.append(notificationId(alarm: alarm, ring: ring))
            for day in 1...7 {
                ids.append(notificationId(alarm: alarm, ring: ring, weekday: day))
            }
        }
        UNUserNotificationCenter.current().removePendingNotificationRequests(
            withIdentifiers: ids
        )
    }

    func rescheduleRemainingRings(alarm: Alarm, afterRing: EscalationRing) {
        for ring in EscalationRing.allCases where ring.rawValue > afterRing.rawValue {
            scheduleRing(for: alarm, ring: ring)
        }
    }

    private func notificationId(alarm: Alarm, ring: EscalationRing, weekday: Int? = nil) -> String {
        if let weekday {
            return "alarm-\(alarm.id.uuidString)-ring-\(ring.rawValue)-day-\(weekday)"
        }
        return "alarm-\(alarm.id.uuidString)-ring-\(ring.rawValue)"
    }

    private func ringNotificationBody(ring: EscalationRing) -> String {
        switch ring {
        case .nudge: "Time's up. Tap to check in."
        case .math: "Still haven't checked in. Let's talk."
        case .mirror: "Remember what you said? Tap to hear it."
        case .preview: "Last call. Are you following through?"
        }
    }
}
