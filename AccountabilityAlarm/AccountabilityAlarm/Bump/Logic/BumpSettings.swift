import Foundation

/// Haptic presets for the fist bump.
enum BumpHaptic: String, CaseIterable {
    case buzz, click, thudClick, success

    static let defaultValue = BumpHaptic.thudClick

    var label: String {
        switch self {
        case .buzz: return "Buzz"
        case .click: return "Click"
        case .thudClick: return "Thud + click"
        case .success: return "Success"
        }
    }
}

/// How the fist leaves the screen after a bump.
enum FistRemoval: String, CaseIterable {
    case burst, dissolve, shatter, recoil, pullAway, shockwave

    var label: String {
        switch self {
        case .burst: return "Burst"
        case .dissolve: return "Dissolve"
        case .shatter: return "Shatter"
        case .recoil: return "Recoil"
        case .pullAway: return "Pull away"
        case .shockwave: return "Shockwave"
        }
    }
}

enum ConfettiPattern: String, CaseIterable {
    case pop, spray, fireworks, rain

    var label: String {
        switch self {
        case .pop: return "Pop"
        case .spray: return "Spray"
        case .fireworks: return "Fireworks"
        case .rain: return "Rain"
        }
    }
}

enum ConfettiShapes: String, CaseIterable {
    case clean, classic, stars, sparkles, love, cake, bubbles, garden, cards, snow

    var label: String {
        switch self {
        case .clean: return "Clean"
        case .classic: return "Classic"
        case .stars: return "Stars"
        case .sparkles: return "Sparkles"
        case .love: return "Love"
        case .cake: return "Cake"
        case .bubbles: return "Bubbles"
        case .garden: return "Garden"
        case .cards: return "Cards"
        case .snow: return "Snow"
        }
    }
}

enum BumpPhase {
    case entering, ready, bumped

    var canBump: Bool { self == .ready }
}
