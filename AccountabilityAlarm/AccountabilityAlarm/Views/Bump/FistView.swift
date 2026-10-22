import SwiftUI

/// The fist emoji. Grows in on appear, then breathes while the phase is `.ready`.
struct FistView: View {
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
    @State private var breathing = false

    var body: some View {
        Text(emoji)
            .font(.system(size: width * 0.82))
            .frame(width: width, height: width)
            .scaleEffect(scale)
            .blur(radius: reduceMotion || entered ? 0 : 8)
            .opacity(reduceMotion && !entered ? 0 : 1)
            .onAppear {
                withAnimation(reduceMotion ? .easeOut(duration: 0.3) : .easeOut(duration: 0.9)) {
                    entered = true
                }
                startBreathingIfReady()
            }
            .onChange(of: phase) { _, _ in startBreathingIfReady() }
    }

    private var scale: CGFloat {
        if reduceMotion { return 1 }
        return (entered ? 1 : 0.05) * (breathing ? 1.03 : 1.0)
    }

    private func startBreathingIfReady() {
        guard phase == .ready, !reduceMotion, !breathing else { return }
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
