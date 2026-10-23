import SwiftUI
import SwiftData

struct ConversationView: View {
    let alarmId: UUID
    let isRehearsal: Bool

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var appState

    @State private var vm = ConversationViewModel()
    @State private var speech = SpeechRecognitionService()
    // AlarmKit owns the ringing now — system UI plays alarm sound at full
    // volume when the alarm fires, then dismisses when the user taps
    // "Talk to Coach." The in-app conversation is intentionally silent;
    // the pre-emptive AlarmKit snooze is the persistence mechanism.

    @State private var mode: Mode = .voice
    @State private var elapsedSeconds: Int = 0
    @State private var timerTask: Task<Void, Never>?
    @State private var rehearsalAlarmSnapshot: Alarm?
    @State private var pulse = false

    @State private var bumpChoice: BumpChoice?
    @AppStorage(Constants.bumpHapticKey) private var hapticRaw = BumpHaptic.defaultValue.rawValue
    @AppStorage(Constants.bumpRemovalKey) private var bumpRemoval = "random"
    @AppStorage(Constants.bumpConfettiPatternKey) private var bumpPattern = "random"
    @AppStorage(Constants.bumpConfettiShapesKey) private var bumpShapes = "random"
    @AppStorage(Constants.bumpFistWidthKey) private var fistWidth = 0.65
    @AppStorage(Constants.bumpLastRemovalKey) private var lastRemovalRaw = ""

    @FocusState private var textInputFocused: Bool

    enum Mode { case voice, text }

    init(alarmId: UUID, isRehearsal: Bool = false) {
        self.alarmId = alarmId
        self.isRehearsal = isRehearsal
    }

    private var elapsedString: String {
        String(format: "%02d:%02d", elapsedSeconds / 60, elapsedSeconds % 60)
    }

    /// One value drives both the stage/chat branch and its cross-fade.
    private var showStage: Bool { vm.actionAuthorized && bumpChoice != nil }

