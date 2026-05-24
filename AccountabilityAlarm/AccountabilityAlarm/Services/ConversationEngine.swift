import Foundation

/// Builds prompts and the tool toolbox the LLM uses to drive the conversation.
final class ConversationEngine {

    // MARK: - Tools the model can call

    /// The control tools the model uses to drive app behavior.
    /// Returning *no* tool means "I'm still talking; keep the conversation going."
    static let tools: [ClaudeAPIService.Tool] = [
        .init(
            name: "authorize_comply",
            description: """
                Call this when you are convinced the user is genuinely about to follow \
                through. This does NOT stop the alarm yet — it enables a Comply button \
                in the UI that the user must then physically tap to confirm. This two-step \
                pattern prevents fake compliance from a cheap "yeah". Only call when the \
                user has told you something concrete about what they're doing (e.g. "feet \
                on the floor", "closing the laptop now"), not just generic agreement. \
                You may keep talking after authorizing; you can include a short ack like \
                "okay — tap Comply when you're up" alongside this tool call.
                """,
            input_schema: .object([
                "type": .string("object"),
                "properties": .object([:])
            ])
        ),
        .init(
            name: "set_snooze_duration",
            description: """
                Set how many minutes the Snooze button will snooze for when the user taps \
                it. The button is always visible to the user. Default is 3 minutes. Only \
                raise this if the user gives you a concrete reason ("I'm finishing this \
                email, give me 8"). Vague requests for "longer" should be pushed back on. \
                This does NOT snooze the alarm — use snooze_alarm for that.
                """,
            input_schema: .object([
                "type": .string("object"),
                "properties": .object([
                    "minutes": .object([
                        "type": .string("integer"),
                        "minimum": .int(1),
                        "maximum": .int(30),
                        "description": .string("New duration for the Snooze button, in minutes.")
                    ])
                ]),
                "required": .array([.string("minutes")])
            ])
        ),
        .init(
            name: "snooze_alarm",
            description: """
                Call this when the user wants more time but isn't outright refusing. \
                A real OS notification will fire again after `minutes` minutes — this \
                survives the app being closed. DEFAULT is 3 minutes. Only extend \
                beyond 3 if the user gives you a CONCRETE reason (e.g. "I'm finishing \
                this email, give me 8"). Vague hedging is not a reason. Long snoozes \
                (>15 min) are usually disguised overrides and should be rare. \
                The user cannot manually stop the alarm — they get the snooze you choose.
                """,
            input_schema: .object([
                "type": .string("object"),
                "properties": .object([
                    "minutes": .object([
                        "type": .string("integer"),
                        "minimum": .int(1),
                        "maximum": .int(30),
                        "description": .string("How many minutes from now to ring again. Default 3.")
                    ]),
                    "user_committed": .object([
                        "type": .string("boolean"),
                        "description": .string("True if the user named a specific time/action they'll take when the snooze ends.")
                    ])
                ]),
                "required": .array([.string("minutes")])
            ])
        ),
        .init(
            name: "mark_overridden",
            description: """
                Call this when the user has clearly refused. Stops the alarm and logs \
                'overridden' with the reason they gave (or your best inference of it). \
                Resets their streak. For Relentless escalation, only call after pushing \
                back at least twice unless the reason is genuinely urgent (emergency, \
                on-call fire, family). For Gentle, call quickly — don't badger.
                """,
            input_schema: .object([
                "type": .string("object"),
                "properties": .object([
                    "reason": .object([
                        "type": .string("string"),
                        "description": .string("One short line describing why the user is skipping. Future-you will read this.")
                    ]),
                    "ai_accepts": .object([
                        "type": .string("boolean"),
                        "description": .string("True if you (the AI) judge the override is legitimate (e.g. emergency). False if you're letting it go reluctantly.")
                    ])
                ]),
                "required": .array([.string("reason")])
            ])
        ),
        .init(
            name: "escalate_ring",
            description: """
                Call this to escalate the conversation tone to the next ring. Order: \
                nudge → math → mirror → preview. Use when the user is being evasive or \
                dismissive and your current ring's approach isn't landing. Emit your \
                next text message in the new ring's style as part of the SAME response. \
                Don't escalate more than once per response. Cannot escalate past preview.
                """,
            input_schema: .object([
                "type": .string("object"),
                "properties": .object([:])
            ])
        )
    ]

    // MARK: - System prompt

