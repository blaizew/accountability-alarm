import Foundation

enum EscalationLevel: String, Codable, CaseIterable, Sendable {
    case gentle
    case firm
    case relentless

    var label: String {
        switch self {
        case .gentle: "Gentle"
        case .firm: "Firm"
        case .relentless: "Relentless"
        }
    }

    var description: String {
        switch self {
        case .gentle: "Warm and understanding. Backs off quickly."
        case .firm: "Direct and factual. Pushes back once."
        case .relentless: "Persistent and confrontational. Won't let you off easy."
        }
    }

    var icon: String {
        switch self {
        case .gentle: "leaf"
        case .firm: "hand.raised"
        case .relentless: "flame"
        }
    }

    /// How many times the AI pushes back before accepting an override
    var overrideResistance: Int {
        switch self {
        case .gentle: 0
        case .firm: 1
        case .relentless: 2
        }
    }
}
