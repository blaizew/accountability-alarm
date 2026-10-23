import Foundation

struct BumpChoice: Equatable {
    let glyph: BumpGlyph
    let removal: FistRemoval
    let pattern: ConfettiPattern
    let shapes: ConfettiShapes
    let palette: ConfettiPalette
    let density: Double
    let size: Double
}

struct BumpRandomizer {
    var rng: any RandomNumberGenerator

    private static let steps: [Double] = [0.6, 1.0, 1.4]
    private static let houseProbability = 0.2

    init(rng: any RandomNumberGenerator = SystemRandomNumberGenerator()) {
        self.rng = rng
    }

    mutating func choose(
        glyphOverride: BumpGlyph?,
        removalOverride: FistRemoval?,
        patternOverride: ConfettiPattern?,
        shapesOverride: ConfettiShapes?,
        lastRemoval: FistRemoval?
    ) -> BumpChoice {
        let glyph = glyphOverride ?? BumpGlyph.allCases.randomElement(using: &rng) ?? .fist
        let removal: FistRemoval
        if let removalOverride {
            removal = removalOverride
        } else {
            let pool = FistRemoval.allCases.filter { $0 != lastRemoval }
            removal = pool.randomElement(using: &rng) ?? .burst
        }
        let pattern = patternOverride ?? ConfettiPattern.allCases.randomElement(using: &rng) ?? .pop
        let shapes = shapesOverride ?? ConfettiShapes.allCases.randomElement(using: &rng) ?? .clean
        let palette: ConfettiPalette
        if Double.random(in: 0..<1, using: &rng) < Self.houseProbability {
            palette = ConfettiPalettes.house
        } else {
            palette = ConfettiPalettes.site.randomElement(using: &rng) ?? ConfettiPalettes.house
        }
        return BumpChoice(
            glyph: glyph,
            removal: removal,
            pattern: pattern,
            shapes: shapes,
            palette: palette,
            density: Self.steps.randomElement(using: &rng) ?? 1.0,
            size: Self.steps.randomElement(using: &rng) ?? 1.0
        )
    }
}
