import Foundation
import SwiftData

@Observable
final class HistoryViewModel {

    func complianceRate(events: [AlarmEvent]) -> Double {
        let resolved = events.filter { $0.outcome != "pending" }
        guard !resolved.isEmpty else { return 0 }
        let complied = resolved.filter { $0.outcome == "complied" || $0.outcome == "snoozed_then_complied" }
        return Double(complied.count) / Double(resolved.count) * 100
    }

    func averageSnoozes(events: [AlarmEvent]) -> Double {
        let withSnoozes = events.filter { $0.snoozeCount > 0 }
        guard !withSnoozes.isEmpty else { return 0 }
        return Double(withSnoozes.map(\.snoozeCount).reduce(0, +)) / Double(withSnoozes.count)
    }

    func outcomeIcon(_ outcome: String) -> String {
        switch outcome {
        case "complied": "checkmark.circle.fill"
        case "snoozed_then_complied": "checkmark.circle"
        case "overridden": "xmark.circle.fill"
        case "ignored": "questionmark.circle"
        default: "circle"
        }
    }

    func outcomeColor(_ outcome: String) -> String {
        switch outcome {
        case "complied": "green"
        case "snoozed_then_complied": "yellow"
        case "overridden": "red"
        case "ignored": "gray"
        default: "gray"
        }
    }
}
