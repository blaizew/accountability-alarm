import SwiftUI

/// The fist-bump stage: the Coach's send-off, a 👊 that grows into the middle,
/// a tap target, then haptic + confetti + a removal animation.
struct BumpStageView: View {
    static let dismissDelay: TimeInterval = 2.2
    static let hintDelay: TimeInterval = 2.0

    let sendOff: String?
    let fistWidthFraction: Double
    let haptic: BumpHaptic
    let choice: BumpChoice
    let snoozeLabel: String
    let isDemo: Bool
    let reduceMotionOverride: Bool?
    let onBump: () -> Void
    let onFinished: () -> Void
    let onSnooze: () -> Void

    init(sendOff: String?, fistWidthFraction: Double, haptic: BumpHaptic, choice: BumpChoice,
         snoozeLabel: String, isDemo: Bool, reduceMotion: Bool? = nil,
         onBump: @escaping () -> Void, onFinished: @escaping () -> Void,
         onSnooze: @escaping () -> Void) {
        self.sendOff = sendOff
        self.fistWidthFraction = fistWidthFraction
        self.haptic = haptic
        self.choice = choice
        self.snoozeLabel = snoozeLabel
        self.isDemo = isDemo
        self.reduceMotionOverride = reduceMotion
        self.onBump = onBump
        self.onFinished = onFinished
        self.onSnooze = onSnooze
    }

    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @State private var phase: BumpPhase = .entering
    @State private var hintVisible = false

    private var reduceMotion: Bool { reduceMotionOverride ?? systemReduceMotion }
    private var bumped: Bool { phase == .bumped }

    var body: some View {
        VStack(spacing: 0) {
            if let sendOff {
                LMessage(message: ConversationMessage(role: .assistant, content: sendOff), index: 0)
                    .opacity(bumped ? 0 : 1)
                    .animation(.easeOut(duration: 0.4), value: bumped)
            } else {
                Spacer().frame(height: 0)
            }

            GeometryReader { geo in
                let width = CGFloat(fistWidthFraction) * geo.size.width
                ZStack {
                    if bumped {
                        FistRemovalView(style: choice.removal, emoji: "👊", width: width,
                                        reduceMotion: reduceMotion, onFinished: {})
                    } else {
                        FistView(width: width, phase: phase, reduceMotion: reduceMotion)
                            .contentShape(Rectangle())
                            .onTapGesture { bump() }
                    }

                    Text("(bump the fist)")
                        .font(L.Mono.font(11))
                        .foregroundStyle(L.Palette.dim)
                        .opacity(hintVisible && !bumped ? 1 : 0)
                        .animation(.easeOut(duration: 0.4), value: hintVisible)
                        .animation(.easeOut(duration: 0.4), value: bumped)
                        .position(x: geo.size.width / 2,
                                  y: geo.size.height / 2 + width / 2 + 12 + 7)
                        .allowsHitTesting(false)

                    if bumped && !reduceMotion {
                        // Same region as the fist, so the fist center is the region center.
                        ConfettiView(pattern: choice.pattern, shapes: choice.shapes,
                                     palette: choice.palette, density: choice.density,
                                     size: choice.size,
                                     origin: CGPoint(x: geo.size.width / 2, y: geo.size.height / 2),
                                     countMultiplier: choice.removal == .burst ? 2.0 : 1.0)
                            .allowsHitTesting(false)
                    }
                }
                .frame(width: geo.size.width, height: geo.size.height)
            }

            if !isDemo {
                Button(action: onSnooze) {
                    Text(snoozeLabel)
                        .font(L.Mono.font(10.5))
                        .tracking(0.6)
                        .textCase(.uppercase)
                        .foregroundStyle(L.Palette.muted)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .overlay(Rectangle().stroke(L.Palette.hair2, lineWidth: 1))
                }
                .buttonStyle(.plain)
                .padding(.horizontal, L.Space.pageH)
                .padding(.bottom, 12)
                .opacity(bumped ? 0 : 1)
                .animation(.easeOut(duration: 0.4), value: bumped)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(L.Palette.bg.ignoresSafeArea())
        .onAppear { HapticService.shared.prepare() }
        .task {
            try? await Task.sleep(for: .seconds(reduceMotion ? 0.3 : 0.9))
            guard !Task.isCancelled else { return }
            phase = .ready
            try? await Task.sleep(for: .seconds(Self.hintDelay))
            guard !Task.isCancelled else { return }
            hintVisible = true
        }
        .task(id: bumped) {
            guard bumped else { return }
            try? await Task.sleep(for: .seconds(Self.dismissDelay))
            guard !Task.isCancelled else { return }
            onFinished()
        }
    }

    private func bump() {
        guard phase.canBump else { return }
        onBump()
        HapticService.shared.play(haptic)
        phase = .bumped
    }
}
