import SwiftUI

/// A single labeled text field with a voice / text mode toggle. Mirrors the
/// conversation screen's input layout — text mode shows a `TextEditor`,
/// voice mode shows a mic button with live transcription. Used for each of
/// the five commitment boxes on the alarm edit screen.
///
/// Each instance owns its own `SpeechRecognitionService` so multiple boxes
/// can be edited independently without their recording state stomping on
/// each other.
struct LCommitmentField: View {
    let sectionNumber: String      // e.g. "05"
    let title: String              // e.g. "Desired behavior"
    let placeholder: String
    var required: Bool = false
    @Binding var text: String

    @State private var mode: Mode = .text
    @State private var speech = SpeechRecognitionService()
    @State private var startedRecordingText: String = ""

    enum Mode { case text, voice }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            switch mode {
            case .text:  textInput
            case .voice: voiceInput
            }
        }
        .padding(.horizontal, L.Space.pageH)
        .padding(.vertical, 14)
        .overlay(alignment: .bottom) { L.Palette.hair.frame(height: 1) }
        .onDisappear {
            // Unconditional teardown — releases the audio session even if a
            // stop was still finalizing when the view went away.
            speech.cancelListening()
        }
        .onChange(of: speech.isListening) { wasListening, isListening in
            // Recognizer died mid-listen (error or OS duration limit).
            // Commit what was captured instead of dropping it.
            if wasListening, !isListening, speech.endedUnexpectedly,
               !speech.transcript.isEmpty {
                text = joined(startedRecordingText, speech.transcript)
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            HStack(spacing: 0) {
                Text("§ \(sectionNumber) · \(title) ").kicker(L.Palette.fg)
                if required {
                    Text("· required").kicker(L.Palette.muted)
                }
            }
            Spacer(minLength: 6)
            modeToggle
        }
    }

    private var modeToggle: some View {
        HStack(spacing: 0) {
            modeButton(.text, label: "txt")
            modeButton(.voice, label: "voice")
        }
    }

    private func modeButton(_ m: Mode, label: String) -> some View {
        let on = mode == m
        return Button {
            if mode == .voice && m == .text && speech.isListening {
                commitVoiceTranscript()
            }
            mode = m
        } label: {
            Text(label)
                .font(L.Mono.font(9.5))
                .tracking(0.4)
                .textCase(.uppercase)
                .foregroundStyle(on ? L.Palette.fg : L.Palette.dim)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(on ? L.Palette.bg : Color.clear)
                .overlay(Rectangle().stroke(on ? L.Palette.fg : L.Palette.hair2, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Text mode

    private var textInput: some View {
        ZStack(alignment: .topLeading) {
            if text.isEmpty {
                Text(placeholder)
                    .font(L.Mono.font(13))
                    .foregroundStyle(L.Palette.dim)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .allowsHitTesting(false)
            }
            TextEditor(text: $text)
                .font(L.Mono.font(13))
                .foregroundStyle(L.Palette.fg)
                .scrollContentBackground(.hidden)
                .background(L.Palette.bg)
                .lineSpacing(4)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .frame(minHeight: 90)
                .overlay(Rectangle().stroke(L.Palette.hair2, lineWidth: 1))
        }
    }

    // MARK: - Voice mode

    private var voiceInput: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 14) {
                Button {
                    voiceMicTap()
                } label: {
                    ZStack {
                        Circle()
                            .fill(L.Palette.fg)
                        L.Mic(size: 18, color: L.Palette.bg)
                    }
                    .frame(width: 48, height: 48)
                }
                .buttonStyle(.plain)

                VStack(alignment: .leading, spacing: 3) {
                    if speech.isListening {
                        HStack(spacing: 6) {
                            L.Dot(size: 5, color: L.Palette.fg)
                            Text("listening · tap to stop").kicker(L.Palette.fg)
                        }
                    } else if speech.isFinalizing {
                        Text("finalizing…").kicker(L.Palette.muted)
                    } else {
                        Text("tap mic to record").kicker()
                    }
                    Text("appends to text below").kicker(L.Palette.dim)
                }

                Spacer()
            }

            // Show the current captured text below the mic so the user can
            // see what's been recorded. Read-only here — to edit, switch to
            // the text mode.
            if text.isEmpty {
                Text(placeholder)
                    .font(L.Mono.font(13))
                    .foregroundStyle(L.Palette.dim)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .frame(maxWidth: .infinity, minHeight: 60, alignment: .topLeading)
                    .overlay(Rectangle().stroke(L.Palette.hair2, lineWidth: 1))
            } else {
                Text(speech.isListening && !speech.transcript.isEmpty
                     ? joined(text, speech.transcript)
                     : text)
                    .font(L.Mono.font(13))
                    .foregroundStyle(L.Palette.fg)
                    .lineSpacing(4)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .frame(maxWidth: .infinity, minHeight: 60, alignment: .topLeading)
                    .overlay(Rectangle().stroke(L.Palette.hair2, lineWidth: 1))
            }
        }
    }

    private func voiceMicTap() {
        if speech.isListening {
            commitVoiceTranscript()
        } else {
            startedRecordingText = text
            speech.prepare()
            speech.startListening()
        }
    }

    /// Stop the recognizer, wait for it to drain the buffered audio (so we
    /// keep the last word), then append the transcript to whatever was
    /// already in `text` when recording started.
    private func commitVoiceTranscript() {
        Task { @MainActor in
            let transcript = await speech.finishListening()
            if !transcript.isEmpty {
                text = joined(startedRecordingText, transcript)
            }
        }
    }

    private func joined(_ existing: String, _ addition: String) -> String {
        if existing.isEmpty { return addition }
        return existing + " " + addition
    }
}
