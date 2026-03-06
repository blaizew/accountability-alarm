import AVFoundation
import UIKit
import Observation

@Observable
final class AlarmSoundService {
    var isPlaying = false

    private var audioPlayer: AVAudioPlayer?
    private var hapticTimer: Timer?
    private let hapticGenerator = UIImpactFeedbackGenerator(style: .heavy)

    func startAlarm() {
        guard !isPlaying else { return }

        do {
            try AudioSessionService.shared.configureForPlayback()
        } catch {
            return
        }

        // Load and loop the alarm sound
        if let url = Bundle.main.url(forResource: "alarm-sound", withExtension: "caf") {
            do {
                audioPlayer = try AVAudioPlayer(contentsOf: url)
                audioPlayer?.numberOfLoops = -1 // Loop indefinitely
                audioPlayer?.volume = 1.0
                audioPlayer?.play()
            } catch {
                // Fall back to system sound if file fails
            }
        }

        // Start haptic vibration pattern
        hapticGenerator.prepare()
        hapticTimer = Timer.scheduledTimer(withTimeInterval: 0.6, repeats: true) { [weak self] _ in
            self?.hapticGenerator.impactOccurred(intensity: 1.0)
        }
        // Fire immediately too
        hapticGenerator.impactOccurred(intensity: 1.0)

        isPlaying = true
    }

    func stopAlarm() {
        audioPlayer?.stop()
        audioPlayer = nil
        hapticTimer?.invalidate()
        hapticTimer = nil
        AudioSessionService.shared.deactivate()
        isPlaying = false
    }
}
