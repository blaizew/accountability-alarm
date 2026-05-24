import Foundation
import UserNotifications

/// Legacy notification service. Alarm scheduling now lives in `AlarmKitService`
/// — this is only kept for non-alarm UNUserNotification uses (e.g. the morning
/// check-in flow) and for requesting baseline notification permission.
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
}
