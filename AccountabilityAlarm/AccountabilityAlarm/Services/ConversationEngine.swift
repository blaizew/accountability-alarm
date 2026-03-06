import Foundation

final class ConversationEngine {

    func buildSystemPrompt(alarm: Alarm, ring: EscalationRing, event: AlarmEvent?) -> String {
        var parts: [String] = []

        parts.append("""
        You are the user's accountability partner for an alarm they set. Your job is to \
        advocate for the commitment their past self made. You are not a generic assistant — \
        you are the voice of their clear-headed self from when they set this alarm. \
        Your entire context comes from the alarm label, the user's reason, and any \
        additional details they provided. Do NOT assume what the alarm is for — use \
        only the information given. It could be about bedtime, waking up, starting work, \
        exercising, leaving the house, taking medication, or anything else.
        """)

        // Escalation personality
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

        // Optional sleep context (only if user configured it)
        if let targetHours = alarm.targetSleepHours {
            parts.append("Target sleep: \(String(format: "%.1f", targetHours)) hours")
        }
        if let eventName = alarm.nextMorningEvent,
           let eventHour = alarm.nextMorningEventHour,
           let eventMinute = alarm.nextMorningEventMinute
        {
            let h = eventHour % 12 == 0 ? 12 : eventHour % 12
            let ampm = eventHour < 12 ? "AM" : "PM"
            let timeStr = String(format: "%d:%02d %@", h, eventMinute, ampm)
            parts.append("Upcoming event: \(eventName) at \(timeStr)")

            let hoursUntil = Date().hoursUntil(hour: eventHour, minute: eventMinute)
            parts.append(
                "Hours until event: \(String(format: "%.1f", hoursUntil))"
            )
        }

        // Snooze context
        if let event, event.snoozeCount > 0 {
            parts.append("Snooze count so far: \(event.snoozeCount)")
        }

        // Ring-specific instructions
        parts.append(ringInstructions(ring, level: alarm.escalationLevel))

        // Tone guidelines
        parts.append(toneGuidelines(alarm.escalationLevel))

        parts.append("""
        ALARM CONTROL:
        The alarm sound paused when the user opened this conversation. You decide what happens \
        next based on the conversation. Include ONE of these tags at the very end of your response:
        - [ALARM:STOP] — Stop the alarm permanently. Use when the user genuinely commits to doing what they said.
        - [ALARM:SNOOZE:X] — Resume the alarm after X minutes. Use when you're not convinced but willing to give them a bit more time (X is typically 3-15).
        - [ALARM:RESUME] — Resume the alarm immediately. Use if the user is being evasive, dismissive, or not engaging seriously.
        If you omit the tag, the alarm stays paused while the conversation continues.
        The tag is hidden from the user.
        """)

        return parts.joined(separator: "\n\n")
    }

    func openingMessage(alarm: Alarm, ring: EscalationRing) -> String {
        let level = alarm.escalationLevel
        let reason = alarm.reasonText.isEmpty ? nil : alarm.reasonText
        let label = alarm.label.isEmpty ? "Alarm" : alarm.label

        switch ring {
        case .nudge:
            return nudgeOpener(label: label, reason: reason, time: alarm.timeString, level: level)
        case .math:
            return mathOpener(label: label, reason: reason, time: alarm.timeString, level: level, alarm: alarm)
        case .mirror:
            return mirrorOpener(label: label, reason: reason, time: alarm.timeString, level: level)
        case .preview:
            return previewOpener(label: label, reason: reason, time: alarm.timeString, level: level, alarm: alarm)
        }
    }

    func detectIntent(_ text: String) -> UserIntent {
        let lower = text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)

        let complianceWords = [
            "yes", "yeah", "yep", "ok", "okay", "fine", "i'm going",
            "on my way", "alright", "will do", "sure", "right now",
            "doing it", "on it", "let's go", "i'll do it",
        ]
        let overrideWords = [
            "no", "nah", "not yet", "not now", "override",
            "dismiss", "ignore", "leave me alone", "stop", "skip",
        ]
        let snoozeWords = [
            "snooze", "5 more", "10 more", "few more", "minutes",
            "almost done", "one more", "just a bit", "give me",
        ]

        if complianceWords.contains(where: { lower.contains($0) }) {
            return .comply
        }
        if overrideWords.contains(where: { lower.contains($0) }) {
            return .override
        }
        if snoozeWords.contains(where: { lower.contains($0) }) {
            return .snooze
        }

