import SwiftUI

/// The fist emoji. Grows in on appear, then breathes while the phase is `.ready`.
struct FistView: View {
    /// Emoji font size as a multiple of the frame width. Chosen so the visible ink is about the frame width.
    static let fontFactor: CGFloat = 1.1
    /// Visible ink height of the glyph as a multiple of the frame width (measured). The hint anchors to it.
    static let inkHeightFactor: CGFloat = 0.875

    let emoji: String
    let width: CGFloat
    let phase: BumpPhase
    let reduceMotion: Bool

    init(emoji: String = "👊", width: CGFloat, phase: BumpPhase, reduceMotion: Bool) {
        self.emoji = emoji
        self.width = width
        self.phase = phase
        self.reduceMotion = reduceMotion
    }

    @State private var entered = false
    @State private var entranceDone = false
    @State private var breathing = false

    var body: some View {
        Text(emoji)
            .font(.system(size: width * FistView.fontFactor))
            .fixedSize()
            .frame(width: width, height: width)
            .scaleEffect(reduceMotion ? 1 : (entered ? 1 : 0.05))
            .scaleEffect(breathing ? 1.03 : 1)
            .blur(radius: reduceMotion || entered ? 0 : 8)
            .opacity(reduceMotion && !entered ? 0 : 1)
            .onAppear {
                withAnimation(reduceMotion ? .easeOut(duration: 0.3) : .easeOut(duration: 0.9)) {
                    entered = true
                } completion: {
                    entranceDone = true
                    startBreathingIfReady()
                }
            }
            .onChange(of: phase) { _, _ in startBreathingIfReady() }
    }

    private func startBreathingIfReady() {
        guard phase == .ready, entranceDone, !reduceMotion, !breathing else { return }
        withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true)) {
            breathing = true
        }
    }
}

#Preview {
    ZStack {
        L.Palette.bg.ignoresSafeArea()
        FistView(width: 393 * 0.65, phase: .ready, reduceMotion: false)
    }
    .frame(width: 393)
}
