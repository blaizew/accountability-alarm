import Foundation

var failures = 0

func check(_ cond: Bool, _ name: String) {
    if cond {
        print("PASS \(name)")
    } else {
        print("FAIL \(name)")
        failures += 1
    }
}

@main
struct Tests {
    static func main() {
        check(ConfettiPalettes.site.count == 36, "36 site palettes")
        check(ConfettiPalettes.site[0].colors == [0x332f48, 0xf2d9e6, 0xec4c4c, 0x772c93], "first palette matches site")
        check(ConfettiPalettes.luminance(0xFFFFFF) > 0.99 && ConfettiPalettes.luminance(0x000000) < 0.01, "luminance bounds")
        // 0x332f48 (lum ~0.03) and 0x772c93 (lum ~0.08) are under 0.2; 0xec4c4c (~0.24) stays.
        check(ConfettiPalettes.usable(ConfettiPalette(colors: [0x332f48, 0xf2d9e6, 0xec4c4c, 0x772c93])) == [0xf2d9e6, 0xec4c4c], "dark colors dropped, order kept")
        check(ConfettiPalettes.usable(ConfettiPalette(colors: [0x000000, 0x111111, 0xFFFFFF])) == [0x000000, 0x111111, 0xFFFFFF], "keep all when fewer than 2 usable")
        check(ConfettiPalettes.usable(ConfettiPalettes.house).count == 4, "house palette all usable")
        // Randomizer: never repeats the last removal
        var r = BumpRandomizer()
        var repeats = 0
        for _ in 0..<500 { if r.choose(glyphOverride: nil, removalOverride: nil, patternOverride: nil, shapesOverride: nil, lastRemoval: .burst).removal == .burst { repeats += 1 } }
        check(repeats == 0, "removal never repeats last")
        check(r.choose(glyphOverride: nil, removalOverride: .burst, patternOverride: nil, shapesOverride: nil, lastRemoval: .burst).removal == .burst, "override wins over last")
        check(r.choose(glyphOverride: nil, removalOverride: nil, patternOverride: .rain, shapesOverride: .snow, lastRemoval: nil).pattern == .rain, "pattern override")
        check(r.choose(glyphOverride: nil, removalOverride: nil, patternOverride: nil, shapesOverride: .snow, lastRemoval: nil).shapes == .snow, "shapes override")
        var house = 0
        for _ in 0..<2000 { if r.choose(glyphOverride: nil, removalOverride: nil, patternOverride: nil, shapesOverride: nil, lastRemoval: nil).palette == ConfettiPalettes.house { house += 1 } }
        check(house > 240 && house < 560, "house palette about one in five (\(house)/2000)")
        let c = r.choose(glyphOverride: nil, removalOverride: nil, patternOverride: nil, shapesOverride: nil, lastRemoval: nil)
        check([0.6, 1.0, 1.4].contains(c.density) && [0.6, 1.0, 1.4].contains(c.size), "density and size steps")
        check(r.choose(glyphOverride: .handLeft, removalOverride: nil, patternOverride: nil, shapesOverride: nil, lastRemoval: nil).glyph == .handLeft, "glyph override wins")
        var seenGlyphs = Set<String>()
        for _ in 0..<300 { seenGlyphs.insert(r.choose(glyphOverride: nil, removalOverride: nil, patternOverride: nil, shapesOverride: nil, lastRemoval: nil).glyph.rawValue) }
        check(seenGlyphs.count == BumpGlyph.allCases.count, "random glyph covers all three")
        check(BumpGlyph.handRight.mirrored && !BumpGlyph.handLeft.mirrored && !BumpGlyph.fist.mirrored, "only the right hand is mirrored")
        // Phase
        check(!BumpPhase.entering.canBump && BumpPhase.ready.canBump && !BumpPhase.bumped.canBump, "only ready can bump")
        // Send-off
        let a = ConversationMessage(role: .assistant, content: "Feet on the floor.")
        let u = ConversationMessage(role: .user, content: "yes")
        check(BumpSendOff.pick([u, a]) == "Feet on the floor.", "send-off is last assistant text")
        check(BumpSendOff.pick([a, u]) == nil, "no send-off when last is user")
        check(BumpSendOff.pick([u, ConversationMessage(role: .assistant, content: "  ")]) == nil, "blank send-off is nil")
        check(BumpSendOff.pick([]) == nil, "empty messages")
        // Turn-limit rule
        check(BumpRules.shouldOverrideForTurnLimit(isCompleted: false, actionAuthorized: false, turnsThisSession: 12, maxTurns: 6), "override at limit")
        check(!BumpRules.shouldOverrideForTurnLimit(isCompleted: false, actionAuthorized: true, turnsThisSession: 12, maxTurns: 6), "authorized turn is not overridden")
        check(!BumpRules.shouldOverrideForTurnLimit(isCompleted: true, actionAuthorized: false, turnsThisSession: 12, maxTurns: 6), "completed is not overridden again")
        check(!BumpRules.shouldOverrideForTurnLimit(isCompleted: false, actionAuthorized: false, turnsThisSession: 11, maxTurns: 6), "under limit")
        
        print(failures == 0 ? "ALL PASSED" : "\(failures) FAILED")
        exit(failures == 0 ? 0 : 1)
    }
}
