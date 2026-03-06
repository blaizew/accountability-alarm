import SwiftUI
import SwiftData

enum AlarmSoundState: Equatable {
    case playing
    case paused
    case stopped
}

@Observable
final class ConversationViewModel {
    var messages: [ConversationMessage] = []
    var inputText = ""
    var isLoading = false
    var error: String?
    var isCompleted = false
    var currentRing: EscalationRing
    var alarmSoundState: AlarmSoundState = .paused

    private let engine = ConversationEngine()
    private var alarm: Alarm?
    private var event: AlarmEvent?
    private var systemPrompt = ""
    private var overrideAttempts = 0
    private var snoozeTimer: Timer?

    init(initialRing: EscalationRing) {
        self.currentRing = initialRing
    }

    func setup(alarmId: UUID, context: ModelContext) {
        let predicate = #Predicate<Alarm> { $0.id == alarmId }
        let descriptor = FetchDescriptor(predicate: predicate)
        guard let alarm = try? context.fetch(descriptor).first else { return }

        self.alarm = alarm

        // Create event for this alarm interaction
        let event = AlarmEvent(alarm: alarm)
        context.insert(event)
        self.event = event

        systemPrompt = engine.buildSystemPrompt(
            alarm: alarm, ring: currentRing, event: event
        )

        // Add opening message
        let opening = engine.openingMessage(alarm: alarm, ring: currentRing)
        let message = ConversationMessage(role: .assistant, content: opening)
        messages.append(message)
    }

    func sendMessage(context: ModelContext) async {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        let userMessage = ConversationMessage(role: .user, content: text)
        messages.append(userMessage)
        inputText = ""

        // Check intent
        let intent = engine.detectIntent(text)

        switch intent {
        case .comply:
            handleCompliance(context: context)
            return
        case .override:
            overrideAttempts += 1
            let level = alarm?.escalationLevel ?? .firm
            if engine.shouldAcceptOverride(level: level, overrideAttempts: overrideAttempts) {
                handleOverride(reason: text, context: context)
                return
            }
            // Not enough pushback yet — fall through to AI response
        case .snooze, .continue:
            break
        }

        // Get AI response
        isLoading = true
        error = nil

        do {
            let response = try await ClaudeAPIService.shared.sendMessage(
                systemPrompt: systemPrompt,
                messages: messages
            )
            let (cleanedMessage, alarmAction) = engine.parseAlarmAction(from: response)
            let aiMessage = ConversationMessage(role: .assistant, content: cleanedMessage)
            messages.append(aiMessage)
            if let alarmAction {
                applyAlarmAction(alarmAction, context: context)
            }
        } catch {
            self.error = error.localizedDescription
            let fallback = ConversationMessage(
                role: .assistant,
                content: "I'm having trouble connecting. But remember why you set this alarm. Are you going to listen to past-you?"
            )
            messages.append(fallback)
        }

        isLoading = false
        saveConversation(context: context)

        // Auto-complete after max turns
        if messages.count >= Constants.maxConversationTurns * 2 {
            handleOverride(reason: "Max conversation turns reached", context: context)
        }
    }

    func addVoiceInput(_ text: String) {
        inputText = text
    }

    private func handleCompliance(context: ModelContext) {
        let level = alarm?.escalationLevel ?? .firm
        let responseText: String
        switch level {
        case .gentle:
            responseText = "Nice. Proud of you for following through."
        case .firm:
            responseText = "Good call. That's what you said you'd do."
        case .relentless:
            responseText = "That's what I like to hear. Now go do it. No more stalling."
        }

        let response = ConversationMessage(role: .assistant, content: responseText)
        messages.append(response)
        isCompleted = true
        alarmSoundState = .stopped

        event?.outcome = "complied"
        event?.complianceTimeMinutes = minutesSinceStart()
        saveConversation(context: context)

        if let alarm {
            NotificationService.shared.cancelRemainingRings(
                alarm: alarm, afterRing: currentRing
            )
            if !alarm.repeatDays.isEmpty {
                NotificationService.shared.rescheduleRemainingRings(
                    alarm: alarm, afterRing: currentRing
                )
            }
        }
    }

    private func handleOverride(reason: String, context: ModelContext) {
        let level = alarm?.escalationLevel ?? .firm
        let responseText: String
        switch level {
        case .gentle:
            responseText = "Okay, no worries. I'll be here next time."
        case .firm:
            responseText = "Okay. Logged. We'll see how that works out."
        case .relentless:
            responseText = "Fine. Logged. We both know you're going to wish you hadn't skipped. I'll be here."
        }

        let response = ConversationMessage(role: .assistant, content: responseText)
        messages.append(response)
        isCompleted = true
        alarmSoundState = .stopped

        event?.outcome = "overridden"
        event?.overrideReason = reason
        event?.complianceTimeMinutes = minutesSinceStart()
        saveConversation(context: context)

        if let alarm {
            NotificationService.shared.cancelRemainingRings(
                alarm: alarm, afterRing: currentRing
            )
            if !alarm.repeatDays.isEmpty {
                NotificationService.shared.rescheduleRemainingRings(
                    alarm: alarm, afterRing: currentRing
                )
            }
        }
    }

    private func applyAlarmAction(_ action: ConversationEngine.AlarmAction, context: ModelContext) {
        snoozeTimer?.invalidate()
        snoozeTimer = nil

        switch action {
        case .stop:
            alarmSoundState = .stopped
        case .resume:
            alarmSoundState = .playing
        case .snooze(let minutes):
            alarmSoundState = .paused
            event?.snoozeCount += 1
            saveConversation(context: context)
            snoozeTimer = Timer.scheduledTimer(withTimeInterval: TimeInterval(minutes * 60), repeats: false) { [weak self] _ in
                Task { @MainActor in
                    self?.alarmSoundState = .playing
                }
            }
        }
    }

    private func saveConversation(context: ModelContext) {
        event?.conversationLog = messages
        try? context.save()
    }

    private func minutesSinceStart() -> Int {
        guard let event else { return 0 }
        return Int(Date().timeIntervalSince(event.firedAt) / 60)
    }
}
