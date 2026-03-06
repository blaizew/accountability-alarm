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
    var targetSleepHours: Double? = nil
    var nextMorningEvent = ""
    var nextMorningEventHour: Int? = nil
    var nextMorningEventMinute: Int? = nil
    var showSleepSettings = false
    var escalationLevel: EscalationLevel = .firm
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
        targetSleepHours = alarm.targetSleepHours
        nextMorningEvent = alarm.nextMorningEvent ?? ""
        nextMorningEventHour = alarm.nextMorningEventHour
        nextMorningEventMinute = alarm.nextMorningEventMinute
        escalationLevel = alarm.escalationLevel
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
        alarm.targetSleepHours = targetSleepHours
        alarm.nextMorningEvent = nextMorningEvent.isEmpty ? nil : nextMorningEvent
        alarm.nextMorningEventHour = nextMorningEventHour
        alarm.nextMorningEventMinute = nextMorningEventMinute
        alarm.reasonAudioPath = reasonAudioPath
        alarm.escalationLevel = escalationLevel
        alarm.enabled = true

        NotificationService.shared.scheduleAlarm(alarm)
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
