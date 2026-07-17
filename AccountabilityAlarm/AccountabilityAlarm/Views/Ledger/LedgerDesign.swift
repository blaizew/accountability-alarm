import SwiftUI

// LEDGER design tokens — dense, monospace, terminal-influenced.
// Palette re-themed to the cbt-i-coach amber night scheme; it no longer mirrors
// `ledger-shared.jsx` colors. Typography and spacing still do.

enum L {

    // MARK: - Palette

    enum Palette {
        // Backgrounds - cbt-i-coach night ramp, warm hue 45.
        static let bg  = Color(hex: 0x140B07) // oklch(0.160 0.018 45)
        static let bg2 = Color(hex: 0x1F1410) // oklch(0.205 0.020 45)
        static let bg3 = Color(hex: 0x271B16) // oklch(0.235 0.021 45)
        static let bg4 = Color(hex: 0x2F221C) // oklch(0.265 0.023 45)

        // Hairlines - warm tint rather than neutral white.
        static let hair  = Color(hex: 0xD9BFA6, opacity: 0.06)
        static let hair2 = Color(hex: 0xD9BFA6, opacity: 0.12)
        static let hair3 = Color(hex: 0xD9BFA6, opacity: 0.18)

        // Text - cbt-i-coach night ramp.
        static let fg     = Color(hex: 0xD9BFA6) // oklch(0.820 0.045 65)
        static let muted  = Color(hex: 0x99816E) // oklch(0.620 0.040 60)
        static let dim    = Color(hex: 0x69574B) // oklch(0.470 0.030 55)
        static let dimmer = Color(hex: 0x4E3F36) // oklch(0.380 0.025 52)

        static let accent = Color(hex: 0xCF7D44) // cbt-i-coach night accent

        // Ring colours - escalation ramp. Hue stays warm (30-70); intensity is
        // carried by climbing chroma, so no stage emits blue light at night.
        // oklch(0.70 0.03 60) faint warm
        static let ringNudge   = Color(hex: 0xAD9A8C)
        // oklch(0.74 0.08 70) straw
        static let ringMath    = Color(hex: 0xCCA273)
        // oklch(0.72 0.13 55) amber
        static let ringMirror  = Color(hex: 0xE28D4F)
        // oklch(0.65 0.18 30) ember red
        static let ringPreview = Color(hex: 0xE85A48)

        static let goodGreen  = Color(hex: 0x94A676) // oklch(0.70 0.07 125)
        static let warnYellow = Color(hex: 0xD9A850) // oklch(0.76 0.12 80)
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

    // MARK: - Ring colour helpers (legacy — only used by HistoryView analytics)

    static func ringColor(_ ring: EscalationRing) -> Color {
        switch ring {
        case .nudge:   return Palette.ringNudge
        case .math:    return Palette.ringMath
        case .mirror:  return Palette.ringMirror
        case .preview: return Palette.ringPreview
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
