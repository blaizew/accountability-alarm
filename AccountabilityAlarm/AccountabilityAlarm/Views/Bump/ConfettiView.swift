import SwiftUI

/// One-shot confetti burst. Plays from first appearance for `duration`, then
/// draws nothing. The parent removes the view.
struct ConfettiView: View {
    static let duration: TimeInterval = 2.0

    let pattern: ConfettiPattern
    let shapes: ConfettiShapes
    let palette: ConfettiPalette
    let density: Double
    let size: Double
    let origin: CGPoint
    var countMultiplier: Double = 1.0

    init(pattern: ConfettiPattern, shapes: ConfettiShapes, palette: ConfettiPalette,
         density: Double, size: Double, origin: CGPoint, countMultiplier: Double = 1.0) {
        self.pattern = pattern
        self.shapes = shapes
        self.palette = palette
        self.density = density
        self.size = size
        self.origin = origin
        self.countMultiplier = countMultiplier
    }

    private struct Particle {
        var birth: TimeInterval
        var position: CGPoint
        var velocity: CGVector
        var rotation: Double
        var spin: Double
        var shapeIndex: Int
        var color: Color
        var size: CGFloat
        var life: TimeInterval
        var phase: Double
        var wobble: Double
        var gravityScale: Double
    }

    /// Reference holder so the draw closure can create and advance particles
    /// without triggering view updates.
    private final class Simulation {
        var particles: [Particle] = []
        var start: Date?
        var lastT: TimeInterval = 0
        var spawned = false
        var symbolNames: [String] = []
        var colors: [Color] = []
    }

    @State private var sim = Simulation()

    var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { ctx, canvasSize in
                draw(&ctx, canvasSize: canvasSize, now: timeline.date)
            }
        }
        .allowsHitTesting(false)
    }

    // MARK: - Drawing

    private func draw(_ ctx: inout GraphicsContext, canvasSize: CGSize, now: Date) {
        if sim.start == nil { sim.start = now }
        let t = now.timeIntervalSince(sim.start ?? now)
        guard t <= Self.duration else { return }

        if !sim.spawned {
            sim.spawned = true
            sim.symbolNames = ConfettiShapeDrawing.symbolNames(for: shapes)
            sim.particles = makeParticles(width: canvasSize.width)
            sim.colors = Array(Set(sim.particles.map(\.color)))
        }
        // Resolve each (symbol, color) pair once per frame, not once per particle.
        let symbols = ConfettiShapeDrawing.SymbolCache(ctx: ctx, names: sim.symbolNames, colors: sim.colors)
        let dt = min(max(t - sim.lastT, 0), 0.05)
        sim.lastT = t
        let drag = pow(0.98, dt * 60)

        for i in sim.particles.indices {
            let age = t - sim.particles[i].birth
            if age < 0 { continue }
            let step = min(dt, age) // a particle born mid-frame only moves since birth
            var p = sim.particles[i]
            p.velocity.dy += 900 * p.gravityScale * step
            let wob = sin(t * 6 + p.phase) * 30 * p.wobble
            p.velocity.dx *= drag
            p.velocity.dy *= drag
            p.position.x += (p.velocity.dx + wob) * step
            p.position.y += p.velocity.dy * step
            p.rotation += p.spin * step
            sim.particles[i] = p

            if age >= p.life { continue }
            let fadeStart = p.life * 0.8
            let alpha = age <= fadeStart ? 1.0 : max(0, 1 - (age - fadeStart) / (p.life - fadeStart))
            let r = CGRect(x: -p.size / 2, y: -p.size / 2, width: p.size, height: p.size)
            var c = ctx // value copy isolates transform and opacity without a transparency layer
            c.opacity = alpha
            c.translateBy(x: p.position.x, y: p.position.y)
            c.rotate(by: .radians(p.rotation))
            ConfettiShapeDrawing.draw(shapes, index: p.shapeIndex, in: &c, rect: r,
                                      color: p.color, symbols: symbols)
        }
    }

    // MARK: - Spawning

    private func makeParticles(width: CGFloat) -> [Particle] {
        let colors = ConfettiPalettes.usable(palette).map { Color(hex: $0) }
        guard !colors.isEmpty else { return [] }
        let scale = density * countMultiplier
        var out: [Particle] = []

        func count(_ base: Int) -> Int { max(Int((Double(base) * scale).rounded()), 1) }

        func burst(_ base: Int, at pt: CGPoint, birth: TimeInterval) {
            for _ in 0..<count(base) {
                let a = Double.random(in: 0..<(2 * .pi))
                let s = Double.random(in: 350...700)
                out.append(make(at: pt, vx: cos(a) * s, vy: sin(a) * s, birth: birth,
                                life: .random(in: 1.4...2.0), wobble: 1))
            }
        }

        func make(at pt: CGPoint, vx: Double, vy: Double, birth: TimeInterval,
                  life: TimeInterval, wobble: Double, gravityScale: Double = 1) -> Particle {
            Particle(birth: birth, position: pt, velocity: CGVector(dx: vx, dy: vy),
                     rotation: .random(in: 0..<(2 * .pi)), spin: .random(in: -8...8),
                     shapeIndex: Int.random(in: 0..<1000), color: colors.randomElement()!,
                     size: CGFloat(size) * .random(in: 7...13), life: min(life, Self.duration - birth),
                     phase: .random(in: 0..<(2 * .pi)), wobble: wobble, gravityScale: gravityScale)
        }

        switch pattern {
        case .pop:
            burst(120, at: origin, birth: 0)
        case .spray:
            for _ in 0..<count(100) {
                let a = Double.random(in: -35...35) * .pi / 180
                let s = Double.random(in: 700...1000)
                out.append(make(at: origin, vx: sin(a) * s, vy: -cos(a) * s,
                                birth: .random(in: 0...0.4), life: .random(in: 1.4...2.0), wobble: 1))
            }
        case .fireworks:
            burst(60, at: origin, birth: 0)
            burst(60, at: CGPoint(x: origin.x - 0.25 * width, y: origin.y), birth: 0.15)
            burst(60, at: CGPoint(x: origin.x + 0.25 * width, y: origin.y), birth: 0.30)
        case .rain:
            for _ in 0..<count(150) {
                out.append(make(at: CGPoint(x: .random(in: 0...max(width, 1)), y: -20),
                                vx: 0, vy: .random(in: 150...300),
                                birth: .random(in: 0...1.2), life: .random(in: 1.4...2.0), wobble: 2, gravityScale: 0.15))
            }
            burst(30, at: origin, birth: 0)
        }
        return out
    }
}

#Preview("pop classic") {
    ZStack {
        L.Palette.bg.ignoresSafeArea()
        ConfettiView(pattern: .pop, shapes: .classic, palette: ConfettiPalettes.site[0],
                     density: 1, size: 1, origin: CGPoint(x: 200, y: 400))
    }
}
