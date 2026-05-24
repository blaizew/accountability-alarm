import SwiftUI
import SwiftData

struct AlarmEditView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var vm = AlarmEditViewModel()
    @State private var recorder = VoiceRecordingService()
    @State private var initialSnapshot: String = ""
    var alarm: Alarm?

    private var isNew: Bool { alarm == nil }

    var body: some View {
        VStack(spacing: 0) {
            LTopBar(
                left: isNew ? "ALARMS / NEW" : "ALARMS / EDIT",
                right: isDirty ? "UNSAVED ●" : "",
                leftColor: L.Palette.dim,
                rightColor: L.Palette.muted
            )

            actionBar

            ScrollView {
                VStack(spacing: 0) {
                    timeSection
                    repeatSection
                    reasonSection
                    labelSection
                    escalationSection
                    if !isNew { deleteSection }
                    Color.clear.frame(height: 40)
                }
            }

            // home-indicator safe area gutter
            L.Palette.bg.frame(height: 12)
        }
        .background(L.Palette.bg.ignoresSafeArea())
        .foregroundStyle(L.Palette.fg)
        .preferredColorScheme(.dark)
        .onAppear {
            if let alarm { vm.loadAlarm(alarm) }
            initialSnapshot = snapshot()
        }
    }

    // MARK: - Action bar (Cancel / Save)

    private var actionBar: some View {
        HStack {
            Button {
                dismiss()
            } label: {
                Text("Cancel")
                    .font(L.Mono.font(12))
                    .foregroundStyle(L.Palette.muted)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .overlay(Rectangle().stroke(L.Palette.hair2, lineWidth: 1))
            }
            .buttonStyle(.plain)

            Spacer()

            Button {
                vm.save(context: modelContext)
                dismiss()
            } label: {
                Text("Save →")
                    .font(L.Mono.font(12, weight: .semibold))
                    .foregroundStyle(canSave ? L.Palette.bg : L.Palette.dim)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .background(canSave ? L.Palette.fg : Color.clear)
                    .overlay(Rectangle().stroke(canSave ? L.Palette.fg : L.Palette.hair2, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .disabled(!canSave)
        }
        .padding(.horizontal, L.Space.pageH)
        .padding(.vertical, 10)
        .overlay(alignment: .bottom) { L.Palette.hair.frame(height: 1) }
    }

    // MARK: - Sections

    private var timeSection: some View {
        VStack(spacing: 12) {
            sectionKicker("§ 01 · Fires at", centered: true)
            LTimeWheel(
                hour12: Binding(get: { hour12Value }, set: { setHour12($0) }),
                minute: Binding(get: { vm.minute }, set: { vm.minute = $0 }),
                period: Binding(get: { vm.hour < 12 ? "AM" : "PM" }, set: { setPeriod($0) })
            )
        }
        .padding(.horizontal, L.Space.pageH)
        .padding(.vertical, 16)
        .overlay(alignment: .bottom) { L.Palette.hair.frame(height: 1) }
    }

    private var repeatSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionKicker("§ 02 · Repeat")
            HStack(spacing: 6) {
                ForEach(0..<7, id: \.self) { i in
                    let day = i + 1 // 1=Sun ... 7=Sat
                    let on = vm.repeatDays.contains(day)
                    Button {
                        vm.toggleDay(day)
                    } label: {
                        Text(["S","M","T","W","T","F","S"][i])
                            .font(L.Mono.font(12, weight: .semibold))
                            .foregroundStyle(on ? L.Palette.bg : L.Palette.muted)
                            .frame(maxWidth: .infinity)
                            .frame(height: 38)
                            .background(on ? L.Palette.fg : Color.clear)
                            .overlay(Rectangle().stroke(on ? L.Palette.fg : L.Palette.hair2, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.horizontal, L.Space.pageH)
        .padding(.vertical, 14)
        .overlay(alignment: .bottom) { L.Palette.hair.frame(height: 1) }
    }

    private var reasonSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                HStack(spacing: 0) {
                    Text("§ 03 · Why this matters ").kicker(L.Palette.fg)
                    Text("· required").kicker()
                }
                Spacer()
            }

            ZStack(alignment: .topLeading) {
                if vm.reasonText.isEmpty {
                    Text("e.g. I want to be in bed by 10 so I can wake at 6 and write before work.")
                        .font(L.Mono.font(13))
                        .foregroundStyle(L.Palette.dim)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .allowsHitTesting(false)
                }
                TextEditor(text: $vm.reasonText)
                    .font(L.Mono.font(13))
                    .foregroundStyle(L.Palette.fg)
                    .scrollContentBackground(.hidden)
                    .background(L.Palette.bg)
                    .lineSpacing(4)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .frame(minHeight: 130)
                    .overlay(Rectangle().stroke(L.Palette.hair2, lineWidth: 1))
            }

            HStack {
                Text("\(wordCount) words").kicker()
                Spacer()
                Button {
                    toggleRecording()
                } label: {
                    HStack(spacing: 5) {
                        L.Dot(size: 6, color: L.Palette.ringPreview)
                        Text(recorder.isRecording ? "STOP" : "REC")
                            .kicker(L.Palette.ringPreview)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .overlay(Rectangle().stroke(L.Palette.ringPreview.opacity(0.55), lineWidth: 1))
                }
                .buttonStyle(.plain)
            }

            waveform
        }
        .padding(.horizontal, L.Space.pageH)
        .padding(.vertical, 14)
        .background(L.Palette.bg2)
        .overlay(alignment: .top) { L.Palette.hair2.frame(height: 1) }
        .overlay(alignment: .bottom) { L.Palette.hair2.frame(height: 1) }
    }

    private var waveform: some View {
        // 64-bar partial waveform; filled count grows with word density so it feels reactive
        // even without real audio. (Real implementation will plug into voice levels.)
        let bars = 64
        let filled = min(bars, max(0, Int(Double(wordCount) * 1.6)))
        return HStack(alignment: .center, spacing: 1.5) {
            ForEach(0..<bars, id: \.self) { i in
                let seed = sin(Double(i) * 1.37) * 0.5 + 0.5
                let h = 4 + seed * 20
                Rectangle()
                    .fill(i < filled ? L.Palette.fg : L.Palette.dim)
                    .opacity(i < filled ? 0.85 : 0.4)
                    .frame(maxWidth: .infinity)
                    .frame(height: CGFloat(h))
            }
        }
        .frame(height: 26)
    }

    private var labelSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionKicker("§ 04 · Label")
            HStack(spacing: 8) {
                Text(">")
                    .font(L.Mono.font(15))
                    .foregroundStyle(L.Palette.dim)
                TextField("name this alarm…", text: $vm.label)
                    .font(L.Mono.font(15))
                    .foregroundStyle(L.Palette.fg)
                    .textFieldStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(L.Palette.bg)
            .overlay(Rectangle().stroke(L.Palette.hair2, lineWidth: 1))
        }
        .padding(.horizontal, L.Space.pageH)
        .padding(.vertical, 14)
        .overlay(alignment: .bottom) { L.Palette.hair.frame(height: 1) }
    }

    private var escalationSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionKicker("§ 05 · Escalation style")
            ForEach(EscalationLevel.allCases, id: \.self) { level in
                escalationRow(level)
            }
        }
        .padding(.horizontal, L.Space.pageH)
        .padding(.vertical, 14)
        .overlay(alignment: .bottom) { L.Palette.hair.frame(height: 1) }
    }

    private func escalationRow(_ level: EscalationLevel) -> some View {
        let selected = vm.escalationLevel == level
        let c = L.escalationStripeColor(level)
        return Button {
            vm.escalationLevel = level
        } label: {
            HStack(spacing: 12) {
                L.styleGlyph(level, size: 14, color: c)
                    .frame(width: 18, alignment: .center)
                VStack(alignment: .leading, spacing: 2) {
                    Text(level.label)
                        .font(L.Mono.font(13, weight: selected ? .semibold : .regular))
                        .foregroundStyle(L.Palette.fg)
                    Text(level.description)
                        .font(L.Mono.font(11))
                        .foregroundStyle(L.Palette.dim)
                }
                Spacer()
                if selected {
                    Text("✓")
                        .font(L.Mono.font(10.5))
                        .foregroundStyle(L.Palette.fg)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(selected ? L.Palette.bg3 : Color.clear)
            .overlay(Rectangle().stroke(selected ? L.Palette.hair2 : Color.clear, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private var deleteSection: some View {
        Button {
            if let alarm {
                Task { @MainActor in
                    await AlarmKitService.shared.cancelAlarm(alarm)
                }
                modelContext.delete(alarm)
                dismiss()
            }
        } label: {
            Text("delete commitment")
                .kicker(L.Palette.badRed)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .overlay(Rectangle().stroke(L.Palette.hair2, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, L.Space.pageH)
        .padding(.top, 20)
        .padding(.bottom, 30)
    }

    // MARK: - Helpers

    private func sectionKicker(_ text: String, centered: Bool = false) -> some View {
        HStack {
            if centered { Spacer() }
            Text(text).kicker()
            if centered { Spacer() }
            if !centered { Spacer() }
        }
    }

    private var canSave: Bool {
        guard !vm.reasonText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        // For a new alarm there's nothing to be "dirty" against — reason alone is enough.
        return isNew || isDirty
    }

    private var isDirty: Bool { snapshot() != initialSnapshot }

    private func snapshot() -> String {
        "\(vm.hour):\(vm.minute):\(vm.label):\(vm.reasonText):\(vm.escalationLevel.rawValue):\(vm.repeatDays.sorted().map(String.init).joined(separator:","))"
    }

    private var wordCount: Int {
        vm.reasonText.split { $0.isWhitespace || $0.isNewline }.count
    }

    private var hour12Value: Int {
        let h = vm.hour % 12
        return h == 0 ? 12 : h
    }

    private func setHour12(_ h12: Int) {
        let clamped = ((h12 - 1) % 12 + 12) % 12 + 1
        let isPM = vm.hour >= 12
        vm.hour = (clamped % 12) + (isPM ? 12 : 0)
    }

    private func setPeriod(_ p: String) {
        let pm = (p == "PM")
        let base = vm.hour % 12
        vm.hour = base + (pm ? 12 : 0)
    }

    private func toggleRecording() {
        if recorder.isRecording {
            if let url = recorder.stopRecording() {
                vm.reasonAudioPath = url.path
                vm.transcribeVoiceNote(from: url)
            }
        } else {
            recorder.startRecording()
        }
    }
}

// MARK: - Time Wheel

private struct LTimeWheel: View {
    @Binding var hour12: Int
    @Binding var minute: Int
    @Binding var period: String

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            LWheelColumn(value: $hour12, range: 1...12)
            Text(":")
                .font(L.Mono.font(38))
                .foregroundStyle(L.Palette.fg)
                .monospacedDigit()
            LWheelColumn(value: $minute, range: 0...59)
            Button {
                period = period == "AM" ? "PM" : "AM"
            } label: {
                Text(period)
                    .font(L.Mono.font(13, weight: .semibold))
                    .tracking(0.6)
                    .foregroundStyle(L.Palette.fg)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(L.Palette.bg2)
                    .overlay(Rectangle().stroke(L.Palette.hair2, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .padding(.leading, 8)
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }
}

private struct LWheelColumn: View {
    @Binding var value: Int
    let range: ClosedRange<Int>

    var body: some View {
        Picker("", selection: $value) {
            ForEach(Array(range), id: \.self) { n in
                Text(String(format: "%02d", n))
                    .font(L.Mono.font(28, weight: .medium))
                    .foregroundStyle(L.Palette.fg)
                    .monospacedDigit()
                    .tag(n)
            }
        }
        .pickerStyle(.wheel)
        .frame(width: 86, height: 140)
        .clipped()
    }
}