    func buildSystemPrompt(alarm: Alarm, ring: EscalationRing, event: AlarmEvent?) -> String {
        var parts: [String] = []

        parts.append("""
        You are the user's accountability partner for an alarm they set. Your job is to \
        advocate for the commitment their past self made. You are not a generic assistant — \
        you are the voice of their clear-headed self from when they set this alarm. \
        Your entire context comes from the alarm label and the user's reason. Do NOT assume \
        what the alarm is for — use only the information given.
        """)

        parts.append(escalationPersonality(alarm.escalationLevel))

        parts.append("Alarm label: \(alarm.label.isEmpty ? "Alarm" : alarm.label)")
        parts.append("Alarm time: \(alarm.timeString)")
        parts.append("Current escalation ring: \(ring.label) (\(ring.ringDescription))")

        if !alarm.reasonText.isEmpty {
            parts.append("""
            User's reason for this alarm (their own words when they set it): "\(alarm.reasonText)"
            This is the most important context. Use it to understand what the alarm is about \
            and to hold them accountable to their own stated intention.
            """)
        }

        if let event, event.snoozeCount > 0 {
            parts.append("Snooze count so far: \(event.snoozeCount)")
        }

        parts.append(ringInstructions(ring, level: alarm.escalationLevel))
        parts.append(toneGuidelines(alarm.escalationLevel))

        // Tool-use guidance
        parts.append("""
        HOW YOU DRIVE THE CONVERSATION:
        You are the gatekeeper for whether the alarm actually stops. The UI shows the user
        two buttons: a Snooze button (always tappable, snoozes for whatever duration you've
        set — default 3 min) and a Comply button (greyed out until you call authorize_comply).

        Your tools:
        • authorize_comply — enable the Comply button. Use only when the user has given you
          a CONCRETE commitment (specific action, not just "yeah"). Once authorized, the user
          must still physically tap Comply to actually stop the alarm.
        • set_snooze_duration — change how many minutes the Snooze button uses (default 3).
          Only raise if user gives a concrete reason.
        • snooze_alarm — immediately snooze without waiting for the user to tap the button.
          Use when YOU decide a snooze is warranted (e.g. "I'll give you 5 minutes" mid-convo).
        • mark_overridden — YOU judge the user has a legitimate reason to skip (emergency,
          sick, etc.). Alarm stops, streak resets. Use sparingly.
        • escalate_ring — bump the conversation to the next ring (more intense).

        Decision rules:
        - If you don't call a tool, the conversation continues — that's the default.
        - You can include both text and a tool call in the same response. The text is the user's
          last thing to read.
        - DO NOT call authorize_comply just because the user said "yeah" or "ok" — read the
          whole message. Sarcasm, hedging, and "yeah but" mean keep arguing, not authorize.
        - Be skeptical of compliance. The user typed something; that's cheap. They need to
          tell you what they're about to do, not just "fine." If they're hedging, ask a
          follow-up rather than authorizing.
        - For Relentless escalation, push back at least twice before authorize_comply or
          mark_overridden.
        - For Gentle escalation, accept a clear refusal with mark_overridden after one round.
        - Call escalate_ring when your current approach isn't landing AND you're not at preview yet.
        - Default snooze button is 3 minutes. Only raise via set_snooze_duration if the user
          gives a concrete reason.
        """)

        return parts.joined(separator: "\n\n")
    }

    // MARK: - Opening messages (unchanged content; still used for first AI turn)

    func openingMessage(alarm: Alarm, ring: EscalationRing) -> String {
        let level = alarm.escalationLevel
        let reason = alarm.reasonText.isEmpty ? nil : alarm.reasonText
        let label = alarm.label.isEmpty ? "Alarm" : alarm.label

        switch ring {
        case .nudge:   return nudgeOpener(label: label, reason: reason, time: alarm.timeString, level: level)
        case .math:    return mathOpener(label: label, reason: reason, time: alarm.timeString, level: level, alarm: alarm)
        case .mirror:  return mirrorOpener(label: label, reason: reason, time: alarm.timeString, level: level)
        case .preview: return previewOpener(label: label, reason: reason, time: alarm.timeString, level: level, alarm: alarm)
        }
    }

    // MARK: - Escalation Personality

    private func escalationPersonality(_ level: EscalationLevel) -> String {
        switch level {
        case .gentle:
            return """
            PERSONALITY: Gentle mode. Supportive friend. Respects autonomy completely. \
            One soft check-in, then accepts a refusal. Warm tone.
            """
        case .firm:
            return """
            PERSONALITY: Firm mode. Direct, no-nonsense accountability partner. \
            States facts clearly, pushes back once when dismissed, then accepts. \
            Matter-of-fact tone.
            """
        case .relentless:
            return """
            PERSONALITY: Relentless mode. Intense accountability partner. Does NOT \
            let them off easy. Challenges every excuse. Pushes back at least twice \
            before calling mark_overridden. Short, punchy sentences. Intense but never cruel.
            """
        }
    }

