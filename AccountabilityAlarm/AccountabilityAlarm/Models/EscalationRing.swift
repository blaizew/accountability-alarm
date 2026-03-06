import Foundation

enum EscalationRing: Int, Codable, CaseIterable, Sendable {
    case nudge = 1
    case math = 2
    case mirror = 3
    case preview = 4

    var label: String {
        switch self {
        case .nudge: "Nudge"
        case .math: "Math"
        case .mirror: "Mirror"
        case .preview: "Preview"
        }
    }

    var minutesAfterAlarm: Int {
        switch self {
        case .nudge: 0
        case .math: 10
        case .mirror: 20
        case .preview: 30
        }
    }

    var ringDescription: String {
        switch self {
        case .nudge: "Gentle reminder"
        case .math: "Sleep math"
        case .mirror: "Your own words"
        case .preview: "Tomorrow preview"
        }
    }
}
