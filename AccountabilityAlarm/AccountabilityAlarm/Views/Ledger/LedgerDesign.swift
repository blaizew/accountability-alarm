import SwiftUI

// LEDGER design tokens — dense, monospace, terminal-influenced.
// Mirrors `ledger-shared.jsx` from the design handoff.

enum L {

    // MARK: - Palette

    enum Palette {
        // Backgrounds
        static let bg  = Color(hex: 0x0A0A0C)
        static let bg2 = Color(hex: 0x121216)
        static let bg3 = Color(hex: 0x18181D)
        static let bg4 = Color(hex: 0x1E1E25)

        // Hairlines
        static let hair  = Color.white.opacity(0.06)
        static let hair2 = Color.white.opacity(0.12)
        static let hair3 = Color.white.opacity(0.18)

        // Text
        static let fg     = Color(hex: 0xE9E9EC)
        static let muted  = Color(hex: 0xE8E8EC, opacity: 0.58)
        static let dim    = Color(hex: 0xE8E8EC, opacity: 0.36)
        static let dimmer = Color(hex: 0xE8E8EC, opacity: 0.22)

        static let accent = Color.white

        // Ring colours — approximated from oklch in the brief.
        // oklch(0.74 0.08 240) cool blue
        static let ringNudge   = Color(red: 0.50, green: 0.71, blue: 0.84)
        // oklch(0.78 0.07 90) straw
        static let ringMath    = Color(red: 0.83, green: 0.76, blue: 0.51)
        // oklch(0.72 0.13 55) amber
        static let ringMirror  = Color(red: 0.93, green: 0.65, blue: 0.36)
        // oklch(0.65 0.18 28) red
        static let ringPreview = Color(red: 0.91, green: 0.40, blue: 0.32)

        static let goodGreen  = Color(red: 0.45, green: 0.79, blue: 0.55) // oklch(0.72 0.12 145)
        static let warnYellow = Color(red: 0.86, green: 0.72, blue: 0.36) // oklch(0.78 0.13 88)
        static let badRed     = ringPreview
    }

    // MARK: - Typography
    //
    // The brief specifies JetBrains Mono. Until that's bundled as a font asset,
    // we fall back to SF Mono via `.monospaced(...)`, which the brief explicitly
    // calls out as acceptable on iOS.

    enum Mono {
        static func font(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
            .system(size: size, weight: weight, design: .monospaced)
        }
    }

    // MARK: - Spacing — canonical values used in the design
    enum Space {
        static let pageH: CGFloat = 16
        static let rowV: CGFloat = 14
    }

    // MARK: - Glyphs

    struct Leaf: View {
        var size: CGFloat = 10
        var color: Color = .primary
        var body: some View {
            Canvas { ctx, _ in
                let s = size
                var p = Path()
                // Q1 9 Q1 1 9 1
                p.move(to: CGPoint(x: 0.1 * s, y: 0.9 * s))
                p.addQuadCurve(to: CGPoint(x: 0.9 * s, y: 0.1 * s),
                               control: CGPoint(x: 0.1 * s, y: 0.1 * s))
                p.addQuadCurve(to: CGPoint(x: 0.1 * s, y: 0.9 * s),
                               control: CGPoint(x: 0.9 * s, y: 0.9 * s))
                p.closeSubpath()
                ctx.stroke(p, with: .color(color), lineWidth: 1)
                var l = Path()
                l.move(to: CGPoint(x: 0.1 * s, y: 0.9 * s))
                l.addLine(to: CGPoint(x: 0.9 * s, y: 0.1 * s))
                ctx.stroke(l, with: .color(color), lineWidth: 0.8)
            }
            .frame(width: size, height: size)
        }
    }

