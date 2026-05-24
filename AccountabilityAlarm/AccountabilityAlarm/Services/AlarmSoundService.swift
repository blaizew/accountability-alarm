import AVFoundation
import UIKit
import CoreHaptics
import Observation

@Observable
final class AlarmSoundService {
    var isPlaying = false

    private var audioPlayer: AVAudioPlayer?
    private var hapticEngine: CHHapticEngine?
    private var hapticPlayer: CHHapticAdvancedPatternPlayer?

    // Fallback haptic when CoreHaptics is unavailable (older devices).
    private var fallbackTimer: Timer?
    private let fallbackGenerator = UIImpactFeedbackGenerator(style: .heavy)

    func startAlarm() {
        guard !isPlaying else { return }

        do {
            try AudioSessionService.shared.configureForPlayback()
        } catch {
            return
        }

        if let url = Bundle.main.url(forResource: "alarm-sound", withExtension: "caf") {
            do {
                audioPlayer = try AVAudioPlayer(contentsOf: url)
                audioPlayer?.numberOfLoops = -1
                audioPlayer?.volume = 1.0          // ceiling is system ringer volume
                audioPlayer?.prepareToPlay()
                audioPlayer?.play()
            } catch {
                // Fall through; haptics still fire.
            }
        }

        startHaptics()
        isPlaying = true
    }

    func stopAlarm() {
        audioPlayer?.stop()
        audioPlayer = nil
        stopHaptics()
        AudioSessionService.shared.deactivate()
        isPlaying = false
    }

    // MARK: - Haptics

    private func startHaptics() {
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else {
            startFallbackHaptics(); return
        }
        do {
            let engine = try CHHapticEngine()
            engine.isAutoShutdownEnabled = false
            engine.stoppedHandler = { _ in /* let stop() handle teardown */ }
            engine.resetHandler = { [weak self] in
                try? self?.hapticEngine?.start()
            }
            try engine.start()
            self.hapticEngine = engine

            // Pattern: two strong taps + a continuous buzz, looped.
            let tap1 = CHHapticEvent(
                eventType: .hapticTransient,
                parameters: [
                    .init(parameterID: .hapticIntensity, value: 1.0),
                    .init(parameterID: .hapticSharpness, value: 1.0),
                ],
                relativeTime: 0
            )
            let tap2 = CHHapticEvent(
                eventType: .hapticTransient,
                parameters: [
                    .init(parameterID: .hapticIntensity, value: 1.0),
                    .init(parameterID: .hapticSharpness, value: 0.9),
                ],
                relativeTime: 0.15
            )
            let buzz = CHHapticEvent(
                eventType: .hapticContinuous,
                parameters: [
                    .init(parameterID: .hapticIntensity, value: 1.0),
                    .init(parameterID: .hapticSharpness, value: 0.6),
                ],
                relativeTime: 0.3,
                duration: 0.4
            )
            let pattern = try CHHapticPattern(events: [tap1, tap2, buzz], parameters: [])
            let player = try engine.makeAdvancedPlayer(with: pattern)
            player.loopEnabled = true
            try player.start(atTime: 0)
            self.hapticPlayer = player
        } catch {
            startFallbackHaptics()
        }
    }

    private func stopHaptics() {
        try? hapticPlayer?.stop(atTime: 0)
        hapticPlayer = nil
        hapticEngine?.stop()
        hapticEngine = nil
        fallbackTimer?.invalidate()
        fallbackTimer = nil
    }

    private func startFallbackHaptics() {
        fallbackGenerator.prepare()
        fallbackGenerator.impactOccurred(intensity: 1.0)
        fallbackTimer = Timer.scheduledTimer(withTimeInterval: 0.6, repeats: true) { [weak self] _ in
            self?.fallbackGenerator.impactOccurred(intensity: 1.0)
        }
    }
}
