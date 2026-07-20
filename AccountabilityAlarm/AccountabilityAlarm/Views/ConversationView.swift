import SwiftUI
import SwiftData

struct ConversationView: View {
    let alarmId: UUID

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var appState

    @State private var vm = ConversationViewModel()
    @State private var speech = SpeechRecognitionService()
    @State private var tts = TextToSpeechService()
    // AlarmKit owns the ringing now — system UI plays alarm sound at full
    // volume when the alarm fires, then dismisses when the user taps
    // "Talk to Coach." The in-app conversation is intentionally silent;
    // the pre-emptive AlarmKit snooze is the persistence mechanism.

    @State private var mode: Mode = .voice
    @State private var elapsedSeconds: Int = 0

    @FocusState private var textInputFocused: Bool

    enum Mode { case voice, text }

    init(alarmId: UUID) {
        self.alarmId = alarmId
    }

    private var elapsedString: String {
        String(format: "%02d:%02d", elapsedSeconds / 60, elapsedSeconds % 60)
    }

    private var alarm: Alarm? {
        let id = alarmId
        let descriptor = FetchDescriptor<Alarm>(predicate: #Predicate { $0.id == id })
        return try? modelContext.fetch(descriptor).first
    }

    var body: some View {
        ZStack {
            L.Palette.bg.ignoresSafeArea()

            VStack(spacing: 0) {
                topBar
                if let alarm { alarmHeader(alarm) }

                messagesScroll
                bottomPanel
            }
        }
        .foregroundStyle(L.Palette.fg)
        .preferredColorScheme(.dark)
        .interactiveDismissDisabled(!vm.isCompleted)
        .onAppear {
            vm.setup(alarmId: alarmId, context: modelContext)
            Task {
                _ = await speech.requestPermission()
                // Pre-warm the audio session so the first mic tap captures
                // without the ~150ms activation delay that would otherwise
                // truncate the start of speech.
                speech.prepare()
            }
            startTimers()
        }
        .onDisappear {
            tts.stop()
            // Unconditional teardown — stopListening() no-ops while a prior
            // stop is finalizing, which left the record audio session live
            // after the view was gone.
            speech.cancelListening()
        }
        .onChange(of: vm.messages.count) { _, count in
            // count > seededMessageCount: never re-speak a message restored
            // from an earlier conversation in this chain.
            if count > vm.seededMessageCount,
               let last = vm.messages.last, last.role == .assistant, mode == .voice {
                tts.speak(last.content)
            }
        }
        .onChange(of: speech.isListening) { wasListening, isListening in
            // Recognizer died mid-listen (error or the OS duration limit)
            // while the user thought they were still recording. Send what
            // was captured instead of letting the next mic tap wipe it.
            if wasListening, !isListening, speech.endedUnexpectedly,
               !speech.transcript.isEmpty, !vm.isCompleted {
                vm.inputText = speech.transcript
                Task { @MainActor in
                    await vm.sendMessage(context: modelContext)
                }
            }
        }
        .onChange(of: vm.isCompleted) { _, done in
            // LLM-driven snooze ends the session with no user tap. Close the
            // cover (after letting the sign-off land) so a stale completed
            // conversation can't block the next re-ring from presenting.
            guard done, vm.autoDismissOnCompletion else { return }
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                appState.dismissAlarm()
                dismiss()
            }
        }
        .onChange(of: tts.isSpeaking) { _, isSpeaking in
            // When TTS finishes, re-prepare the recording session so the
            // next mic tap is hot. TTS's stop() deactivates the session;
            // without re-priming, the first tap eats activation latency.
            if !isSpeaking { speech.prepare() }
        }
    }

    // MARK: - Top bar

    private var topBar: some View {
        HStack {
            HStack(spacing: 5) {
                L.Dot(size: 5, color: L.Palette.fg)
                Text("ALARM FIRING · \(elapsedString)")
                    .kicker(L.Palette.muted)
            }
            Spacer()
        }
        .padding(.horizontal, L.Space.pageH)
        .padding(.vertical, 8)
        .overlay(alignment: .bottom) { L.Palette.hair.frame(height: 1) }
    }

    // MARK: - Alarm header