    struct Hand: View {
        var size: CGFloat = 10
        var color: Color = .primary
        var body: some View {
            Canvas { ctx, _ in
                let s = size
                let rect = CGRect(x: 0.25 * s, y: 0.2 * s, width: 0.5 * s, height: 0.65 * s)
                let path = Path(roundedRect: rect, cornerRadius: 0.1 * s)
                ctx.stroke(path, with: .color(color), lineWidth: 1)
                var bar = Path()
                bar.move(to: CGPoint(x: 0.5 * s, y: 0.45 * s))
                bar.addLine(to: CGPoint(x: 0.5 * s, y: 0.65 * s))
                ctx.stroke(bar, with: .color(color), lineWidth: 1)
            }
            .frame(width: size, height: size)
        }
    }

    struct Flame: View {
        var size: CGFloat = 10
        var color: Color = .primary
        var body: some View {
            Canvas { ctx, _ in
                let s = size
                var p = Path()
                p.move(to: CGPoint(x: 0.5 * s, y: 0.1 * s))
                p.addQuadCurve(to: CGPoint(x: 0.2 * s, y: 0.65 * s),
                               control: CGPoint(x: 0.2 * s, y: 0.4 * s))
                p.addQuadCurve(to: CGPoint(x: 0.5 * s, y: 0.9 * s),
                               control: CGPoint(x: 0.2 * s, y: 0.9 * s))
                p.addQuadCurve(to: CGPoint(x: 0.8 * s, y: 0.65 * s),
                               control: CGPoint(x: 0.8 * s, y: 0.9 * s))
                p.addQuadCurve(to: CGPoint(x: 0.5 * s, y: 0.1 * s),
                               control: CGPoint(x: 0.8 * s, y: 0.4 * s))
                p.closeSubpath()
                ctx.stroke(p, with: .color(color), lineWidth: 1)
            }
            .frame(width: size, height: size)
        }
    }

    struct Chev: View {
        var size: CGFloat = 10
        var color: Color = .primary
        var body: some View {
            Canvas { ctx, _ in
                let s = size
                var p = Path()
                p.move(to: CGPoint(x: 0.3 * s, y: 0.2 * s))
                p.addLine(to: CGPoint(x: 0.7 * s, y: 0.5 * s))
                p.addLine(to: CGPoint(x: 0.3 * s, y: 0.8 * s))
                ctx.stroke(p, with: .color(color),
                           style: StrokeStyle(lineWidth: 1.2, lineCap: .square))
            }
            .frame(width: size, height: size)
        }
    }

    struct Dot: View {
        var size: CGFloat = 6
        var color: Color = .primary
        var body: some View {
            Circle().fill(color).frame(width: size, height: size)
        }
    }

    struct Plus: View {
        var size: CGFloat = 12
        var color: Color = .primary
        var body: some View {
            Canvas { ctx, _ in
                let s = size
                var p = Path()
                p.move(to: CGPoint(x: 0.5 * s, y: 0.08 * s))
                p.addLine(to: CGPoint(x: 0.5 * s, y: 0.92 * s))
                p.move(to: CGPoint(x: 0.08 * s, y: 0.5 * s))
                p.addLine(to: CGPoint(x: 0.92 * s, y: 0.5 * s))
                ctx.stroke(p, with: .color(color),
                           style: StrokeStyle(lineWidth: 1.4, lineCap: .square))
            }
            .frame(width: size, height: size)
        }
    }

    struct Mic: View {
        var size: CGFloat = 16
        var color: Color = .primary
        var body: some View {
            Canvas { ctx, _ in
                let s = size
                let cap = CGRect(x: 0.375 * s, y: 0.125 * s, width: 0.25 * s, height: 0.5 * s)
                ctx.stroke(Path(roundedRect: cap, cornerRadius: 0.125 * s),
                           with: .color(color), lineWidth: 1.2)
                var arc = Path()
                arc.move(to: CGPoint(x: 0.19 * s, y: 0.5 * s))
                arc.addQuadCurve(to: CGPoint(x: 0.81 * s, y: 0.5 * s),
                                 control: CGPoint(x: 0.5 * s, y: 0.95 * s))
                ctx.stroke(arc, with: .color(color),
                           style: StrokeStyle(lineWidth: 1.2, lineCap: .square))
                var stem = Path()
                stem.move(to: CGPoint(x: 0.5 * s, y: 0.81 * s))
                stem.addLine(to: CGPoint(x: 0.5 * s, y: 0.94 * s))
                ctx.stroke(stem, with: .color(color),
                           style: StrokeStyle(lineWidth: 1.2, lineCap: .square))
            }
            .frame(width: size, height: size)
        }
    }

