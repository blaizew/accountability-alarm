import SwiftUI

/// Plays one of six exit animations for the fist, once, then calls `onFinished`.
/// Fills the space it is given and centers the fist in it.
struct FistRemovalView: View {
    let style: FistRemoval
    let emoji: String
    let width: CGFloat
    let reduceMotion: Bool
    let onFinished: () -> Void

    init(style: FistRemoval, emoji: String, width: CGFloat, reduceMotion: Bool,
         onFinished: @escaping () -> Void) {
        self.style = style
        self.emoji = emoji
        self.width = width
        self.reduceMotion = reduceMotion
        self.onFinished = onFinished
        // Ring starts at the fist's width, fully visible, on the first render.
        _ringDiameter = State(initialValue: width)
    }

    // Transform-based styles
    @State private var scale: CGFloat = 1
    @State private var opacity: Double = 1
    @State private var blur: CGFloat = 0
    @State private var yOffset: CGFloat = 0
    // Shockwave
    @State private var flash: Double = 0
    @State private var ringDiameter: CGFloat
    @State private var ringOpacity: Double = 1
    // Raster styles
    @State private var raster: UIImage?
    @State private var sim = PieceSimulation()
    @State private var finished = false

    private var duration: TimeInterval {
        if reduceMotion { return 0.4 }
        switch style {
        case .burst: return 0.2
        case .dissolve, .shatter: return 1.0
        case .recoil, .shockwave: return 0.7
        case .pullAway: return 0.9
        }
    }

