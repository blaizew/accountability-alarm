import Foundation

extension Date {
    func hoursUntil(hour: Int, minute: Int) -> Double {
        let calendar = Calendar.current
        var target = calendar.nextDate(
            after: self,
            matching: DateComponents(hour: hour, minute: minute),
            matchingPolicy: .nextTime
        ) ?? self
        // If target is in the past (shouldn't happen with nextDate), add a day
        if target <= self {
            target = calendar.date(byAdding: .day, value: 1, to: target) ?? target
        }
        return target.timeIntervalSince(self) / 3600
    }

    func sleepHoursIfBedNow(wakeHour: Int, wakeMinute: Int) -> Double {
        hoursUntil(hour: wakeHour, minute: wakeMinute)
    }

    var shortTimeString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return formatter.string(from: self)
    }
}