    private var alarm: Alarm? {
        if isRehearsal { return rehearsalAlarmSnapshot ?? appState.rehearsalAlarm }
        let id = alarmId
        let descriptor = FetchDescriptor<Alarm>(predicate: #Predicate { $0.id == id })
        return try? modelContext.fetch(descriptor).first
    }

    var body: some View {
        ZStack {
            L.Palette.bg.ignoresSafeArea()

            GeometryReader { geo in
                VStack(spacing: 0) {
                    topBar
                    if let alarm { alarmHeader(alarm) }

                    if showStage, let choice = bumpChoice {
                        bumpStage(choice)
                            .transition(.opacity)
                    } else {
                        messagesScroll(containerHeight: geo.size.height)
                            .transition(.opacity)
                        bottomPanel
                            .transition(.opacity)
                    }
                }
                .frame(width: geo.size.width, height: geo.size.height)
                .animation(.easeInOut(duration: 0.3), value: showStage)
                .animation(.easeInOut(duration: 0.2), value: mode)
            }
        }
        .foregroundStyle(L.Palette.fg)
        .preferredColorScheme(.dark)
        .interactiveDismissDisabled(!vm.isCompleted)
        .onAppear {
            if isRehearsal {
                if let rehearsalAlarm = appState.rehearsalAlarm {
                    rehearsalAlarmSnapshot = rehearsalAlarm
                    vm.setup(alarm: rehearsalAlarm, isRehearsal: true, context: modelContext)
                } else {
                    appState.dismissAlarm()
                    dismiss()
                    return
                }
            } else {
                vm.setup(alarmId: alarmId, context: modelContext)
            }
            Task {
                _ = await speech.requestPermission()
                // Pre-warm the audio session so the first mic tap captures
                // without the ~150ms activation delay that would otherwise
                // truncate the start of speech.
                speech.prepare()
                HapticService.shared.prepare()
            }
            startTimers()
        }
        .onDisappear {
            timerTask?.cancel()
            // Unconditional teardown — stopListening() no-ops while a prior
            // stop is finalizing, which left the record audio session live
            // after the view was gone.
            speech.cancelListening()
        }
        .onChange(of: vm.actionAuthorized) { _, authorized in
            // Pick the bump's look once per authorization, so the stage
            // never re-rolls on a redraw.
            guard authorized else { return }
            // The stage replaces the input row; a live listen must not
            // auto-send a hidden turn after "Do not reply."
            speech.cancelListening()
            textInputFocused = false
            guard bumpChoice == nil else { return }
            var r = BumpRandomizer()
            bumpChoice = r.choose(removalOverride: FistRemoval(rawValue: bumpRemoval),
                                  patternOverride: ConfettiPattern(rawValue: bumpPattern),
                                  shapesOverride: ConfettiShapes(rawValue: bumpShapes),
                                  lastRemoval: FistRemoval(rawValue: lastRemovalRaw))
        }
        .onChange(of: speech.isListening) { wasListening, isListening in
            // Recognizer died mid-listen (error or the OS duration limit)
            // while the user thought they were still recording. Send what
            // was captured instead of letting the next mic tap wipe it.
            if wasListening, !isListening, speech.endedUnexpectedly,
               !speech.transcript.isEmpty, !vm.isCompleted, !vm.actionAuthorized {
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
                if appState.activeSession?.alarmId == alarmId { appState.dismissAlarm() }
                dismiss()
            }
        }
    }

    // MARK: - Top bar

    private var topBar: some View {
        HStack {
            HStack(spacing: 5) {
                L.Dot(size: 5, color: L.Palette.fg)
                Text("\(isRehearsal ? "REHEARSAL" : "ALARM FIRING") · \(elapsedString)")
                    .kicker(L.Palette.muted)
            }
            Spacer()
            if isRehearsal {
                Button {
                    speech.cancelListening()
                    appState.dismissAlarm()
                    dismiss()
                } label: {
                    Text("END").kicker(L.Palette.muted)
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, L.Space.pageH)
        .padding(.vertical, isRehearsal ? 0 : 8)
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

    @ViewBuilder
    private func messagesScroll(containerHeight: CGFloat) -> some View {
        if mode == .voice {
            messagesScrollContent
                .frame(maxWidth: .infinity)
                .frame(height: containerHeight * 0.5)
        } else {
            messagesScrollContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var messagesScrollContent: some View {
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
    }

    // MARK: - Bottom panel

    private var bottomPanel: some View {
        VStack(spacing: 0) {
            modeTabs
            if mode == .voice {
                voiceInput
            } else {
                textInput
            }
            outcomeButtons
        }
        // Voice fills the space under the half-height chat; text stays natural
        // height so the chat keeps the room.
        .frame(maxWidth: .infinity, maxHeight: mode == .voice ? .infinity : nil)
        .background(L.Palette.bg2)
        .overlay(alignment: .top) { L.Palette.hair2.frame(height: 1) }
    }

    private func bumpStage(_ choice: BumpChoice) -> some View {
        BumpStageView(
            sendOff: vm.sendOff,
            fistWidthFraction: fistWidth,
            haptic: BumpHaptic(rawValue: hapticRaw) ?? .defaultValue,
            choice: choice,
            snoozeLabel: "Snooze \(vm.snoozeButtonMinutes)m",
            isDemo: false,
            onBump: {
                vm.resolveAction(context: modelContext)
                lastRemovalRaw = choice.removal.rawValue
            },
            onFinished: {
                if appState.activeSession?.alarmId == alarmId { appState.dismissAlarm() }
                dismiss()
            },
            onSnooze: {
                vm.resolveSnooze(context: modelContext)
                appState.dismissAlarm()
                dismiss()
            }
        )
    }

    private var outcomeButtons: some View {
        HStack(spacing: 6) {
            Button {
                vm.resolveSnooze(context: modelContext)
                appState.dismissAlarm()
                dismiss()
            } label: {
                Text("Snooze \(vm.snoozeButtonMinutes)m")
                    .font(L.Mono.font(14, weight: .semibold))
                    .tracking(0.8)
                    .textCase(.uppercase)
                    .foregroundStyle(vm.isCompleted ? L.Palette.dim : L.Palette.badRed)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 18)
                    .background(vm.isCompleted ? Color.clear : L.Palette.badRed.opacity(0.12))
                    .overlay(Rectangle().stroke(vm.isCompleted ? L.Palette.hair2 : L.Palette.badRed, lineWidth: 1.5))
            }
            .buttonStyle(.plain)
            // A resolved chain must not be re-armed from the still-open view.
            .disabled(vm.isCompleted)
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
        VStack(spacing: 18) {
            Spacer(minLength: 0)
            micButton
            hintLabel
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, L.Space.pageH)
    }

    private var micButton: some View {
        Button {
            voiceMicTap()
        } label: {
            ZStack {
                if speech.isListening {
                    Circle()
                        .stroke(L.Palette.badRed, lineWidth: 2)
                        .scaleEffect(pulse ? 1.35 : 1.0)
                        .opacity(pulse ? 0 : 0.7)
                        .animation(pulse ? .easeOut(duration: 1.1).repeatForever(autoreverses: false) : .default,
                                   value: pulse)
                }
                Circle()
                    .fill(vm.isCompleted
                          ? L.Palette.bg3
                          : (speech.isListening ? L.Palette.badRed : L.Palette.fg))
                    .opacity(vm.isCompleted ? 0.5 : 1.0)
                    .animation(.easeInOut(duration: 0.15), value: speech.isListening)
                L.Mic(size: 48, color: L.Palette.bg)
            }
            .frame(width: 128, height: 128)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(vm.isCompleted)
        .accessibilityLabel(speech.isListening ? "Stop and send" : "Speak")
        .onChange(of: speech.isListening) { _, isListening in
            pulse = isListening
        }
    }

    private var hintLabel: some View {
        Group {
            if speech.isListening {
                Text("listening · tap to send")
                    .foregroundStyle(L.Palette.badRed)
            } else {
                Text(vm.isCompleted ? "conversation closed" : "tap mic to speak")
                    .foregroundStyle(L.Palette.dim)
            }
        }
        .font(L.Mono.font(10))
        .tracking(0.4)
        .textCase(.uppercase)
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
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
        HapticService.shared.play(speech.isListening ? .thudClick : .click)
        if speech.isListening {
            Task { @MainActor in
                let transcript = await speech.finishListening()
                if !transcript.isEmpty {
                    vm.inputText = transcript
                    await vm.sendMessage(context: modelContext)
                }
            }
        } else {
            speech.startListening()
        }
    }


    private func startTimers() {
        elapsedSeconds = 3
        timerTask?.cancel()
        timerTask = Task { @MainActor in
            while !Task.isCancelled, !vm.isCompleted {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                elapsedSeconds += 1
            }
        }
    }
}

// MARK: - Single message row

struct LMessage: View {
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
