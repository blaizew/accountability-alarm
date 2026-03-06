import SwiftUI
import SwiftData

struct AlarmEditView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel = AlarmEditViewModel()

    var alarm: Alarm?

    var body: some View {
        NavigationStack {
            Form {
                timeSection
                labelSection
                repeatSection
                reasonSection
                escalationSection
                sleepToggleSection
                if viewModel.showSleepSettings {
                    sleepTargetSection
                    morningEventSection
                }
            }
            .navigationTitle(viewModel.isEditing ? "Edit Alarm" : "New Alarm")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        viewModel.save(context: modelContext)
                        dismiss()
                    }
                }
            }
            .onAppear {
                if let alarm {
                    viewModel.loadAlarm(alarm)
                }
            }
        }
    }

    private var timeSection: some View {
        Section {
            DatePicker(
                "Time",
                selection: $viewModel.selectedTime,
                displayedComponents: .hourAndMinute
            )
            .datePickerStyle(.wheel)
            .labelsHidden()
            .frame(maxWidth: .infinity)
        }
    }

    private var labelSection: some View {
        Section("Label") {
            TextField("e.g. Bedtime, Wake Up", text: $viewModel.label)
        }
    }

    private var repeatSection: some View {
        Section("Repeat") {
            RepeatDayPicker(selectedDays: $viewModel.repeatDays)
        }
    }

    private var reasonSection: some View {
        Section("Why does this alarm matter?") {
            TextField(
                "e.g. I need to start work — big day today",
                text: $viewModel.reasonText,
                axis: .vertical
            )
            .lineLimit(3...6)

            VoiceRecordButton { url in
                viewModel.reasonAudioPath = url.path
                viewModel.transcribeVoiceNote(from: url)
            }

            if viewModel.isTranscribing {
                Label("Transcribing voice note...", systemImage: "waveform")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if viewModel.reasonAudioPath != nil {
                Label("Voice memo saved", systemImage: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.green)
            }
        }
    }

    private var escalationSection: some View {
        Section("Escalation Style") {
            ForEach(EscalationLevel.allCases, id: \.self) { level in
                EscalationLevelRow(
                    level: level,
                    isSelected: viewModel.escalationLevel == level
                ) {
                    viewModel.escalationLevel = level
                }
            }
        }
    }

    private var sleepToggleSection: some View {
        Section {
            Toggle("Sleep settings", isOn: $viewModel.showSleepSettings)
        } footer: {
            Text("Add sleep target and morning event for smarter conversations")
        }
    }

    private var sleepTargetSection: some View {
        Section("Sleep Target") {
            HStack {
                Text("Hours")
                Spacer()
                TextField(
                    "7.0",
                    value: $viewModel.targetSleepHours,
                    format: .number
                )
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 60)
            }
        }
    }

    private var morningEventSection: some View {
        Section("Morning Event") {
            TextField("e.g. Standup meeting", text: $viewModel.nextMorningEvent)
            if !viewModel.nextMorningEvent.isEmpty {
                DatePicker(
                    "Event time",
                    selection: $viewModel.morningEventTime,
                    displayedComponents: .hourAndMinute
                )
            }
        }
    }
}

// MARK: - Sub-components

struct RepeatDayPicker: View {
    @Binding var selectedDays: Set<Int>

    private let dayNames = ["S", "M", "T", "W", "T", "F", "S"]
    private let dayValues = [1, 2, 3, 4, 5, 6, 7]

    var body: some View {
        HStack(spacing: 8) {
            ForEach(Array(zip(dayValues, dayNames)), id: \.0) { day, name in
                Button {
                    if selectedDays.contains(day) {
                        selectedDays.remove(day)
                    } else {
                        selectedDays.insert(day)
                    }
                } label: {
                    Text(name)
                        .font(.caption.bold())
                        .frame(width: 36, height: 36)
                        .background(
                            selectedDays.contains(day)
                                ? Color.accentColor : Color(.systemGray5)
                        )
                        .foregroundStyle(
                            selectedDays.contains(day) ? .white : .primary
                        )
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

struct EscalationLevelRow: View {
    let level: EscalationLevel
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack {
                Image(systemName: level.icon)
                    .frame(width: 24)
                VStack(alignment: .leading, spacing: 2) {
                    Text(level.label)
                        .font(.body)
                    Text(level.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark")
                        .foregroundStyle(Color.accentColor)
                }
            }
            .foregroundStyle(.primary)
        }
    }
}
