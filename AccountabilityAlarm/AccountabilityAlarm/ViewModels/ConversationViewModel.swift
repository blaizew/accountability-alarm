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
    var alarmSoundState: AlarmSoundState = .paused

    /// "DOING IT" button is greyed out until the LLM calls `authorize_action`.
    /// The LLM only authorizes once the user has given a concrete commitment
    /// that they're about to perform the action the alarm was set for.
    /// Authorization only unlocks the button — the chain dies on the tap.
    var actionAuthorized = false

    /// How many minutes the Snooze button will snooze for. Seeded from the
    /// alarm's configured `snoozeMinutes` in setup(); LLM adjusts via
    /// `set_snooze_duration`.
    var snoozeButtonMinutes = 3

    /// How many of `messages` were restored from the chain's earlier
    /// conversations (vs. produced in this session). The view uses this to
    /// avoid re-speaking a restored assistant message via TTS on open.
    private(set) var seededMessageCount = 0

    /// Set when the session completes without a user tap (LLM-driven
    /// snooze). The view auto-dismisses the cover — a completed
    /// conversation left presented blocks the next re-ring's trigger from
    /// presenting a fresh one.
    private(set) var autoDismissOnCompletion = false

    private let engine = ConversationEngine()
    private var alarm: Alarm?
    private var event: AlarmEvent?
    /// SwiftUI `.onAppear` can fire multiple times per view presentation
    /// (system re-creates the view, refresh, etc.) — without this guard,
    /// setup() would re-run, duplicate the opening message, reset
    /// `snoozeButtonMinutes` back to the alarm default (wiping any
    /// LLM-set value), and re-schedule the safety-net snooze.
    private var didSetup = false

    // Parallel API-side conversation log (content blocks for tool round-trips).
    private var apiMessages: [ClaudeAPIService.APIMessage] = []
    private var pendingToolResults: [ClaudeAPIService.ContentBlock] = []

    init() {}

    // MARK: - Setup

    func setup(alarmId: UUID, context: ModelContext) {
        guard !didSetup else { return }
        didSetup = true

        let predicate = #Predicate<Alarm> { $0.id == alarmId }
        let descriptor = FetchDescriptor(predicate: predicate)
        guard let alarm = try? context.fetch(descriptor).first else { return }

        self.alarm = alarm
        // Adopt the alarm's configured snooze duration as the conversation's
        // default for the Snooze button. The LLM can still adjust within this
        // session via set_snooze_duration.
        self.snoozeButtonMinutes = alarm.snoozeMinutes

        // Reuse the open wake-up chain if one exists (a prior snooze or the
        // system Stop button already started it) so snoozeCount carries
        // across re-rings — the LLM's skepticism ladder keys off it.
        if let existing = AlarmEvent.openChain(for: alarm) {
            self.event = existing
            // The safety net is the one snooze scheduled without being
            // recorded — it's armed on every conversation open, so recording
            // it then would count a snooze that may never happen. It only
            // becomes real if it actually fires and drags us back here, which
            // is exactly this branch. Attribute it when no recorded snooze
            // accounts for the elapsed pending snooze.
            Self.recordElapsedSafetyNet(alarm: alarm, event: existing)
            // Restore the chain's earlier conversation(s) so this session is
            // a continuation, not a restart: the user sees the prior
            // back-and-forth, saveConversation appends instead of clobbering
            // the stored transcript, and the LLM gets the full history to
            // quote their own words back at them.
            let prior = existing.conversationLog
            messages = prior
            seededMessageCount = prior.count
            // The transcript rides inside the trigger message rather than as
            // replayed turns — the stored log doesn't guarantee strict
            // user/assistant alternation (e.g. a push-back immediately
            // followed by the snooze sign-off), which the API requires.
            apiMessages.append(.init(role: "user", text: Self.reFireTrigger(prior: prior)))
        } else {
            let event = AlarmEvent(alarm: alarm)
            context.insert(event)
            self.event = event
            // Trigger message — the LLM never shows this to the user. The
            // system prompt has explicit instructions for handling it:
            // respond with a specific check-in question grounded in the
            // user's recorded reason.
            apiMessages.append(.init(role: "user", text: "[alarm fired at \(ConversationEngine.clock(Date()))]"))
        }

        Task { @MainActor in
            await LogService.shared.log(
                .conversation,
                "conversation opened (restored \(seededMessageCount) prior messages, snoozeCount=\(event?.snoozeCount ?? 0))",
                alarmId: alarm.id.uuidString
            )

            // Silence any actively-ringing alarm sound. Under normal
            // conditions tapping "Talk to Coach" dismisses the alarm
            // UI/sound automatically; under Downtime collision it doesn't,
            // and the alarm keeps ringing until we explicitly stop it.
            await AlarmKitService.shared.stopAllActive(alarm)

            // Pre-emptive safety net for the "opened conversation but closed
            // the app without resolving" path. 5-minute cadence — the same
            // as the system Stop button — so the user can't accidentally
            // escape the alarm by backgrounding the app.
            await rescheduleSnooze(context: context, minutes: Constants.conversationSafetyNetMinutes)

            // TEMPORARY INSTRUMENTATION (spec AC-4.2). The prompt is not
            // otherwise observable without a test target. Removed in Phase 7.
            await LogService.shared.log(
                .conversation,
                "PROBE timeContext:\n" + engine.buildTimeContext(alarm: alarm, event: event),
                alarmId: alarm.id.uuidString
            )

            // Ask the LLM to generate the opening check-in. Personalized to
            // the user's recorded reason, framed as a concrete question.
            await runAssistantTurn(context: context)
        }
    }

    /// Attribute an elapsed safety-net snooze that nothing else accounts for.
    ///
    /// Coach and button snoozes are recorded when *granted*. The safety net
    /// isn't — it's armed silently at every conversation open, and only counts
    /// if it fires. So when a chain re-opens and the alarm's pending snooze has
    /// already elapsed, we check whether any recorded snooze ends at that time.
    /// If none does, the safety net is what brought the user back.
    private static func recordElapsedSafetyNet(alarm: Alarm, event: AlarmEvent) {
        guard let until = alarm.snoozedUntil, until <= Date() else { return }

        // Tolerance covers scheduling jitter between our Date() math and when
        // AlarmKit actually fires.
        let accountedFor = event.snoozeLog.contains { record in
            let end = record.at.addingTimeInterval(TimeInterval(record.minutes * 60))
            return abs(end.timeIntervalSince(until)) < 90
        }
        guard !accountedFor else { return }

        let minutes = Constants.conversationSafetyNetMinutes
        event.recordSnooze(
            minutes: minutes,
            source: .safetyNet,
            at: until.addingTimeInterval(-TimeInterval(minutes * 60)),
            isApproximate: true
        )
    }

    /// Trigger message for a re-ring within an open chain. Carries the
    /// chain's transcript so the LLM can reference what the user actually
    /// said before snoozing ("at 7:05 you said five more minutes").
    private static func reFireTrigger(prior: [ConversationMessage], now: Date = Date()) -> String {
        guard !prior.isEmpty else { return "[alarm fired at \(ConversationEngine.clock(now))]" }
        var lines = [
            "[alarm re-fired after snooze at \(ConversationEngine.clock(now))]",
            "",
            "Transcript from earlier in this wake-up chain:"
        ]
        // Both roles are stamped here, unlike live turns: this is quoted
        // transcript inside a user message, clearly framed as a record, so
        // there's no risk of the model copying the format into its own replies.
        for m in prior {
            let who = m.role == .assistant ? "COACH" : "USER"
            lines.append("\(who) [\(ConversationEngine.clock(m.timestamp))]: \(m.content)")
        }
        return lines.joined(separator: "\n")
    }

    // MARK: - User-driven turn

    func sendMessage(context: ModelContext) async {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        await LogService.shared.log(
            .conversation,
            "user: \(text.count > 200 ? String(text.prefix(200)) + "…" : text)",
            alarmId: alarm?.id.uuidString
        )

        let uiMessage = ConversationMessage(role: .user, content: text)
        messages.append(uiMessage)
        inputText = ""

        // Stamp ONLY the copy the API sees. The system prompt's "now" refreshes
        // each turn, so without this the Coach can't tell a five-second reply
        // from a five-minute one. Assistant turns are deliberately left
        // unstamped — rewriting the model's own words back into history teaches
        // it to emit "[9:42 PM]" in user-visible replies, and the gap between
        // consecutive user stamps already shows the pacing.
        let stampedText = "[\(ConversationEngine.clock(uiMessage.timestamp))] \(text)"

        var blocks: [ClaudeAPIService.ContentBlock] = []
        if !pendingToolResults.isEmpty {
            blocks.append(contentsOf: pendingToolResults)
            pendingToolResults.removeAll()
        }
        blocks.append(.text(stampedText))

        if blocks.count == 1, case .text = (blocks[0].text.map(ClaudeAPIService.MessageContent.text) ?? .text("")) {
            apiMessages.append(.init(role: "user", text: stampedText))
        } else {
            apiMessages.append(.init(role: "user", blocks: blocks))
        }

        await runAssistantTurn(context: context)

        // Count only THIS session's turns. `messages` is seeded with the
        // chain's earlier conversations on a re-ring, and counting those
        // toward the limit made any re-opened conversation with a decent
        // transcript behind it override itself on the first reply — logging
        // "overridden" and resetting the streak while the user was complying.
        let turnsThisSession = messages.count - seededMessageCount
        if !isCompleted, turnsThisSession >= Constants.maxConversationTurns * 2 {
            handleOverride(reason: "Max conversation turns reached", context: context)
        }
    }

    // MARK: - Explicit outcome resolutions (UI buttons; bypass the LLM)

    func resolveAction(context: ModelContext) {
        guard actionAuthorized else { return }
        handleCompliance(context: context)
    }

    func resolveSnooze(context: ModelContext, minutes: Int? = nil) {
        // A resolved chain (complied/overridden) must never be re-armed —
        // that would re-ring an alarm the ledger already credited.
        guard let alarm, !isCompleted else { return }
        let n = minutes ?? snoozeButtonMinutes
        Task { @MainActor in
            await rescheduleSnooze(context: context, minutes: n)
        }
        event?.recordSnooze(minutes: n, source: .snoozeButton)
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

        let priorId = alarm.pendingSnoozeIdString
        await LogService.shared.log(
            .conversation,
            "rescheduleSnooze: minutes=\(minutes) priorId=\(priorId?.prefix(8).description ?? "nil")",
            alarmId: alarm.id.uuidString
        )

        if let s = priorId, let oldId = UUID(uuidString: s) {
            await AlarmKitService.shared.cancel(alarmKitId: oldId)
        }
        if let newId = await AlarmKitService.shared.scheduleSnooze(alarm: alarm, minutes: minutes) {
            alarm.pendingSnoozeIdString = newId.uuidString
            alarm.snoozedUntil = Date().addingTimeInterval(TimeInterval(minutes * 60))
            await LogService.shared.log(
                .conversation,
                "rescheduleSnooze: scheduled newId=\(newId.uuidString.prefix(8)) fires=\(Int(minutes * 60))s",
                alarmId: alarm.id.uuidString,
                alarmKitId: newId.uuidString
            )
        } else {
            await LogService.shared.log(
                .conversation,
                "rescheduleSnooze: scheduleSnooze returned nil",
                alarmId: alarm.id.uuidString,
                isError: true
            )
        }
        try? context.save()
    }

    /// Cancel the pre-emptive snooze without scheduling a replacement.
    /// Used on comply/override.
    private func cancelPendingSnooze(context: ModelContext) async {
        guard let alarm else { return }
        let priorId = alarm.pendingSnoozeIdString
        await LogService.shared.log(
            .conversation,
            "cancelPendingSnooze: priorId=\(priorId?.prefix(8).description ?? "nil")",
            alarmId: alarm.id.uuidString
        )
        if let s = priorId, let id = UUID(uuidString: s) {
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
            alarm: alarm,
            event: event,
            snoozeButtonMinutes: snoozeButtonMinutes
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
                await LogService.shared.log(
                    .conversation,
                    "assistant: \(response.text.count > 200 ? String(response.text.prefix(200)) + "…" : response.text)",
                    alarmId: alarm.id.uuidString
                )
                messages.append(.init(role: .assistant, content: response.text))
            }
            if !response.toolUses.isEmpty {
                let toolNames = response.toolUses.map(\.name).joined(separator: ", ")
                await LogService.shared.log(
                    .conversation,
                    "assistant tools: \(toolNames)",
                    alarmId: alarm.id.uuidString
                )
            }

            for tool in response.toolUses {
                await dispatch(tool: tool, context: context)
            }

        } catch {
            self.error = error.localizedDescription
            await LogService.shared.log(
                .conversation,
                "api error: \(error.localizedDescription)",
                alarmId: alarm.id.uuidString,
                isError: true
            )
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
        let inputJSON = encodeForLog(tool.input)
        await LogService.shared.log(
            .conversation,
            "tool: \(tool.name) input=\(inputJSON)",
            alarmId: alarm?.id.uuidString
        )

        switch tool.name {

        case "authorize_action":
            actionAuthorized = true
            await LogService.shared.log(.conversation, "authorize_action: DOING IT unlocked", alarmId: alarm?.id.uuidString)
            // Two-step compliance: authorization only unlocks the DOING IT
            // button. The chain dies when the user physically taps it
            // (resolveAction → handleCompliance). A half-asleep "feet on
            // the floor" typed from bed can't kill the alarm on its own —
            // the tap is the cheap-but-real physical confirmation. If the
            // user keeps snoozing instead of tapping, the safety-net snooze
            // keeps the chain alive.
            queueToolResult(id: tool.id, content: "DOING IT button unlocked. The alarm chain stops only when the user taps it — if they keep talking instead of tapping, they haven't followed through yet.")

        case "set_snooze_duration":
            let before = snoozeButtonMinutes
            let resolution = SnoozeResolver.resolve(
                minutes: tool.input["minutes"]?.int,
                until: tool.input["until"]?.string
            )
            switch resolution {
            case let .invalid(message):
                await LogService.shared.log(
                    .conversation,
                    "set_snooze_duration: invalid — \(message)",
                    alarmId: alarm?.id.uuidString,
                    isError: true
                )
                queueToolResult(id: tool.id, content: message, isError: true)

            case let .ok(minutes, returnsAt, requested):
                snoozeButtonMinutes = minutes
                await LogService.shared.log(
                    .conversation,
                    "set_snooze_duration: before=\(before) after=\(minutes)"
                        + (requested.map { " (clamped from \($0.minutes))" } ?? ""),
                    alarmId: alarm?.id.uuidString
                )
                // Only changes the user-facing Snooze button. The pre-emptive
                // safety-net "you didn't engage" timer is separate.
                queueToolResult(
                    id: tool.id,
                    content: Self.snoozeResultText(
                        verb: "Snooze button set to",
                        minutes: minutes,
                        returnsAt: returnsAt,
                        requested: requested
                    )
                )
            }

        case "mark_overridden":
            let reason = tool.input["reason"]?.string ?? "(no reason)"
            await LogService.shared.log(.conversation, "mark_overridden: \(reason)", alarmId: alarm?.id.uuidString)
            queueToolResult(id: tool.id, content: "Logged as overridden.")
            await cancelPendingSnooze(context: context)
            handleOverride(reason: reason, context: context)

        case "snooze_alarm":
            guard !isCompleted else {
                queueToolResult(id: tool.id, content: "Alarm already resolved — no snooze scheduled.", isError: true)
                break
            }
            let hasAny = tool.input["minutes"]?.int != nil || tool.input["until"]?.string != nil
            let resolution = hasAny
                ? SnoozeResolver.resolve(
                    minutes: tool.input["minutes"]?.int,
                    until: tool.input["until"]?.string
                  )
                // Neither given: fall back to the button's current duration
                // rather than refusing — the user is already owed a snooze.
                : SnoozeResolver.resolve(minutes: snoozeButtonMinutes, until: nil)

            switch resolution {
            case let .invalid(message):
                await LogService.shared.log(
                    .conversation,
                    "snooze_alarm: invalid — \(message)",
                    alarmId: alarm?.id.uuidString,
                    isError: true
                )
                queueToolResult(id: tool.id, content: message, isError: true)

            case let .ok(minutes, returnsAt, requested):
                await LogService.shared.log(
                    .conversation,
                    "snooze_alarm: \(minutes) min, returns \(ConversationEngine.clock(returnsAt))"
                        + (requested.map { " (clamped from \($0.minutes))" } ?? ""),
                    alarmId: alarm?.id.uuidString
                )
                await rescheduleSnooze(context: context, minutes: minutes)
                event?.recordSnooze(minutes: minutes, source: .coach)
                alarmSoundState = .stopped
                let resultText = Self.snoozeResultText(
                    verb: "Snoozed",
                    minutes: minutes,
                    returnsAt: returnsAt,
                    requested: requested
                )
                await LogService.shared.log(
                    .conversation,
                    "tool result: \(resultText)",
                    alarmId: alarm?.id.uuidString
                )
                queueToolResult(id: tool.id, content: resultText)
                autoDismissOnCompletion = true
                isCompleted = true
                saveConversation(context: context)
            }

        default:
            await LogService.shared.log(.conversation, "unknown tool: \(tool.name)", alarmId: alarm?.id.uuidString, isError: true)
            queueToolResult(id: tool.id, content: "Unknown tool.", isError: true)
        }
    }

    /// Serialize a tool input JSONValue to a compact string for the log. Keeps
    /// the log scannable while still preserving the actual parameters the
    /// LLM passed.
    private func encodeForLog(_ value: JSONValue) -> String {
        let encoder = JSONEncoder()
        guard let data = try? encoder.encode(value),
              let str = String(data: data, encoding: .utf8) else {
            return "<unencodable>"
        }
        // Cap at 200 chars so a runaway prompt doesn't blow up the log row.
        if str.count > 200 { return String(str.prefix(200)) + "…" }
        return str
    }

    /// Tool result text for a resolved snooze.
    ///
    /// Always states the absolute return time — a relative "Snoozed 18
    /// minutes" leaves the Coach able to tell the user only something
    /// relative, and it was that gap the user fell through. When the ask was
    /// clamped, both numbers are named and the Coach is told to say so, so it
    /// can never promise a return time the alarm won't honour.
    private static func snoozeResultText(
        verb: String,
        minutes: Int,
        returnsAt: Date,
        requested: (minutes: Int, at: Date)?
    ) -> String {
        let base = "\(verb) \(minutes) minutes — alarm returns at \(ConversationEngine.clock(returnsAt))."
        guard let requested else { return base }
        return """
        Requested \(ConversationEngine.clock(requested.at)) = \(requested.minutes) min, \
        over the \(Constants.maxSnoozeMinutes) min cap. \(base) \
        Not \(ConversationEngine.clock(requested.at)). Tell the user this explicitly.
        """
    }

    private func queueToolResult(id: String, content: String, isError: Bool = false) {
        pendingToolResults.append(.toolResult(id: id, content: content, isError: isError))
    }

    // MARK: - Outcome handlers

    private func handleCompliance(context: ModelContext) {
        guard !isCompleted else { return }
        alarmSoundState = .stopped
        isCompleted = true

        // A chain that took snoozes before complying is the ledger's yellow
        // "snoozed then complied" — distinct from a clean first-ring comply.
        event?.outcome = (event?.snoozeCount ?? 0) > 0 ? "snoozed_then_complied" : "complied"
        event?.complianceTimeMinutes = minutesSinceStart()
        saveConversation(context: context)

        Task { @MainActor in
            await LogService.shared.log(.conversation, "comply", alarmId: alarm?.id.uuidString)
            if let alarm { await AlarmKitService.shared.stopAllActive(alarm) }
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
            await LogService.shared.log(.conversation, "override: \(reason)", alarmId: alarm?.id.uuidString)
            if let alarm { await AlarmKitService.shared.stopAllActive(alarm) }
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