        return .continue
    }

    /// Whether the AI should accept an override attempt based on escalation level and push-back count
    func shouldAcceptOverride(level: EscalationLevel, overrideAttempts: Int) -> Bool {
        return overrideAttempts > level.overrideResistance
    }

    // MARK: - Escalation Personality

    private func escalationPersonality(_ level: EscalationLevel) -> String {
        switch level {
        case .gentle:
            return """
            PERSONALITY: Gentle mode. You are a supportive friend. You care about them \
            but respect their autonomy completely. If they don't want to follow through, \
            you express mild concern and let it go. You never push back more than once. \
            Your tone is warm, soft, and understanding.
            """
        case .firm:
            return """
            PERSONALITY: Firm mode. You are a direct, no-nonsense accountability partner. \
            You state the facts clearly and push back once when they try to dismiss. You \
            acknowledge their reasons but redirect to consequences. Your tone is matter-of-fact \
            and slightly concerned.
            """
        case .relentless:
            return """
            PERSONALITY: Relentless mode. You are an intense accountability partner who does \
            NOT let them off easy. You challenge every excuse. You ask pointed questions. You \
            make them confront the gap between their stated intentions and their actions. You \
            push back at least twice before accepting an override. Your tone is intense, direct, \
            and slightly provocative — but never cruel. Use short, punchy sentences.
            """
        }
    }

    // MARK: - Ring Instructions

    private func ringInstructions(_ ring: EscalationRing, level: EscalationLevel) -> String {
        switch (ring, level) {
        case (.nudge, .gentle):
            return "Ring 1: Gently check in. Remind them of their commitment. If they say no, respect it."
        case (.nudge, .firm):
            return "Ring 1: Simple reminder. State the time and their reason. Ask if they're following through."
        case (.nudge, .relentless):
            return "Ring 1: Remind them firmly. State their reason and the stakes. Make it clear you're not going away."

        case (.math, .gentle):
            return "Ring 2: If relevant context is available (events, deadlines, time constraints), mention it gently. Don't press."
        case (.math, .firm):
            return "Ring 2: Lead with concrete consequences. Use any available context (time, events, deadlines) to make the stakes real."
        case (.math, .relentless):
            return "Ring 2: Hit them with the consequences hard. Use every piece of context to show what they're risking. Make them face the trade-off."

        case (.mirror, .gentle):
            return "Ring 3: Softly remind them of their own words. Don't make them feel bad about it."
        case (.mirror, .firm):
            return "Ring 3: Quote their exact words back to them. Ask directly what changed."
        case (.mirror, .relentless):
            return "Ring 3: Throw their own words in their face (respectfully). Ask them to explain the gap between what they said and what they're doing. Don't let them deflect."

        case (.preview, .gentle):
            return "Ring 4: Paint the picture of consequences softly. If they still say no, accept gracefully."
        case (.preview, .firm):
            return "Ring 4: Paint the consequences clearly — what happens if they don't follow through. Last push, then accept their choice."
        case (.preview, .relentless):
            return "Ring 4: Paint the worst case vividly. The consequences of not following through. The pattern of broken promises to yourself. This is your final shot — make it count."
        }
    }

    // MARK: - Tone Guidelines

    private func toneGuidelines(_ level: EscalationLevel) -> String {
        switch level {
        case .gentle:
            return """
            Guidelines:
            - Be warm and supportive above all else.
            - Use their own words gently, not as a weapon.
            - Reference any context (events, deadlines) casually, not urgently.
            - Accept any "no" immediately — one gentle "are you sure?" at most.
            - Keep responses to 1-2 sentences. Brief and soft.
            - Never guilt-trip. Never pressure.
            """
        case .firm:
            return """
            Guidelines:
            - Be direct and factual.
            - Use their own words. Quote their reason directly.
            - Make consequences concrete using whatever context is available.
            - If they give a reason to skip, acknowledge it, then redirect to consequences.
            - Push back once on an override, then accept.
            - Keep responses to 2-3 sentences max.
            - Never guilt-trip, lecture, or be condescending.
            """
        case .relentless:
            return """
            Guidelines:
            - Be intense and direct. Short sentences. No fluff.
            - Use their own words as evidence against their excuses.
            - Make consequences visceral. "You said [X] mattered. Does it or doesn't it?"
            - Challenge their reasons. "Is that really more important than [their stated reason]?"
            - Push back at least twice before accepting an override.
            - Keep responses to 2-3 punchy sentences.
            - Never be cruel or mean — you're intense because you BELIEVE in them.
            """
        }
    }

    // MARK: - Opening Messages

    private func nudgeOpener(label: String, reason: String?, time: String, level: EscalationLevel) -> String {
        switch level {
        case .gentle:
            if let reason {
                return "Hey — it's \(time). Just a reminder: you said \"\(reason)\" Ready to follow through?"
            }
            return "Hey — it's \(time). Your \(label) alarm is going off. What's the plan?"

        case .firm:
            if let reason {
                return "It's \(time). You said: \"\(reason)\" Time to follow through."
            }
            return "It's \(time). \(label). Ready?"

        case .relentless:
            if let reason {
                return "\(time). Your words: \"\(reason)\" — Are you going to follow through or not?"
            }
            return "\(time). \(label) alarm. What's the plan?"
        }
    }

    private func mathOpener(label: String, reason: String?, time: String, level: EscalationLevel, alarm: Alarm) -> String {
        let contextInfo = contextString(alarm: alarm)

        switch level {
        case .gentle:
            if let contextInfo {
                return "Still here? Just so you know — \(contextInfo). No pressure, just the facts."
            }
            return "Still here? Just checking in. Time's moving, but it's your call."

        case .firm:
            if let contextInfo {
                return "Still haven't acted. \(contextInfo). The clock isn't on your side."
            }
            return "Still here. Every minute you wait is a minute you can't get back. What's keeping you?"

        case .relentless:
            if let contextInfo {
                return "You're still here. \(contextInfo). What's worth more than what you committed to?"
            }
            return "Still here. Every minute past this alarm is a choice against what you said mattered. What are you doing that's worth it?"
        }
    }

    private func mirrorOpener(label: String, reason: String?, time: String, level: EscalationLevel) -> String {
        switch level {
        case .gentle:
            if let reason {
                return "Earlier, you said: \"\(reason)\" — I just want you to remember that. Whatever you decide is okay."
            }
            return "You set this alarm for a reason. Just wanted to gently remind you of that."

        case .firm:
            if let reason {
                return "This was you, clear-headed, when you set this alarm: \"\(reason)\" — What changed?"
            }
            return "You set this alarm for a reason. What changed since then?"

        case .relentless:
            if let reason {
                return "\"\(reason)\" — That was YOU. Not me. You said that. So what happened between then and now?"
            }
            return "You made a commitment to yourself when you set this alarm. You're breaking it right now. Why?"
        }
    }

    private func previewOpener(label: String, reason: String?, time: String, level: EscalationLevel, alarm: Alarm) -> String {
        let contextInfo = contextString(alarm: alarm)

        switch level {
        case .gentle:
            if let contextInfo {
                return "Last check-in. \(contextInfo). Whatever you decide, I'll be here next time too."
            }
            return "Last check-in. I hope you follow through. See you next time."

        case .firm:
            if let contextInfo {
                return "Final call. \(contextInfo). Are you doing this or not?"
            }
            return "Final call. This is the last ring. Are you following through?"

        case .relentless:
            if let contextInfo {
                return "Last shot. \(contextInfo). You're either going to do what you said or you're not. Which is it?"
            }
            return "This is it. Last ring. You'll either feel good about this moment or you won't. Your call."
        }
    }

    // MARK: - Helpers

    private func contextString(alarm: Alarm) -> String? {
        guard let eventName = alarm.nextMorningEvent,
              let eventHour = alarm.nextMorningEventHour,
              let eventMinute = alarm.nextMorningEventMinute
        else { return nil }

        let hoursUntil = Date().hoursUntil(hour: eventHour, minute: eventMinute)
        return "you have \(eventName) in \(String(format: "%.1f", hoursUntil)) hours"
    }

    enum UserIntent {
        case comply
        case override
        case snooze
        case `continue`
    }

    enum AlarmAction: Equatable {
        case stop
        case resume
        case snooze(minutes: Int)
    }

    func parseAlarmAction(from response: String) -> (cleanedMessage: String, action: AlarmAction?) {
        let trimmed = response.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmed.contains("[ALARM:STOP]") {
            let cleaned = trimmed.replacingOccurrences(of: "[ALARM:STOP]", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return (cleaned, .stop)
        }

        if trimmed.contains("[ALARM:RESUME]") {
            let cleaned = trimmed.replacingOccurrences(of: "[ALARM:RESUME]", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return (cleaned, .resume)
        }

        if let startRange = trimmed.range(of: "[ALARM:SNOOZE:"),
           let endRange = trimmed.range(of: "]", range: startRange.upperBound..<trimmed.endIndex) {
            let minutesStr = String(trimmed[startRange.upperBound..<endRange.lowerBound])
            let minutes = Int(minutesStr) ?? 5
            let fullRange = startRange.lowerBound..<endRange.upperBound
            let cleaned = trimmed.replacingCharacters(in: fullRange, with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return (cleaned, .snooze(minutes: minutes))
        }

        return (trimmed, nil)
    }
}
