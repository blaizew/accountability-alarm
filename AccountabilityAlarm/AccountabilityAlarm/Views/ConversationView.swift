import SwiftUI
import SwiftData

struct ConversationView: View {
    let alarmId: UUID
    let initialRing: EscalationRing

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var appState

    @State private var vm: ConversationViewModel
    @State private var speech = SpeechRecognitionService()
    @State private var tts = TextToSpeechService()
    // AlarmKit owns the ringing now — system UI plays alarm sound at full
    // volume when the alarm fires, then dismisses when the user taps
    // "Talk to past-self." The in-app conversation is intentionally silent;
    // the pre-emptive AlarmKit snooze is the persistence mechanism.

    @State private var mode: Mode = .voice
    @State private var elapsedSeconds: Int = 0

    @FocusState private var textInputFocused: Bool

    enum Mode { case voice, text }

    init(alarmId: UUID, initialRing: EscalationRing) {
        self.alarmId = alarmId
        self.initialRing = initialRing
        self._vm = State(initialValue: ConversationViewModel(initialRing: initialRing))
    }

    private var ring: EscalationRing { vm.currentRing }
    private var ringColor: Color { L.ringColor(ring) }
    private var ringIndex: Int { ring.rawValue - 1 } // 0..3
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
            backgroundWash.ignoresSafeArea()

            VStack(spacing: 0) {
                topBar
                ringMeter
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
            Task { _ = await speech.requestPermission() }
            startTimers()
        }
        .onDisappear {
            tts.stop()
            speech.stopListening()
        }
        .onChange(of: vm.messages.count) { _, _ in
            if let last = vm.messages.last, last.role == .assistant, mode == .voice {
                tts.speak(last.content)
            }
        }
        .animation(.easeOut(duration: 0.3), value: ring)
    }

    // MARK: - Background

    private var backgroundWash: some View {
        let washColor: Color = {
            switch ring {
            case .preview: return L.Palette.ringPreview.opacity(0.22)
            case .mirror:  return L.Palette.ringMirror.opacity(0.16)
            case .math:    return L.Palette.ringMath.opacity(0.10)
            case .nudge:   return .clear
            }
        }()
        return ZStack {
            L.Palette.bg
            RadialGradient(
                colors: [washColor, .clear],
                center: .top,
                startRadius: 0,
                endRadius: 600
            )
        }
    }

    // MARK: - Top bar

    private var topBar: some View {
        let leftColor = ring == .preview ? L.Palette.ringPreview : L.Palette.muted
        let dotColor  = ring == .preview ? L.Palette.ringPreview : L.Palette.fg
        let offsetMin = ring.minutesAfterAlarm
        return HStack {
            HStack(spacing: 5) {
                L.Dot(size: 5, color: dotColor)
                Text("ALARM FIRING · +\(offsetMin)m · \(elapsedString)")
                    .kicker(leftColor)
            }
            Spacer()
        }
        .padding(.horizontal, L.Space.pageH)
        .padding(.vertical, 8)
        .overlay(alignment: .bottom) { L.Palette.hair.frame(height: 1) }
    }

    // MARK: - Ring meter

    private var ringMeter: some View {
        VStack(spacing: 8) {
            HStack(spacing: 4) {
                ForEach(EscalationRing.allCases, id: \.self) { r in
                    let reached = r.rawValue <= ring.rawValue
                    let current = r == ring
                    Rectangle()
                        .fill(reached ? L.ringColor(r) : L.Palette.hair2)
                        .frame(height: current ? 4 : 2)
                        .frame(maxWidth: .infinity)
                        .animation(.easeOut(duration: 0.3), value: ring)
                }
            }
            HStack {
                HStack(spacing: 6) {
                    Text("Ring \(ring.rawValue)/4").kicker(L.Palette.fg)
                    Text("· \(ring.label)").kicker(ringColor)
                }
                Spacer()
                Text(ring.ringDescription).kicker()
            }
        }
        .padding(.horizontal, L.Space.pageH)
        .padding(.top, 10)
        .padding(.bottom, 12)
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
                        LMessage(message: msg, index: idx + 1, ring: ring)
                            .id(msg.id)
                    }
                    if vm.isLoading {
                        HStack {
                            Text("// past-self thinking…").kicker()
                            Spacer()
                        }
                        .padding(.horizontal, L.Space.pageH)
                        .padding(.vertical, 12)
                    }
                }
            }
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
                    .foregroundStyle(L.Palette.muted)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .overlay(Rectangle().stroke(L.Palette.hair2, lineWidth: 1))
            }
            .buttonStyle(.plain)

            Button {
                vm.resolveComply(context: modelContext)
                appState.dismissAlarm()
                dismiss()
            } label: {
                Text("Comply ↑")
                    .font(L.Mono.font(10.5, weight: .semibold))
                    .tracking(0.6)
                    .textCase(.uppercase)
                    .foregroundStyle(vm.complyAuthorized ? L.Palette.bg : L.Palette.dim)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(vm.complyAuthorized ? L.Palette.fg : L.Palette.bg3)
                    .overlay(
                        Rectangle().stroke(
                            vm.complyAuthorized ? Color.clear : L.Palette.hair2,
                            lineWidth: 1
                        )
                    )
            }
            .buttonStyle(.plain)
            .disabled(!vm.complyAuthorized)
            .animation(.easeInOut(duration: 0.15), value: vm.complyAuthorized)
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
                        .fill(vm.isCompleted ? L.Palette.bg3 : ringColor)
                        .opacity(vm.isCompleted ? 0.5 : 1.0)
                    L.Mic(size: 22, color: L.Palette.bg)
                }
                .frame(width: 56, height: 56)
            }
            .buttonStyle(.plain)
            .disabled(vm.isCompleted)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 2) {
                    ForEach(0..<28, id: \.self) { i in
                        let seed = abs(sin(Double(i) * 2.1 + Double(ring.rawValue)))
                        Rectangle()
                            .fill(ringColor)
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
        !vm.inputText.trimmingCharacters(in: .whitespaces).isEmpty && !vm.isLoading
    }

    private func sendText() {
        guard canSend else { return }
        Task { @MainActor in
            await vm.sendMessage(context: modelContext)
        }
    }

    private func voiceMicTap() {
        if speech.isListening {
            speech.stopListening()
            if !speech.transcript.isEmpty {
                vm.inputText = speech.transcript
                Task { @MainActor in
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
    let ring: EscalationRing

    private var isAI: Bool { message.role == .assistant }

    private var aiColor: Color { L.ringColor(ring) }

    private var aiWeight: Font.Weight {
        switch ring {
        case .nudge:   return .regular
        case .math:    return .medium
        case .mirror:  return .semibold
        case .preview: return .bold
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(isAI ? "> past-self · \(ring.label.lowercased())" : "you")
                    .font(L.Mono.font(9.5))
                    .tracking(0.4)
                    .textCase(.uppercase)
                    .foregroundStyle(isAI ? aiColor : L.Palette.muted)
                    .lineLimit(1)
                Spacer()
                Text(String(format: "%02d", index))
                    .font(L.Mono.font(9.5))
                    .tracking(0.4)
                    .foregroundStyle(L.Palette.dim)
            }

            Text(message.content)
                .font(L.Mono.font(14, weight: isAI ? aiWeight : .regular))
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
