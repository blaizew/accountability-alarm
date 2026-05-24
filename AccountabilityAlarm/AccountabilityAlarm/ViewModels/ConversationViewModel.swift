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

    /// Comply button is greyed out until the LLM calls `authorize_comply`.
    var complyAuthorized = false

    /// How many minutes the Snooze button will snooze for. LLM controls via
    /// `set_snooze_duration`. Defaults to 3.
    var snoozeButtonMinutes = 3

    private let engine = ConversationEngine()
    private var alarm: Alarm?
    private var event: AlarmEvent?

    // Parallel API-side conversation log (content blocks for tool round-trips).
    private var apiMessages: [ClaudeAPIService.APIMessage] = []
    private var pendingToolResults: [ClaudeAPIService.ContentBlock] = []

    init(initialRing: EscalationRing) {
        self.currentRing = initialRing
    }

    // MARK: - Setup

    func setup(alarmId: UUID, context: ModelContext) {
        let predicate = #Predicate<Alarm> { $0.id == alarmId }
        let descriptor = FetchDescriptor(predicate: predicate)
        guard let alarm = try? context.fetch(descriptor).first else { return }

        self.alarm = alarm

        let event = AlarmEvent(alarm: alarm)
        context.insert(event)
        self.event = event

        let opening = engine.openingMessage(alarm: alarm, ring: currentRing)
        messages.append(.init(role: .assistant, content: opening))
        apiMessages.append(.init(role: "assistant", text: opening))

        Task { @MainActor in
            // The user is interacting, so cancel today's T+1 companion (which
            // was about to fire / just fired and woke us) and schedule
            // tomorrow's T+1 in its place. This keeps T+1 companions as
            // individually-cancellable one-shots per occurrence.
            let nextT1 = await AlarmKitService.shared.refreshNextCompanion(for: alarm)
            alarm.nextT1IdString = nextT1?.uuidString
            try? context.save()

            // Pre-emptive snooze safety net for the "user opened the
            // conversation but closed the app without resolving" path.
            // Fires after 1 minute. Distinct from the next-instance T+1
            // companion and from the user-facing Snooze button.
            await rescheduleSnooze(context: context, minutes: 1)
        }
    }

    // MARK: - User-driven turn

    func sendMessage(context: ModelContext) async {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        let uiMessage = ConversationMessage(role: .user, content: text)
        messages.append(uiMessage)
        inputText = ""

        var blocks: [ClaudeAPIService.ContentBlock] = []
        if !pendingToolResults.isEmpty {
            blocks.append(contentsOf: pendingToolResults)
            pendingToolResults.removeAll()
        }
        blocks.append(.text(text))

        if blocks.count == 1, case .text = (blocks[0].text.map(ClaudeAPIService.MessageContent.text) ?? .text("")) {
            apiMessages.append(.init(role: "user", text: text))
        } else {
            apiMessages.append(.init(role: "user", blocks: blocks))
        }

        await runAssistantTurn(context: context)

        if !isCompleted, messages.count >= Constants.maxConversationTurns * 2 {
            handleOverride(reason: "Max conversation turns reached", context: context)
        }
    }

    // MARK: - Explicit outcome resolutions (UI buttons; bypass the LLM)

    func resolveComply(context: ModelContext) {
        guard complyAuthorized else { return }
        handleCompliance(context: context)
    }

    func resolveSnooze(context: ModelContext, minutes: Int? = nil) {
        guard let alarm else { return }
        let n = minutes ?? snoozeButtonMinutes
        Task { @MainActor in
            await rescheduleSnooze(context: context, minutes: n)
        }
        event?.snoozeCount += 1
        alarm.snoozedUntil = Date().addingTimeInterval(TimeInterval(n * 60))
        alarmSoundState = .stopped
        messages.append(.init(role: .assistant, content: "Okay — \(n) more minutes. I'll be back."))
        saveConversation(context: context)
        isCompleted = true
    }

    func resolveOverride(reason: String, context: ModelContext) {
        handleOverride(reason: reason, context: context)
    }

    // MARK: - Snooze management

    /// Cancel any in-flight pre-emptive snooze and schedule a fresh one.
    /// Single source of truth for "this alarm should re-ring in N minutes."
    private func rescheduleSnooze(context: ModelContext, minutes: Int) async {
        guard let alarm else { return }
        if let s = alarm.pendingSnoozeIdString, let oldId = UUID(uuidString: s) {
            await AlarmKitService.shared.cancel(alarmKitId: oldId)
        }
        if let newId = await AlarmKitService.shared.scheduleSnooze(alarm: alarm, minutes: minutes) {
            alarm.pendingSnoozeIdString = newId.uuidString
            alarm.snoozedUntil = Date().addingTimeInterval(TimeInterval(minutes * 60))
        }
        try? context.save()
    }

    /// Cancel the pre-emptive snooze without scheduling a replacement.
    /// Used on comply/override.
    private func cancelPendingSnooze(context: ModelContext) async {
        guard let alarm else { return }
        if let s = alarm.pendingSnoozeIdString, let id = UUID(uuidString: s) {
            await AlarmKitService.shared.cancel(alarmKitId: id)
        }
        alarm.pendingSnoozeIdString = nil
        alarm.snoozedUntil = nil
        try? context.save()
    }

    // MARK: - Assistant turn (API call + tool dispatch)

    private func runAssistantTurn(context: ModelContext) async {
        guard let alarm else { return }
        isLoading = true
        error = nil

        let systemPrompt = engine.buildSystemPrompt(
            alarm: alarm, ring: currentRing, event: event
        )

        do {
            let response = try await ClaudeAPIService.shared.sendMessage(
                systemPrompt: systemPrompt,
                messages: apiMessages,
                tools: ConversationEngine.tools
            )

            var assistantBlocks: [ClaudeAPIService.ContentBlock] = []
            if !response.text.isEmpty {
                assistantBlocks.append(.text(response.text))
            }
            for tool in response.toolUses {
                assistantBlocks.append(.toolUse(id: tool.id, name: tool.name, input: tool.input))
            }
            if !assistantBlocks.isEmpty {
                apiMessages.append(.init(role: "assistant", blocks: assistantBlocks))
            }

            if !response.text.isEmpty {
                messages.append(.init(role: .assistant, content: response.text))
            }

            for tool in response.toolUses {
                await dispatch(tool: tool, context: context)
            }

        } catch {
            self.error = error.localizedDescription
            messages.append(.init(
                role: .assistant,
                content: "I'm having trouble connecting. But remember why you set this alarm. Are you going to listen to past-you?"
            ))
        }

        isLoading = false
        saveConversation(context: context)
    }

    // MARK: - Tool dispatch

    private func dispatch(tool: ClaudeAPIService.ToolUse, context: ModelContext) async {
        switch tool.name {

        case "authorize_comply":
            complyAuthorized = true
            queueToolResult(id: tool.id, content: "Comply button enabled. Awaiting user tap.")

        case "set_snooze_duration":
            let minutes = tool.input["minutes"]?.int ?? 3
            snoozeButtonMinutes = max(1, min(30, minutes))
            // Only changes the user-facing Snooze button. The pre-emptive
            // 1-min "you didn't engage" timer is separate and not affected.
            queueToolResult(id: tool.id, content: "Snooze button set to \(snoozeButtonMinutes) minutes.")

        case "mark_overridden":
            let reason = tool.input["reason"]?.string ?? "(no reason)"
            queueToolResult(id: tool.id, content: "Logged as overridden.")
            await cancelPendingSnooze(context: context)
            handleOverride(reason: reason, context: context)

        case "snooze_alarm":
            let minutes = tool.input["minutes"]?.int ?? 3
            await rescheduleSnooze(context: context, minutes: minutes)
            event?.snoozeCount += 1
            alarmSoundState = .stopped
            queueToolResult(id: tool.id, content: "Snoozed for \(minutes) minutes.")
            isCompleted = true
            saveConversation(context: context)

        case "escalate_ring":
            if let next = nextRing(after: currentRing) {
                currentRing = next
                queueToolResult(id: tool.id, content: "Escalated to ring: \(next.label).")
            } else {
                queueToolResult(id: tool.id, content: "Already at preview ring. No further escalation.", isError: true)
            }

        default:
            queueToolResult(id: tool.id, content: "Unknown tool.", isError: true)
        }
    }

    private func queueToolResult(id: String, content: String, isError: Bool = false) {
        pendingToolResults.append(.toolResult(id: id, content: content, isError: isError))
    }

    private func nextRing(after ring: EscalationRing) -> EscalationRing? {
        switch ring {
        case .nudge:   return .math
        case .math:    return .mirror
        case .mirror:  return .preview
        case .preview: return nil
        }
    }

    // MARK: - Outcome handlers

    private func handleCompliance(context: ModelContext) {
        guard !isCompleted else { return }
        alarmSoundState = .stopped
        isCompleted = true

        event?.outcome = "complied"
        event?.complianceTimeMinutes = minutesSinceStart()
        saveConversation(context: context)

        Task { @MainActor in
            await cancelPendingSnooze(context: context)
        }
    }

    private func handleOverride(reason: String, context: ModelContext) {
        guard !isCompleted else { return }
        alarmSoundState = .stopped
        isCompleted = true

        event?.outcome = "overridden"
        event?.overrideReason = reason
        event?.complianceTimeMinutes = minutesSinceStart()
        saveConversation(context: context)

        Task { @MainActor in
            await cancelPendingSnooze(context: context)
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
