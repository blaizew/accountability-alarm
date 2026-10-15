import SwiftUI
import SwiftData
import Speech

@Observable
final class AlarmEditViewModel {
    var label = ""
    var hour = 22
    var minute = 0
    var repeatDays: Set<Int> = []
    var reasonText = ""

    /// Five-box commitment fields. Each box has its own voice/text input in
    /// the edit screen and all five (with their titles) get passed to the LLM.
    var desiredBehavior = ""
    var whyWantThis = ""
    var positiveOutcome = ""
    var negativeOutcome = ""
    var longTermImpact = ""
    var exceptionCases = ""

    var targetSleepHours: Double? = nil
    var nextMorningEvent = ""
    var nextMorningEventHour: Int? = nil
    var nextMorningEventMinute: Int? = nil
    var showSleepSettings = false
    var snoozeMinutes: Int = 10
    var isRecording = false
    var reasonAudioPath: String?
    var isTranscribing = false

    private var existingAlarm: Alarm?

    var isEditing: Bool { existingAlarm != nil }

    var selectedTime: Date {
        get {
            var components = DateComponents()
            components.hour = hour
            components.minute = minute
            return Calendar.current.date(from: components) ?? Date()
        }
        set {
            let components = Calendar.current.dateComponents([.hour, .minute], from: newValue)
            hour = components.hour ?? 22
            minute = components.minute ?? 0
        }
    }

    var morningEventTime: Date {
        get {
            var components = DateComponents()
            components.hour = nextMorningEventHour ?? 7
            components.minute = nextMorningEventMinute ?? 0
            return Calendar.current.date(from: components) ?? Date()
        }
        set {
            let components = Calendar.current.dateComponents([.hour, .minute], from: newValue)
            nextMorningEventHour = components.hour
            nextMorningEventMinute = components.minute
        }
    }

    func loadAlarm(_ alarm: Alarm) {
        existingAlarm = alarm
        label = alarm.label
        hour = alarm.hour
        minute = alarm.minute
        repeatDays = Set(alarm.repeatDays)
        reasonText = alarm.reasonText

        desiredBehavior = alarm.desiredBehavior
        whyWantThis = alarm.whyWantThis
        positiveOutcome = alarm.positiveOutcome
        negativeOutcome = alarm.negativeOutcome
        longTermImpact = alarm.longTermImpact
        exceptionCases = alarm.exceptionCases

        // Legacy alarms only have reasonText. On first edit, surface it in
        // the "Desired behavior" box so the user can split it across the
        // five fields rather than losing it.
        let hasAnyNew = !desiredBehavior.isEmpty
            || !whyWantThis.isEmpty
            || !positiveOutcome.isEmpty
            || !negativeOutcome.isEmpty
            || !longTermImpact.isEmpty
        if !hasAnyNew && !reasonText.isEmpty {
            desiredBehavior = reasonText
        }

        targetSleepHours = alarm.targetSleepHours
        nextMorningEvent = alarm.nextMorningEvent ?? ""
        nextMorningEventHour = alarm.nextMorningEventHour
        nextMorningEventMinute = alarm.nextMorningEventMinute
        snoozeMinutes = alarm.snoozeMinutes
        reasonAudioPath = alarm.reasonAudioPath
        showSleepSettings = alarm.targetSleepHours != nil || alarm.nextMorningEvent != nil
    }

    func save(context: ModelContext) {
        let alarm: Alarm
        if let existing = existingAlarm {
            alarm = existing
        } else {
            alarm = Alarm()
            context.insert(alarm)
        }

        alarm.label = label
        alarm.hour = hour
        alarm.minute = minute
        alarm.repeatDays = repeatDays.sorted()
        alarm.reasonText = reasonText
        alarm.desiredBehavior = desiredBehavior
        alarm.whyWantThis = whyWantThis
        alarm.positiveOutcome = positiveOutcome
        alarm.negativeOutcome = negativeOutcome
        alarm.longTermImpact = longTermImpact
        alarm.exceptionCases = exceptionCases
        alarm.targetSleepHours = targetSleepHours
        alarm.nextMorningEvent = nextMorningEvent.isEmpty ? nil : nextMorningEvent
        alarm.nextMorningEventHour = nextMorningEventHour
        alarm.nextMorningEventMinute = nextMorningEventMinute
        alarm.reasonAudioPath = reasonAudioPath
        alarm.snoozeMinutes = max(1, min(30, snoozeMinutes))
        alarm.enabled = true

        // Schedule with AlarmKit (rings through Silent/DnD/Focus at alarm volume).
        Task { @MainActor in
            let ids = await AlarmKitService.shared.scheduleAlarm(alarm)
            alarm.alarmKitIdStrings = ids.map(\.uuidString)
        }
    }

    func toggleDay(_ day: Int) {
        if repeatDays.contains(day) {
            repeatDays.remove(day)
        } else {
            repeatDays.insert(day)
        }
    }

    func transcribeVoiceNote(from url: URL) {
        guard let recognizer = SFSpeechRecognizer(), recognizer.isAvailable else { return }

        isTranscribing = true
        let request = SFSpeechURLRecognitionRequest(url: url)

        recognizer.recognitionTask(with: request) { [weak self] result, error in
            guard let self else { return }
            if let result, result.isFinal {
                self.reasonText = result.bestTranscription.formattedString
                self.isTranscribing = false
            } else if error != nil {
                self.isTranscribing = false
            }
        }
    }
}
