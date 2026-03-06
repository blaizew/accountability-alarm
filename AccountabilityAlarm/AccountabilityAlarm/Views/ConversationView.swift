import SwiftUI
import SwiftData

struct ConversationView: View {
    let alarmId: UUID
    let initialRing: EscalationRing

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var appState
    @State private var viewModel: ConversationViewModel
    @State private var speechService = SpeechRecognitionService()
    @State private var ttsService = TextToSpeechService()
    @State private var alarmSound = AlarmSoundService()
    @State private var voiceMode = false
    @FocusState private var isInputFocused: Bool

    init(alarmId: UUID, initialRing: EscalationRing) {
        self.alarmId = alarmId
        self.initialRing = initialRing
        self._viewModel = State(initialValue: ConversationViewModel(initialRing: initialRing))
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Ring indicator
                RingIndicator(currentRing: viewModel.currentRing)
                    .padding(.vertical, 8)

                Divider()

                // Messages
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            ForEach(viewModel.messages) { message in
                                MessageBubble(message: message)
                                    .id(message.id)
                            }

                            if viewModel.isLoading {
                                HStack {
                                    ProgressView()
                                        .padding(.horizontal, 14)
                                        .padding(.vertical, 10)
                                        .background(Color(.systemGray5))
                                        .clipShape(RoundedRectangle(cornerRadius: 16))
                                    Spacer(minLength: 60)
                                }
                            }
                        }
                        .padding()
                    }
                    .onChange(of: viewModel.messages.count) {
                        if let last = viewModel.messages.last {
                            withAnimation {
                                proxy.scrollTo(last.id, anchor: .bottom)
                            }
                        }
                        // Auto-speak new AI messages in voice mode
                        if voiceMode, let last = viewModel.messages.last, last.role == .assistant {
                            ttsService.speak(last.content)
                        }
                    }
                }

                Divider()

                // Input area
                if viewModel.isCompleted {
                    Button {
                        alarmSound.stopAlarm()
                        ttsService.stop()
                        speechService.stopListening()
                        appState.dismissAlarm()
                        dismiss()
                    } label: {
                        Text("Done")
                            .frame(maxWidth: .infinity)
                            .padding()
                    }
                    .buttonStyle(.borderedProminent)
                    .padding()
                } else {
                    VStack(spacing: 8) {
                        // Voice mode toggle
                        HStack {
                            Spacer()
                            Button {
                                voiceMode.toggle()
                                if !voiceMode {
                                    speechService.stopListening()
                                    ttsService.stop()
                                }
                            } label: {
                                Label(
                                    voiceMode ? "Text mode" : "Voice mode",
                                    systemImage: voiceMode ? "keyboard" : "mic"
                                )
                                .font(.caption)
                            }
                        }
                        .padding(.horizontal)
                        .padding(.top, 4)

                        if voiceMode {
                            // Voice input
                            VStack(spacing: 8) {
                                if !speechService.transcript.isEmpty {
                                    Text(speechService.transcript)
                                        .font(.body)
                                        .padding(.horizontal)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }

                                HStack(spacing: 16) {
                                    Button {
                                        if speechService.isListening {
                                            speechService.stopListening()
                                            if !speechService.transcript.isEmpty {
                                                viewModel.inputText = speechService.transcript
                                                Task {
                                                    await viewModel.sendMessage(context: modelContext)
                                                }
                                            }
                                        } else {
                                            ttsService.stop()
                                            speechService.startListening()
                                        }
                                    } label: {
                                        Image(systemName: speechService.isListening ? "mic.fill" : "mic")
                                            .font(.title)
                                            .foregroundStyle(speechService.isListening ? .red : .accentColor)
                                            .frame(width: 60, height: 60)
                                            .background(
                                                Circle()
                                                    .fill(Color(.systemGray6))
                                            )
                                    }
                                    .disabled(viewModel.isLoading)
                                }
                            }
                            .padding(.bottom)
                        } else {
                            // Text input
                            HStack(spacing: 12) {
                                TextField("Reply...", text: $viewModel.inputText, axis: .vertical)
                                    .textFieldStyle(.roundedBorder)
                                    .lineLimit(1...3)
                                    .focused($isInputFocused)

                                Button {
                                    Task {
                                        await viewModel.sendMessage(context: modelContext)
                                    }
                                } label: {
                                    Image(systemName: "arrow.up.circle.fill")
                                        .font(.title2)
                                }
                                .disabled(viewModel.inputText.trimmingCharacters(in: .whitespaces).isEmpty || viewModel.isLoading)
                            }
                            .padding()
                        }
                    }
                }
            }
            .navigationTitle("Alarm")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Dismiss") {
                        ttsService.stop()
                        speechService.stopListening()
                        appState.dismissAlarm()
                        dismiss()
                    }
                }
            }
            .onAppear {
                viewModel.setup(alarmId: alarmId, context: modelContext)
                Task {
                    _ = await speechService.requestPermission()
                }
            }
            .onDisappear {
                alarmSound.stopAlarm()
            }
            .onChange(of: viewModel.alarmSoundState) { _, newState in
                switch newState {
                case .playing:
                    alarmSound.startAlarm()
                case .paused, .stopped:
                    alarmSound.stopAlarm()
                }
            }
            .interactiveDismissDisabled(!viewModel.isCompleted)
        }
    }
}