    struct PlayTri: View {
        var size: CGFloat = 9
        var color: Color = .primary
        var body: some View {
            Canvas { ctx, _ in
                let s = size
                var p = Path()
                p.move(to: CGPoint(x: 0.22 * s, y: 0.11 * s))
                p.addLine(to: CGPoint(x: 0.89 * s, y: 0.5 * s))
                p.addLine(to: CGPoint(x: 0.22 * s, y: 0.89 * s))
                p.closeSubpath()
                ctx.fill(p, with: .color(color))
            }
            .frame(width: size, height: size)
        }
    }

    struct XGlyph: View {
        var size: CGFloat = 10
        var color: Color = .primary
        var body: some View {
            Canvas { ctx, _ in
                let s = size
                var p = Path()
                p.move(to: CGPoint(x: 0.1 * s, y: 0.1 * s))
                p.addLine(to: CGPoint(x: 0.9 * s, y: 0.9 * s))
                p.move(to: CGPoint(x: 0.9 * s, y: 0.1 * s))
                p.addLine(to: CGPoint(x: 0.1 * s, y: 0.9 * s))
                ctx.stroke(p, with: .color(color),
                           style: StrokeStyle(lineWidth: 1.2, lineCap: .square))
            }
            .frame(width: size, height: size)
        }
    }

    @ViewBuilder
    static func styleGlyph(_ style: EscalationLevel, size: CGFloat = 10, color: Color) -> some View {
        switch style {
        case .gentle:     Leaf(size: size, color: color)
        case .firm:       Hand(size: size, color: color)
        case .relentless: Flame(size: size, color: color)
        }
    }

    // MARK: - Ring colour helpers

    static func ringColor(_ ring: EscalationRing) -> Color {
        switch ring {
        case .nudge:   return Palette.ringNudge
        case .math:    return Palette.ringMath
        case .mirror:  return Palette.ringMirror
        case .preview: return Palette.ringPreview
        }
    }

    static func escalationStripeColor(_ level: EscalationLevel) -> Color {
        switch level {
        case .gentle:     return Palette.ringNudge
        case .firm:       return Palette.ringMirror
        case .relentless: return Palette.ringPreview
        }
    }
}

// MARK: - Color hex helper

extension Color {
    init(hex: UInt32, opacity: Double = 1.0) {
        let r = Double((hex >> 16) & 0xFF) / 255.0
        let g = Double((hex >>  8) & 0xFF) / 255.0
        let b = Double( hex        & 0xFF) / 255.0
        self.init(.sRGB, red: r, green: g, blue: b, opacity: opacity)
    }
}

// MARK: - Common modifiers

extension View {
    /// A 1px hairline border on the named edges.
    func hairline(_ edges: Edge.Set = .top, color: Color = L.Palette.hair) -> some View {
        overlay(alignment: .top) {
            if edges.contains(.top) { color.frame(height: 1) }
        }
        .overlay(alignment: .bottom) {
            if edges.contains(.bottom) { color.frame(height: 1) }
        }
        .overlay(alignment: .leading) {
            if edges.contains(.leading) { color.frame(width: 1) }
        }
        .overlay(alignment: .trailing) {
            if edges.contains(.trailing) { color.frame(width: 1) }
        }
    }
}

// MARK: - Microcopy / kicker text style

struct Kicker: ViewModifier {
    var color: Color = L.Palette.dim
    func body(content: Content) -> some View {
        content
            .font(L.Mono.font(10.5))
            .tracking(0.6)
            .textCase(.uppercase)
            .foregroundStyle(color)
    }
}

extension View {
    func kicker(_ color: Color = L.Palette.dim) -> some View {
        modifier(Kicker(color: color))
    }
}