    private var usesRaster: Bool {
        !reduceMotion && (style == .dissolve || style == .shatter)
    }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                if usesRaster {
                    pieceCanvas
                } else {
                    fist
                        .overlay { if style == .shockwave && !reduceMotion { flashOverlay } }
                        .scaleEffect(scale)
                        .offset(y: yOffset)
                        .blur(radius: blur)
                        .opacity(opacity)
                    if style == .shockwave && !reduceMotion {
                        Circle()
                            .stroke(L.Palette.fg, lineWidth: 1.5)
                            .frame(width: ringDiameter, height: ringDiameter)
                            .opacity(ringOpacity)
                    }
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .onAppear { start(screenWidth: geo.size.width) }
        }
        .allowsHitTesting(false)
        .task {
            try? await Task.sleep(for: .seconds(duration))
            guard !Task.isCancelled, !finished else { return }
            finished = true
            onFinished()
        }
    }

    private var fist: some View {
        Text(emoji)
            .font(.system(size: width * FistView.fontFactor))
            .fixedSize()
            .frame(width: width, height: width)
    }

    private var flashOverlay: some View {
        Color.white
            .blendMode(.plusLighter)
            .mask(fist)
            .opacity(flash)
    }

    // MARK: - Start

    private func start(screenWidth: CGFloat) {
        if reduceMotion {
            withAnimation(.easeOut(duration: 0.4)) { opacity = 0 }
            return
        }
        switch style {
        case .burst:
            withAnimation(.easeOut(duration: 0.08)) { scale = 1.15 } completion: {
                withAnimation(.linear(duration: 0.1)) { opacity = 0 }
            }
        case .dissolve, .shatter:
            raster = EmojiRaster.image(emoji, pointSize: width * FistView.fontFactor)
        case .recoil:
            withAnimation(.spring(response: 0.25, dampingFraction: 0.5)) {
                scale = 0.88
                yOffset = 20
            }
            Task {
                try? await Task.sleep(for: .seconds(0.12))
                guard !Task.isCancelled else { return }
                withAnimation(.easeIn(duration: 0.5)) { scale = 0 }
            }
        case .pullAway:
            withAnimation(.easeIn(duration: 0.9)) {
                scale = 0.05
                blur = 10
                opacity = 0
            }
        case .shockwave:
            withAnimation(.linear(duration: 0.7)) {
                ringDiameter = screenWidth * 1.6
                ringOpacity = 0
            }
            withAnimation(.linear(duration: 0.5)) { opacity = 0 }
            withAnimation(.linear(duration: 0.06)) { flash = 1 } completion: {
                withAnimation(.linear(duration: 0.2)) { flash = 0 }
            }
        }
    }

    // MARK: - Raster pieces (dissolve, shatter)

    private struct Piece {
        var image: Image
        var cell: CGSize
        var position: CGPoint   // offset from the canvas center
        var velocity: CGVector
        var rotation: Double
        var spin: Double
        var life: TimeInterval
    }

    /// Reference holder so the draw closure can build and advance pieces
    /// without triggering view updates.
    private final class PieceSimulation {
        var pieces: [Piece] = []
        var start: Date?
        var lastT: TimeInterval = 0
        var built = false
    }

    private var pieceCanvas: some View {
        TimelineView(.animation) { timeline in
            Canvas { ctx, size in
                drawPieces(&ctx, size: size, now: timeline.date)
            }
        }
    }

    private func drawPieces(_ ctx: inout GraphicsContext, size: CGSize, now: Date) {
        guard let raster, let cg = raster.cgImage else { return }
        if sim.start == nil { sim.start = now }
        let t = now.timeIntervalSince(sim.start ?? now)
        guard t <= duration else { return }

        let isShatter = style == .shatter
        if !sim.built {
            sim.built = true
            sim.pieces = makePieces(cg, scale: raster.scale, shatter: isShatter)
        }
        let dt = min(max(t - sim.lastT, 0), 0.05)
        sim.lastT = t
        let center = CGPoint(x: size.width / 2, y: size.height / 2)

        for i in sim.pieces.indices {
            sim.pieces[i].position.x += sim.pieces[i].velocity.dx * dt
            sim.pieces[i].position.y += sim.pieces[i].velocity.dy * dt
            if isShatter { sim.pieces[i].velocity.dy += 900 * dt }
            sim.pieces[i].rotation += sim.pieces[i].spin * dt

            let p = sim.pieces[i]
            let alpha: Double
            if isShatter {
                alpha = t < 0.7 ? 1 : max(0, 1 - (t - 0.7) / 0.3)
            } else {
                alpha = max(0, 1 - t / p.life)
            }
            guard alpha > 0 else { continue }

            let rect = CGRect(x: -p.cell.width / 2, y: -p.cell.height / 2,
                              width: p.cell.width, height: p.cell.height)
            ctx.drawLayer { layer in
                layer.opacity = alpha
                layer.translateBy(x: center.x + p.position.x, y: center.y + p.position.y)
                layer.rotate(by: .radians(p.rotation))
                if !isShatter { layer.clip(to: Path(ellipseIn: rect)) }
                layer.draw(p.image, in: rect)
            }
        }
    }

    private func makePieces(_ cg: CGImage, scale: CGFloat, shatter: Bool) -> [Piece] {
        let n = shatter ? 5 : 12
        let pxW = CGFloat(cg.width) / CGFloat(n)
        let pxH = CGFloat(cg.height) / CGFloat(n)
        let cell = CGSize(width: width / CGFloat(n), height: width / CGFloat(n))
        var result: [Piece] = []
        result.reserveCapacity(n * n)
        for row in 0..<n {
            for col in 0..<n {
                let crop = CGRect(x: CGFloat(col) * pxW, y: CGFloat(row) * pxH, width: pxW, height: pxH)
                guard let piece = cg.cropping(to: crop) else { continue }
                let img = Image(decorative: piece, scale: scale)
                let pos = CGPoint(x: (CGFloat(col) + 0.5) * cell.width - width / 2,
                                  y: (CGFloat(row) + 0.5) * cell.height - width / 2)
                // Unit vector pointing away from the center; random if at the center.
                let len = hypot(pos.x, pos.y)
                var dir = len > 0.5
                    ? CGVector(dx: pos.x / len, dy: pos.y / len)
                    : { let a = Double.random(in: 0..<(2 * .pi)); return CGVector(dx: cos(a), dy: sin(a)) }()
                let velocity: CGVector
                let life: TimeInterval
                if shatter {
                    let speed = Double.random(in: 150...400)
                    velocity = CGVector(dx: dir.dx * speed, dy: dir.dy * speed)
                    life = 1.0
                } else {
                    // Up and outward.
                    dir = CGVector(dx: dir.dx, dy: dir.dy - 0.8)
                    let dl = max(hypot(dir.dx, dir.dy), 0.001)
                    let speed = Double.random(in: 40...160)
                    velocity = CGVector(dx: dir.dx / dl * speed, dy: dir.dy / dl * speed)
                    life = Double.random(in: 0.6...1.0)
                }
                result.append(Piece(image: img, cell: cell, position: pos, velocity: velocity,
                                    rotation: 0, spin: shatter ? Double.random(in: -6...6) : 0,
                                    life: life))
            }
        }
        return result
    }
}

#Preview {
    ZStack {
        L.Palette.bg.ignoresSafeArea()
        FistRemovalView(style: .shatter, emoji: "👊", width: 393 * 0.65,
                        reduceMotion: false, onFinished: {})
    }
}
