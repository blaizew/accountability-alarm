import UIKit
import CoreHaptics

/// Plays the fist-bump haptic presets. Core Haptics first, UIKit generators as fallback.
@MainActor
final class HapticService {
    static let shared = HapticService()

    private var engine: CHHapticEngine?
    private var didPrepare = false

    private init() {}

    /// Creates and starts the Core Haptics engine once. Safe to call many times.
    func prepare() {
        guard !didPrepare else { return }
        didPrepare = true
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else { return }
        do {
            let engine = try CHHapticEngine()
            engine.isAutoShutdownEnabled = false
            engine.resetHandler = { [weak self] in
                Task { @MainActor in
                    try? self?.engine?.start()
                }
            }
            try engine.start()
            self.engine = engine
        } catch {
            self.engine = nil
        }
    }

    func play(_ preset: BumpHaptic) {
        if preset == .success {
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            return
        }
        prepare()
        guard let engine else {
            playFallback(preset)
            return
        }
        do {
            let pattern = try CHHapticPattern(events: events(for: preset), parameters: [])
            let player = try engine.makePlayer(with: pattern)
            try engine.start()
            try player.start(atTime: CHHapticTimeImmediate)
        } catch {
            playFallback(preset)
        }
    }

    private func events(for preset: BumpHaptic) -> [CHHapticEvent] {
        func params(_ intensity: Float, _ sharpness: Float) -> [CHHapticEventParameter] {
            [
                CHHapticEventParameter(parameterID: .hapticIntensity, value: intensity),
                CHHapticEventParameter(parameterID: .hapticSharpness, value: sharpness),
            ]
        }
        switch preset {
        case .buzz:
            return [CHHapticEvent(eventType: .hapticContinuous, parameters: params(0.8, 0.3),
                                  relativeTime: 0, duration: 0.25)]
        case .click:
            return [CHHapticEvent(eventType: .hapticTransient, parameters: params(1.0, 1.0),
                                  relativeTime: 0)]
        case .thudClick:
            return [
                CHHapticEvent(eventType: .hapticTransient, parameters: params(1.0, 0.15), relativeTime: 0),
                CHHapticEvent(eventType: .hapticTransient, parameters: params(0.9, 1.0), relativeTime: 0.06),
            ]
        case .success:
            return []
        }
    }

    private func playFallback(_ preset: BumpHaptic) {
        switch preset {
        case .buzz, .thudClick:
            UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
        case .click:
            UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
        case .success:
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        }
    }
}
