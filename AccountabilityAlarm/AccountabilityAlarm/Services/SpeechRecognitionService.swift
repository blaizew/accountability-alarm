import Speech
import Observation
import AVFoundation

@Observable
final class SpeechRecognitionService {
    var isListening = false
    var transcript = ""
    var error: String?

    private var recognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var audioEngine: AVAudioEngine?

    /// Set during `stopListening()` and cleared once the recognizer finishes
    /// processing the buffered audio (the `isFinal` callback). While true,
    /// `transcript` may still be receiving its final partial — the UI can use
    /// this to defer reading the transcript until it's stable.
    private(set) var isFinalizing = false

    /// True when the last session ended on its own — recognizer error or
    /// the system's recognition-duration limit — rather than via
    /// `stopListening()`/`cancelListening()`. Views watch `isListening`
    /// flip false and use this to rescue the captured transcript instead of
    /// silently dropping it on the next mic tap.
    private(set) var endedUnexpectedly = false

    init() {
        recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    }

    func requestPermission() async -> Bool {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
    }

    /// Pre-warm the audio session. Called from the conversation view on
    /// appear so the mic is ready by the time the user taps the button —
    /// otherwise the first ~100-200ms of audio is dropped while the session
    /// activates. Cheap to call; safe to call repeatedly.
    func prepare() {
        try? AudioSessionService.shared.configureForRecording()
    }

    func startListening() {
        guard let recognizer, recognizer.isAvailable else {
            error = "Speech recognition unavailable"
            return
        }

        // If a prior session is still finalizing, tear it down hard before
        // starting fresh — we don't want overlapping recognition tasks.
        if isFinalizing { forceCleanup() }

        do {
            try AudioSessionService.shared.configureForRecording()

            recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
            guard let request = recognitionRequest else { return }
            request.shouldReportPartialResults = true

            let engine = AVAudioEngine()
            self.audioEngine = engine

            recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
                // The recognizer calls back on its own queue; transcript and
                // the listening flags drive SwiftUI, so hop to main before
                // touching them.
                let text = result?.bestTranscription.formattedString
                let finished = (result?.isFinal ?? false) || error != nil
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    if let text { self.transcript = text }
                    if finished {
                        // Drain complete — safe to release the audio session.
                        self.forceCleanup()
                    }
                }
            }

            let inputNode = engine.inputNode
            let format = inputNode.outputFormat(forBus: 0)
            inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
                request.append(buffer)
            }

            engine.prepare()
            try engine.start()
            isListening = true
            transcript = ""
            error = nil
            endedUnexpectedly = false
        } catch {
            self.error = "Failed to start listening: \(error.localizedDescription)"
        }
    }

    /// Stop capturing audio but allow the recognizer to drain any buffered
    /// audio that hasn't been transcribed yet. The cleanup happens in the
    /// recognition task's callback once `isFinal` fires. This eliminates the
    /// end-of-utterance truncation we used to see when `cancel()` was called
    /// immediately.
    func stopListening() {
        guard isListening else { return }
        isListening = false
        isFinalizing = true

        audioEngine?.stop()
        audioEngine?.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        // Intentionally do NOT call recognitionTask?.cancel() here. The
        // recognizer needs time to process any audio still in its internal
        // buffer; cancelling discards it.
    }

    /// Stop capturing and wait (bounded) for the recognizer to drain its
    /// buffered audio so the tail of the utterance isn't truncated. Returns
    /// the final transcript — empty if nothing was captured.
    func finishListening() async -> String {
        stopListening()
        for _ in 0..<15 {
            if !isFinalizing { break }
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        return transcript
    }

    /// Unconditional teardown for view dismissal. Unlike `stopListening()`,
    /// this also fires while a previous stop is still finalizing — the
    /// audio session must ALWAYS be released when the owning view goes
    /// away, or the record session stays active (mic indicator lit, other
    /// audio ducked) until the OS recognizer times out on its own.
    func cancelListening() {
        isListening = false
        isFinalizing = false
        forceCleanup()
    }

    /// Hard teardown. Called from the recognition task callback once drain
    /// completes (or it errors), from `startListening()` if a new session
    /// starts before the previous one finished, and from `cancelListening()`.
    private func forceCleanup() {
        // Reaching here while still marked listening means the recognizer
        // died on us mid-session (error or duration limit) — the user never
        // asked it to stop. Flag it so views can rescue the transcript.
        endedUnexpectedly = isListening

        audioEngine?.stop()
        audioEngine?.inputNode.removeTap(onBus: 0)
        recognitionTask?.cancel()

        audioEngine = nil
        recognitionRequest = nil
        recognitionTask = nil

        isListening = false
        isFinalizing = false
        AudioSessionService.shared.deactivate()
    }
}
