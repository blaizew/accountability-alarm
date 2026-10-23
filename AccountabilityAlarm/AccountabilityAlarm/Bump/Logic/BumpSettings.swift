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

/// Which hand the user taps on the bump stage.
enum BumpGlyph: String, CaseIterable {
    case fist, handLeft, handRight

    /// Visible ink height of the fist as a multiple of the frame width (measured).
    static let fistInkHeightFactor: CGFloat = 0.875

    /// The emoji drawn. Apple's ✋ faces the viewer with the thumb on the viewer's right,
    /// so it reads as a left hand; the right hand is the same glyph mirrored.
    var emoji: String { self == .fist ? "👊" : "✋" }
    var mirrored: Bool { self == .handRight }
    var label: String {
        switch self {
        case .fist: return "Fist"
        case .handLeft: return "Left hand"
        case .handRight: return "Right hand"
        }
    }
    /// The hint under the glyph.
    var hint: String { self == .fist ? "(bump the fist)" : "(high five)" }
    /// Visible ink height as a multiple of the frame width; the hint anchors below it.
    var inkHeightFactor: CGFloat { self == .fist ? BumpGlyph.fistInkHeightFactor : 1.11 }
}
