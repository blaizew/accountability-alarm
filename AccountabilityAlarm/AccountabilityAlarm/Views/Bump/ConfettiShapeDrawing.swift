import SwiftUI

/// Draws one confetti particle shape. The caller sets translation, rotation and
/// opacity; `rect` is the particle's bounds centered on the origin.
enum ConfettiShapeDrawing {
    private enum Kind {
        case square, circle, shortStrip, longStrip, zigzag, semicircle
        case star4, flower, sprinkle, ring(CGFloat)
        case symbol(Int) // index into symbolNames(for:)
    }

    private static func kinds(for shapes: ConfettiShapes) -> [Kind] {
        switch shapes {
        case .clean: return [.square]
        case .classic: return [.circle, .shortStrip, .longStrip, .zigzag, .semicircle]
        case .stars: return [.circle, .symbol(0)]
        case .sparkles: return [.circle, .symbol(0), .star4]
        case .love: return [.symbol(0), .circle, .symbol(1)]
        case .cake: return [.circle, .symbol(0), .sprinkle]
        case .bubbles: return [.ring(0.08), .ring(0.16)]
        case .garden: return [.circle, .flower, .symbol(0)]
        case .cards: return [.symbol(0), .symbol(1), .symbol(2), .symbol(3)]
        case .snow: return [.circle, .symbol(0)]
        }
    }

    /// SF Symbol names, in the order `.symbol(i)` refers to.
    static func symbolNames(for shapes: ConfettiShapes) -> [String] {
        switch shapes {
        case .clean, .classic, .bubbles: return []
        case .stars: return ["star.fill"]
        case .sparkles: return ["sparkle"]
        case .love: return ["heart.fill", "suit.heart.fill"]
        case .cake: return ["star.fill"]
        case .garden: return ["leaf.fill"]
        case .cards: return ["suit.spade.fill", "suit.heart.fill", "suit.diamond.fill", "suit.club.fill"]
        case .snow: return ["snowflake"]
        }
    }

    /// `symbols` must match `symbolNames(for: shapes)` in order and count.
    static func draw(_ shapes: ConfettiShapes, index: Int, in ctx: inout GraphicsContext,
                     rect: CGRect, color: Color, symbols: [Image]) {
        let list = kinds(for: shapes)
        let shading = GraphicsContext.Shading.color(color)
        let w = rect.width, h = rect.height
        switch list[index % list.count] {
        case .square:
            ctx.fill(Path(rect), with: shading)
        case .circle:
            ctx.fill(Path(ellipseIn: rect), with: shading)
        case .shortStrip:
            ctx.fill(Path(CGRect(x: rect.minX, y: rect.midY - h * 0.2, width: w, height: h * 0.4)), with: shading)
        case .longStrip:
            ctx.fill(Path(CGRect(x: rect.midX - w * 0.8, y: rect.midY - h * 0.175, width: w * 1.6, height: h * 0.35)), with: shading)
        case .zigzag:
            var p = Path()
            let x0 = rect.minX - w * 0.3, step = w * 1.6 / 4
            p.move(to: CGPoint(x: x0, y: rect.midY))
            for i in 1...4 {
                p.addLine(to: CGPoint(x: x0 + step * CGFloat(i), y: rect.midY + (i % 2 == 1 ? -h * 0.35 : h * 0.35)))
            }
            ctx.stroke(p, with: shading, style: StrokeStyle(lineWidth: max(1.5, h * 0.2), lineJoin: .round))
        case .semicircle:
            var p = Path()
            p.addArc(center: CGPoint(x: rect.midX, y: rect.midY), radius: w / 2,
                     startAngle: .degrees(180), endAngle: .degrees(0), clockwise: false)
            p.closeSubpath()
            ctx.fill(p, with: shading)
        case .star4:
            var p = Path()
            let c = CGPoint(x: rect.midX, y: rect.midY), outer = w / 2, inner = w * 0.12
            for i in 0..<8 {
                let a = CGFloat(i) * .pi / 4 - .pi / 2
                let r = i % 2 == 0 ? outer : inner
                let pt = CGPoint(x: c.x + cos(a) * r, y: c.y + sin(a) * r)
                if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
            }
            p.closeSubpath()
            ctx.fill(p, with: shading)
        case .flower:
            var p = Path()
            let c = CGPoint(x: rect.midX, y: rect.midY), pr = w * 0.22
            for i in 0..<5 {
                let a = CGFloat(i) * 2 * .pi / 5 - .pi / 2
                let pc = CGPoint(x: c.x + cos(a) * w * 0.28, y: c.y + sin(a) * w * 0.28)
                p.addEllipse(in: CGRect(x: pc.x - pr, y: pc.y - pr, width: pr * 2, height: pr * 2))
            }
            ctx.fill(p, with: shading)
        case .sprinkle:
            let r = CGRect(x: rect.midX - w * 0.6, y: rect.midY - h * 0.15, width: w * 1.2, height: h * 0.3)
            ctx.fill(Path(roundedRect: r, cornerRadius: h * 0.15), with: shading)
        case .ring(let frac):
            let lw = max(1, w * frac)
            ctx.stroke(Path(ellipseIn: rect.insetBy(dx: lw / 2, dy: lw / 2)), with: shading, lineWidth: lw)
        case .symbol(let i):
            guard i < symbols.count else { return }
            var img = ctx.resolve(symbols[i].renderingMode(.template))
            img.shading = shading
            ctx.draw(img, in: rect)
        }
    }
}
