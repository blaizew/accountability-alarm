import Foundation
import SwiftData

/// A single durable log entry. Written from both the app process and the
/// background intent process so we can reconstruct what happened after the
/// fact when something weird occurs (e.g. an alarm fires at 9:55 with no
/// scheduled source).
@Model
final class AlarmLogEntry {
    var id: UUID = UUID()
    var timestamp: Date = Date()
    var categoryRaw: String = "app"
    var message: String = ""
    var alarmIdString: String?
    var alarmKitIdString: String?
    var isError: Bool = false

    var category: LogCategory {
        LogCategory(rawValue: categoryRaw) ?? .app
    }

    init(
        category: LogCategory,
        message: String,
        alarmIdString: String? = nil,
        alarmKitIdString: String? = nil,
        isError: Bool = false
    ) {
        self.id = UUID()
        self.timestamp = Date()
        self.categoryRaw = category.rawValue
        self.message = message
        self.alarmIdString = alarmIdString
        self.alarmKitIdString = alarmKitIdString
        self.isError = isError
    }
}

enum LogCategory: String, CaseIterable {
    case alarmkit   // schedule/cancel/stop calls into AlarmKit
    case intent     // App Intent invocations (Stop, Talk to Coach)
    case conversation // conversation lifecycle (open, comply, override, snooze)
    case app        // launch, reconcile, scene-phase
    case error      // anything explicitly flagged

    var label: String {
        switch self {
        case .alarmkit:     return "alarmkit"
        case .intent:       return "intent"
        case .conversation: return "convo"
        case .app:          return "app"
        case .error:        return "error"
        }
    }
}