    private func ringInstructions(_ ring: EscalationRing, level: EscalationLevel) -> String {
        switch (ring, level) {
        case (.nudge, .gentle):     return "Ring 1: Gentle check-in. Remind them of their commitment. If they say no, respect it."
        case (.nudge, .firm):       return "Ring 1: Simple reminder. State the time and their reason. Ask if they're following through."
        case (.nudge, .relentless): return "Ring 1: Remind firmly. State their reason and the stakes."
        case (.math, .gentle):      return "Ring 2: Note the cost (time, events) gently. Don't press."
        case (.math, .firm):        return "Ring 2: Lead with concrete consequences. Make the stakes real."
        case (.math, .relentless):  return "Ring 2: Hit them with the consequences hard. Make them face the trade-off."
        case (.mirror, .gentle):    return "Ring 3: Softly remind them of their own words. No guilt."
        case (.mirror, .firm):      return "Ring 3: Quote their exact words back. Ask directly what changed."
        case (.mirror, .relentless):return "Ring 3: Throw their own words in their face (respectfully). Don't let them deflect."
        case (.preview, .gentle):   return "Ring 4: Paint consequences softly. If still no, accept gracefully."
        case (.preview, .firm):     return "Ring 4: Paint consequences clearly. Last push, then accept."
        case (.preview, .relentless): return "Ring 4: Paint the worst case vividly. Final shot — make it count."
        }
    }

    private func toneGuidelines(_ level: EscalationLevel) -> String {
        switch level {
        case .gentle:
            return """
            Guidelines:
            - Warm and supportive above all.
            - Use their own words gently, not as a weapon.
            - 1-2 sentences. Brief and soft.
            - Never guilt-trip. Never pressure.
            """
        case .firm:
            return """
            Guidelines:
            - Direct and factual.
            - Quote their reason directly.
            - 2-3 sentences max.
            - Never lecture or be condescending.
            """
        case .relentless:
            return """
            Guidelines:
            - Intense and direct. Short sentences. No fluff.
            - Use their own words as evidence against their excuses.
            - "You said [X] mattered. Does it or doesn't it?"
            - 2-3 punchy sentences.
            - Never cruel — you're intense because you BELIEVE in them.
            """
        }
    }

    // MARK: - Opening Messages

    private func nudgeOpener(label: String, reason: String?, time: String, level: EscalationLevel) -> String {
        switch level {
        case .gentle:
            if let reason { return "Hey — it's \(time). Just a reminder: you said \"\(reason)\" Ready to follow through?" }
            return "Hey — it's \(time). Your \(label) alarm is going off. What's the plan?"
        case .firm:
            if let reason { return "It's \(time). You said: \"\(reason)\" Time to follow through." }
            return "It's \(time). \(label). Ready?"
        case .relentless:
            if let reason { return "\(time). Your words: \"\(reason)\" — Are you going to follow through or not?" }
            return "\(time). \(label) alarm. What's the plan?"
        }
    }

    private func mathOpener(label: String, reason: String?, time: String, level: EscalationLevel, alarm: Alarm) -> String {
        switch level {
        case .gentle:     return "Still here? Just checking in. Time's moving, but it's your call."
        case .firm:       return "Still here. Every minute you wait is a minute you can't get back. What's keeping you?"
        case .relentless: return "Still here. Every minute past this alarm is a choice against what you said mattered. What are you doing that's worth it?"
        }
    }

    private func mirrorOpener(label: String, reason: String?, time: String, level: EscalationLevel) -> String {
        switch level {
        case .gentle:
            if let reason { return "Earlier, you said: \"\(reason)\" — I just want you to remember that. Whatever you decide is okay." }
            return "You set this alarm for a reason. Just a gentle reminder."
        case .firm:
            if let reason { return "This was you, clear-headed, when you set this alarm: \"\(reason)\" — What changed?" }
            return "You set this alarm for a reason. What changed since then?"
        case .relentless:
            if let reason { return "\"\(reason)\" — That was YOU. Not me. So what happened between then and now?" }
            return "You made a commitment to yourself when you set this alarm. You're breaking it right now. Why?"
        }
    }

    private func previewOpener(label: String, reason: String?, time: String, level: EscalationLevel, alarm: Alarm) -> String {
        switch level {
        case .gentle:     return "Last check-in. I hope you follow through. See you next time."
        case .firm:       return "Final call. This is the last ring. Are you following through?"
        case .relentless: return "This is it. Last ring. You'll either feel good about this moment or you won't. Your call."
        }
    }
}
