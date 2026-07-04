import SwiftUI
import SwiftData

struct AlarmEditView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var vm = AlarmEditViewModel()
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
                    snoozeSection
                    labelSection

                    LCommitmentField(
                        sectionNumber: "05",
                        title: "Desired behavior",
                        placeholder: "e.g. be in bed with lights out by 10pm",
                        required: true,
                        text: $vm.desiredBehavior
                    )
                    LCommitmentField(
                        sectionNumber: "06",
                        title: "Why do you want this?",
                        placeholder: "e.g. so I can wake at 6 and have an hour to write before work",
                        text: $vm.whyWantThis
                    )
                    LCommitmentField(
                        sectionNumber: "07",
                        title: "What positive outcome happens when you do it",
                        placeholder: "e.g. I feel sharp, present at the morning standup, get my deep work done",
                        text: $vm.positiveOutcome
                    )
                    LCommitmentField(
                        sectionNumber: "08",
                        title: "What negative outcome happens when you don't do it",
                        placeholder: "e.g. I'm groggy, snap at people in meetings, skip the gym",
                        text: $vm.negativeOutcome
                    )
                    LCommitmentField(
                        sectionNumber: "09",
                        title: "What is the long-term impact of not doing this?",
                        placeholder: "e.g. years of sleep debt, no writing portfolio, drift from the life I want",
                        text: $vm.longTermImpact
                    )

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


    private var snoozeSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionKicker("§ 03 · Snooze duration")
            HStack(spacing: 12) {
                Button {
                    vm.snoozeMinutes = max(1, vm.snoozeMinutes - 1)
                } label: {
                    Text("–")
                        .font(L.Mono.font(18, weight: .medium))
                        .foregroundStyle(L.Palette.fg)
                        .frame(width: 38, height: 38)
                        .overlay(Rectangle().stroke(L.Palette.hair2, lineWidth: 1))
                }
                .buttonStyle(.plain)

                HStack(alignment: .lastTextBaseline, spacing: 4) {
                    Text("\(vm.snoozeMinutes)")
                        .font(L.Mono.font(28, weight: .medium))
                        .foregroundStyle(L.Palette.fg)
                        .monospacedDigit()
                    Text(vm.snoozeMinutes == 1 ? "min" : "min")
                        .font(L.Mono.font(13))
                        .foregroundStyle(L.Palette.muted)
                }
                .frame(maxWidth: .infinity)

                Button {
                    vm.snoozeMinutes = min(30, vm.snoozeMinutes + 1)
                } label: {
                    Text("+")
                        .font(L.Mono.font(18, weight: .medium))
                        .foregroundStyle(L.Palette.fg)
                        .frame(width: 38, height: 38)
                        .overlay(Rectangle().stroke(L.Palette.hair2, lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
            Text("// how long past-self snoozes when you ask. slide-to-stop on the alarm is fixed at 5 min.")
                .kicker()
        }
        .padding(.horizontal, L.Space.pageH)
        .padding(.vertical, 14)
        .overlay(alignment: .bottom) { L.Palette.hair.frame(height: 1) }
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
        // Require at least the first (required) commitment box. Other fields
        // are optional — the user can fill them in later via edit.
        guard !vm.desiredBehavior.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        return isNew || isDirty
    }

    private var isDirty: Bool { snapshot() != initialSnapshot }

    private func snapshot() -> String {
        [
            "\(vm.hour):\(vm.minute)",
            vm.label,
            vm.snoozeMinutes.description,
            vm.repeatDays.sorted().map(String.init).joined(separator: ","),
            vm.desiredBehavior,
            vm.whyWantThis,
            vm.positiveOutcome,
            vm.negativeOutcome,
            vm.longTermImpact,
        ].joined(separator: "|")
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