    private func alarmHeader(_ alarm: Alarm) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Now firing").kicker()
            Text("\(alarm.time12) \(alarm.period) · \(alarm.label)")
                .font(L.Mono.font(18, weight: .medium))
                .tracking(-0.3)
                .foregroundStyle(L.Palette.fg)
                .lineLimit(1)
                .truncationMode(.tail)
            Text("\u{201C}\(alarm.reasonShort)\u{201D}")
                .font(L.Mono.font(11))
                .foregroundStyle(L.Palette.muted)
                .lineSpacing(2)
                .padding(.leading, 10)
                .overlay(alignment: .leading) { L.Palette.hair2.frame(width: 1) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, L.Space.pageH)
        .padding(.vertical, 14)
        .overlay(alignment: .bottom) { L.Palette.hair.frame(height: 1) }
    }

    // MARK: - Messages

    private var messagesScroll: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(Array(vm.messages.enumerated()), id: \.element.id) { idx, msg in
                        LMessage(message: msg, index: idx + 1)
                            .id(msg.id)
                    }
                    if vm.isLoading {
                        HStack {
                            Text("// coach thinking…").kicker()
                            Spacer()
                        }
                        .padding(.horizontal, L.Space.pageH)
                        .padding(.vertical, 12)
                    }
                }
            }
            // Start pinned to the newest message — matters when the view
            // opens with restored history from earlier in the chain.
            .defaultScrollAnchor(.bottom)
            .onChange(of: vm.messages.count) { _, _ in
                if let last = vm.messages.last {
                    withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Bottom panel

    private var bottomPanel: some View {
        VStack(spacing: 0) {
            modeTabs
            if mode == .voice { voiceInput } else { textInput }
            outcomeButtons
        }
        .background(L.Palette.bg2)
        .overlay(alignment: .top) { L.Palette.hair2.frame(height: 1) }
    }

    private var outcomeButtons: some View {
        HStack(spacing: 6) {
            Button {
                vm.resolveSnooze(context: modelContext)
                appState.dismissAlarm()
                dismiss()
            } label: {
                Text("Snooze \(vm.snoozeButtonMinutes)m")
                    .font(L.Mono.font(10.5))
                    .tracking(0.6)
                    .textCase(.uppercase)
                    .foregroundStyle(vm.isCompleted ? L.Palette.dim : L.Palette.muted)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .overlay(Rectangle().stroke(L.Palette.hair2, lineWidth: 1))
            }
            .buttonStyle(.plain)
            // A resolved chain must not be re-armed from the still-open view.
            .disabled(vm.isCompleted)

            Button {
                vm.resolveAction(context: modelContext)
                appState.dismissAlarm()
                dismiss()
            } label: {
                Text("Doing It ↑")
                    .font(L.Mono.font(10.5, weight: .semibold))
                    .tracking(0.6)
                    .textCase(.uppercase)
                    .foregroundStyle(vm.actionAuthorized ? L.Palette.bg : L.Palette.dim)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(vm.actionAuthorized ? L.Palette.fg : L.Palette.bg3)
                    .overlay(
                        Rectangle().stroke(
                            vm.actionAuthorized ? Color.clear : L.Palette.hair2,
                            lineWidth: 1
                        )
                    )
            }
            .buttonStyle(.plain)
            .disabled(!vm.actionAuthorized)
            .animation(.easeInOut(duration: 0.15), value: vm.actionAuthorized)
        }
        .padding(.horizontal, L.Space.pageH)
        .padding(.bottom, 26)
        .padding(.top, 4)
    }

    private var modeTabs: some View {
        HStack(spacing: 0) {
            modeTab(.voice, label: "● voice")
            modeTab(.text, label: "text")
        }
        .overlay(alignment: .bottom) { L.Palette.hair.frame(height: 1) }
    }

    private func modeTab(_ m: Mode, label: String) -> some View {
        let on = mode == m
        return Button {
            mode = m
            if m == .text { textInputFocused = true } else { speech.stopListening() }
        } label: {
            Text(label)
                .font(L.Mono.font(11))
                .tracking(0.6)
                .textCase(.uppercase)
                .foregroundStyle(on ? L.Palette.fg : L.Palette.dim)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .overlay(alignment: .bottom) {
                    Rectangle().fill(on ? L.Palette.fg : Color.clear).frame(height: 2)
                }
        }
        .buttonStyle(.plain)
    }

    private var voiceInput: some View {
        HStack(spacing: 16) {
            Button {
                voiceMicTap()
            } label: {
                ZStack {
                    Circle()
                        .fill(vm.isCompleted
                              ? L.Palette.bg3
                              : (speech.isListening ? L.Palette.badRed : L.Palette.fg))
                        .opacity(vm.isCompleted ? 0.5 : 1.0)
                    L.Mic(size: 22, color: L.Palette.bg)
                }
                .frame(width: 56, height: 56)
                .animation(.easeInOut(duration: 0.15), value: speech.isListening)
            }
            .buttonStyle(.plain)
            .disabled(vm.isCompleted)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 2) {
                    ForEach(0..<28, id: \.self) { i in
                        let seed = abs(sin(Double(i) * 2.1))
                        Rectangle()
                            .fill(L.Palette.fg)
                            .opacity(vm.isCompleted ? 0.15 : 0.25 + seed * 0.6)
                            .frame(maxWidth: .infinity)
                            .frame(height: 3 + CGFloat(seed) * 18)
                    }
                }
                .frame(height: 24)

                if speech.isListening {
                    Text("listening · tap to send")
                        .font(L.Mono.font(10))
                        .tracking(0.4)
                        .textCase(.uppercase)
                        .foregroundStyle(L.Palette.fg)
                } else {
                    Text(vm.isCompleted ? "conversation closed" : "tap mic to speak")
                        .font(L.Mono.font(10))
                        .tracking(0.4)
                        .textCase(.uppercase)
                        .foregroundStyle(L.Palette.dim)
                }
            }
        }
        .padding(.horizontal, L.Space.pageH)
        .padding(.vertical, 18)
    }

    private var textInput: some View {
        HStack(spacing: 8) {
            TextField("type a reply…", text: $vm.inputText)
                .font(L.Mono.font(13))
                .foregroundStyle(L.Palette.fg)
                .textFieldStyle(.plain)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(L.Palette.bg)
                .overlay(Rectangle().stroke(L.Palette.hair2, lineWidth: 1))
                .focused($textInputFocused)
                .onSubmit { sendText() }

            Button {
                sendText()
            } label: {
                Text("send →")
                    .font(L.Mono.font(11, weight: .semibold))
                    .tracking(0.6)
                    .textCase(.uppercase)
                    .foregroundStyle(canSend ? L.Palette.bg : L.Palette.dim)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(canSend ? L.Palette.fg : L.Palette.bg3)
            }
            .buttonStyle(.plain)
            .disabled(!canSend)
        }
        .padding(.horizontal, L.Space.pageH)
        .padding(.vertical, 12)
    }


    // MARK: - Actions

    private var canSend: Bool {
        !vm.inputText.trimmingCharacters(in: .whitespaces).isEmpty && !vm.isLoading && !vm.isCompleted
    }

    private func sendText() {
        guard canSend else { return }
        Task { @MainActor in
            await vm.sendMessage(context: modelContext)
        }
    }

    private func voiceMicTap() {
        if speech.isListening {
            Task { @MainActor in
                let transcript = await speech.finishListening()
                if !transcript.isEmpty {
                    vm.inputText = transcript
                    await vm.sendMessage(context: modelContext)
                }
            }
        } else {
            tts.stop()
            speech.startListening()
        }
    }


    private func startTimers() {
        elapsedSeconds = 3
        Task { @MainActor in
            while !Task.isCancelled, !vm.isCompleted {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                elapsedSeconds += 1
            }
        }
    }
}

// MARK: - Single message row

private struct LMessage: View {
    let message: ConversationMessage
    let index: Int

    private var isAI: Bool { message.role == .assistant }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(isAI ? "> coach" : "you")
                    .font(L.Mono.font(9.5))
                    .tracking(0.4)
                    .textCase(.uppercase)
                    .foregroundStyle(isAI ? L.Palette.fg : L.Palette.muted)
                    .lineLimit(1)
                Spacer()
                Text(String(format: "%02d", index))
                    .font(L.Mono.font(9.5))
                    .tracking(0.4)
                    .foregroundStyle(L.Palette.dim)
            }

            Text(message.content)
                .font(L.Mono.font(14))
                .lineSpacing(4)
                .foregroundStyle(isAI ? L.Palette.fg : L.Palette.muted)
                .padding(.leading, isAI ? 0 : 24)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, L.Space.pageH)
        .padding(.vertical, 10)
        .overlay(alignment: .bottom) { L.Palette.hair.frame(height: 1) }
    }
}
