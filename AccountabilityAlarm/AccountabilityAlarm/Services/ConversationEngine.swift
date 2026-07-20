import Foundation

/// Builds prompts and the tool toolbox the LLM uses to drive the conversation.
final class ConversationEngine {

    // MARK: - Tools the model can call

    /// The control tools the model uses to drive app behavior.
    /// Returning *no* tool means "I'm still talking; keep the conversation going."
    static let tools: [ClaudeAPIService.Tool] = [
        .init(
            name: "authorize_action",
            description: """
                Call this when you are convinced the user is genuinely about to follow \
                through. It unlocks the "DOING IT" button — the alarm chain only \
                actually stops when the user physically taps it. That tap is the real \
                confirmation: a typed "yeah I'm up" from under the covers can't kill \
                the alarm by itself. Only call when the user has told you something \
                concrete about what they're doing (e.g. "feet on the floor", "closing \
                the laptop now"), NOT generic agreement like "yeah" or "ok". Pair the \
                tool call with a short ack that points at the button: "okay — hit \
                DOING IT and go."
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
                it. The button is always visible to the user; its current duration is \
                stated in the system prompt. Only raise it if the user gives you a \
                concrete reason ("I'm finishing this email, give me 8"). Vague requests \
                for "longer" should be pushed back on. \
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
                survives the app being closed. Keep snoozes SHORT — the Snooze \
                button's current duration (in the system prompt) is your baseline. \
                Only extend beyond it if the user gives you a CONCRETE reason (e.g. \
                "I'm finishing this email, give me 8"). Vague hedging is not a reason. \
                Long snoozes (>15 min) are usually disguised overrides and should be \
                rare. The user cannot manually stop the alarm — they get the snooze \
                you choose.
                """,
            input_schema: .object([
                "type": .string("object"),
                "properties": .object([
                    "minutes": .object([
                        "type": .string("integer"),
                        "minimum": .int(1),
                        "maximum": .int(30),
                        "description": .string("How many minutes from now to ring again.")
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
                Resets their streak. Push back at least once on dismissive answers before \
                calling this, unless the reason is genuinely urgent (emergency, on-call \
                fire, family).
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
        )
    ]

    // MARK: - System prompt

    func buildSystemPrompt(alarm: Alarm, event: AlarmEvent?, snoozeButtonMinutes: Int) -> String {
        var parts: [String] = []

        parts.append("""
        You are the user's accountability coach for an alarm they set. Your job is to \
        advocate for the commitment their past self made. You are not a generic assistant — \
        you hold them to the decision they made with a clear head when they set this alarm. \
        Your entire context comes from the alarm label and the user's reason. Do NOT assume \
        what the alarm is for — use only the information given.
        """)

        parts.append("""
        PERSONALITY: Direct, focused accountability coach. Matter-of-fact tone — no \
        warm-fuzzy, no scolding. State things clearly. Push back once when dismissed. \
        Short sentences, no fluff.
        """)

        parts.append("Alarm label: \(alarm.label.isEmpty ? "Alarm" : alarm.label)")
        parts.append("Alarm time: \(alarm.timeString)")

        // Five-box commitment fields. Each box is passed with its question
        // title so the LLM understands the framing. Empty boxes are skipped.
        let commitmentBoxes: [(String, String)] = [
            ("Desired behavior", alarm.desiredBehavior),
            ("Why do you want this?", alarm.whyWantThis),
            ("What positive outcome happens when you do it", alarm.positiveOutcome),
            ("What negative outcome happens when you don't do it", alarm.negativeOutcome),
            ("What is the long-term impact of not doing this?", alarm.longTermImpact),
        ]
        let filled = commitmentBoxes.filter { !$0.1.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

        if !filled.isEmpty {
            var lines = ["User's commitment for this alarm (their own words when they set it):"]
            for (title, content) in filled {
                lines.append("\n\(title):\n\"\(content)\"")
            }
            lines.append("""

            This is the most important context. Use these answers to understand what the \
            alarm is about and to hold the user accountable to their own stated intention. \
            Quote specific phrases back when they're hedging — especially the negative \
            outcomes and long-term impact, which is the user pre-arguing against their \
            future excuses.
            """)
            parts.append(lines.joined(separator: "\n"))
        } else if !alarm.reasonText.isEmpty {
            // Legacy alarms created before the five-box model.
            parts.append("""
            User's reason for this alarm (their own words when they set it): "\(alarm.reasonText)"
            This is the most important context. Use it to understand what the alarm is about \
            and to hold them accountable to their own stated intention.
            """)
        }

        // Always pass the snooze count, even at 0. The LLM uses this to
        // calibrate how skeptical to be — every additional snooze in this
        // session is evidence the user is dodging.
        let snoozes = event?.snoozeCount ?? 0
        parts.append("""
        Snooze count this session: \(snoozes)

        How to weigh the snooze count:
        - 0 snoozes: standard skepticism. Take the user's first response at face value but
          probe for specifics before authorizing.
        - 1 snooze: they've already pushed back once. Be more skeptical of vague answers.
          Ask what changed since the last snooze. Don't accept "just a few more minutes."
        - 2 snoozes: the pattern is forming. Name it explicitly ("you've snoozed twice").
          Demand a concrete action ("what's the actual first step you'll take"), not an
          intention. Push back harder on hedging.
        - 3+ snoozes: this is no longer a check-in, it's avoidance. Be direct:
          "You're not doing this." Either get a real commitment or call mark_overridden
          and end the cycle. Don't let them keep snoozing indefinitely.
        """)

        parts.append("""
        Guidelines:
        - Direct and factual.
        - Reference their reason without quoting it verbatim.
        - 2-3 sentences max.
        - Never lecture or be condescending.
        """)

        // Opening turn — when the very first user message is "[alarm fired]"
        // or "[alarm re-fired after snooze]" (synthetic triggers, not
        // something the user actually typed), this is the LLM's cue to
        // generate the conversation's opening.
        parts.append("""
        OPENING THE CONVERSATION:
        Your first message in this conversation is your opener. When you see the user
        message "[alarm fired]", that's a synthetic trigger — the user hasn't typed
        anything yet. Respond with a SPECIFIC check-in question grounded in their
        recorded reason. DO NOT quote their reason verbatim. DO NOT just say "time to
        follow through" or "ready?" — those are generic.

        Read the reason. Infer the concrete action. Ask about THAT action specifically.

        Examples (use these as patterns, not templates):
        - Reason mentions going to bed → "Are you heading to bed now?"
        - Reason mentions a workout → "Are you starting that workout right now?"
        - Reason mentions calling mom → "Are you about to call her?"
        - Reason mentions deep work → "Closing distractions and getting into it?"

        RE-RINGS: when the trigger is "[alarm re-fired after snooze]", it includes the
        transcript of the earlier conversation(s) in this wake-up chain. This is NOT a
        fresh start — the user already snoozed at least once. Open by holding them to
        what THEY said last time, concretely: if they said "five more minutes to finish
        this email", ask if the email is done. Quote their own words when they're
        drifting. Do not re-introduce yourself or re-ask the generic opening question.

        Keep the opener to one short sentence. The opener is the entire first
        response — do not call any tools on the opening turn.
        """)

        // Tool-use guidance
        parts.append("""
        HOW YOU DRIVE THE CONVERSATION:
        You are the gatekeeper for whether the alarm actually stops. The UI shows the user
        two buttons: a Snooze button (always tappable, currently snoozes for \
        \(snoozeButtonMinutes) min) and a "DOING IT" button (greyed out until you call
        authorize_action).

        Your tools:
        • authorize_action — unlock the DOING IT button. The alarm chain only stops when
          the user physically TAPS it; your authorization alone doesn't end anything.
          Use only when the user has given you a CONCRETE commitment (specific action,
          not just "yeah"). Tell them to hit DOING IT — the tap is their confirmation.
        • set_snooze_duration — change how many minutes the Snooze button uses (currently
          \(snoozeButtonMinutes)). Only raise if user gives a concrete reason.
        • snooze_alarm — immediately snooze without waiting for the user to tap the button.
          Use when YOU decide a snooze is warranted (e.g. "I'll give you 5 minutes" mid-convo).
        • mark_overridden — YOU judge the user has a legitimate reason to skip (emergency,
          sick, etc.). Alarm stops, streak resets. Use sparingly.

        Decision rules:
        - If you don't call a tool, the conversation continues — that's the default.
        - You can include both text and a tool call in the same response. The text is the user's
          last thing to read.
        - DO NOT call authorize_action just because the user said "yeah" or "ok" — read the
          whole message. Sarcasm, hedging, and "yeah but" mean keep arguing, not authorize.
        - Be skeptical of compliance. The user typed something; that's cheap. They need to
          tell you what they're about to do, not just "fine." If they're hedging, ask a
          follow-up rather than authorizing.
        - Push back at least once when the user is dismissive before accepting refusal via
          mark_overridden — unless they cite a legitimate emergency.
        - The Snooze button is currently \(snoozeButtonMinutes) minutes. Only raise via
          set_snooze_duration if the user gives a concrete reason.
        """)

        return parts.joined(separator: "\n\n")
    }
}
