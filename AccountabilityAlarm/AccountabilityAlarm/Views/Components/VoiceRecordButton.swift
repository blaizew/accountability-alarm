import SwiftUI

struct VoiceRecordButton: View {
    @State private var recorder = VoiceRecordingService()
    let onRecordingComplete: (URL) -> Void

    var body: some View {
        VStack(spacing: 8) {
            Button {
                if recorder.isRecording {
                    if let url = recorder.stopRecording() {
                        onRecordingComplete(url)
                    }
                } else {
                    recorder.startRecording()
                }
            } label: {
                Label(
                    recorder.isRecording ? "Stop Recording" : "Record Reason",
                    systemImage: recorder.isRecording ? "stop.circle.fill" : "mic.circle.fill"
                )
                .font(.headline)
                .foregroundStyle(recorder.isRecording ? L.Palette.badRed : L.Palette.accent)
            }

            if recorder.isRecording {
                Text("Recording...")
                    .font(.caption)
                    .foregroundStyle(L.Palette.badRed)
            }

            if let error = recorder.error {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(L.Palette.badRed)
            }
        }
    }
}
