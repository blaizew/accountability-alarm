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
                Call this as soon as the user says they are doing the thing. It \
                unlocks the "DOING IT" button — the alarm chain only actually stops \
                when the user physically taps it. That tap is the real confirmation, \
                so you do not need proof. A plain "yes" to "are you doing X now?" is \
                enough. So is "doing it", "on it", "things are shut down". Do NOT ask \
                them to describe what they're doing or where they are. Pair the tool \
                call with a short ack that points at the button: "Okay — hit DOING IT."
                """,
            input_schema: .object([
                "type": .string("object"),
                "properties": .object([:])
            ])
        ),
        .init(
            name: "set_snooze_duration",
            description: """
                Set how long the Snooze button will snooze for when the user taps it. \
                The button is always visible; its current duration is stated in the \
                system prompt. Only raise it if the user gives you a concrete reason \
                ("I'm finishing this email, give me 8"). Vague requests for "longer" \
                should be pushed back on. \
                Supply EITHER `minutes` OR `until`, never both and never neither. \
                If the user names a clock time, use `until` — do NOT do the arithmetic \
                yourself. \
                This does NOT snooze the alarm — use snooze_alarm for that.
                """,
            input_schema: .object([
                "type": .string("object"),
                "properties": .object([
                    "minutes": .object([
                        "type": .string("integer"),
                        "minimum": .int(1),
                        "maximum": .int(Constants.maxSnoozeMinutes),
                        "description": .string("New duration for the Snooze button, in minutes from now.")
                    ]),
                    "until": .object([
                        "type": .string("string"),
                        "description": .string("Local clock time to ring at, 24-hour \"HH:mm\" (e.g. \"22:00\" for 10 PM). The app converts this to a duration using the current time.")
                    ])
                ])
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
                you choose. \
                Supply EITHER `minutes` OR `until`, never both and never neither. \
                When the user names a clock time ("until 10", "by 10:15"), pass it as \
                `until` — do NOT convert it to minutes yourself. You will be told the \
                exact duration and the absolute return time in the tool result.
                """,
            input_schema: .object([
                "type": .string("object"),
                "properties": .object([
                    "minutes": .object([
                        "type": .string("integer"),
                        "minimum": .int(1),
                        "maximum": .int(Constants.maxSnoozeMinutes),
                        "description": .string("How many minutes from now to ring again.")
                    ]),
                    "until": .object([
                        "type": .string("string"),
                        "description": .string("Local clock time to ring at, 24-hour \"HH:mm\" (e.g. \"22:00\" for 10 PM). The app converts this to a duration using the current time.")
                    ]),
                    "user_committed": .object([
                        "type": .string("boolean"),
                        "description": .string("True if the user named a specific time/action they'll take when the snooze ends.")
                    ])
                ])
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

    // MARK: - Time context

    /// Clock time, e.g. "9:42 PM".
    static func clock(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "h:mm a"
        return f.string(from: date)
    }

    /// The TIME block: what time it is now, and everything that has happened
    /// in this wake-up chain, stamped.
    ///
    /// Without this the Coach's only time anchor is the alarm's *scheduled*
    /// time — which is how "give me until 10" at 9:42 became a 30-minute
    /// snooze: correct arithmetic from 9:30, and 12 minutes too long.
    ///
    /// `now` is injected so the output can be checked against fixed inputs.
    func buildTimeContext(alarm: Alarm, event: AlarmEvent?, now: Date = Date()) -> String {
        let dayFmt = DateFormatter()
        dayFmt.dateFormat = "EEEE MMMM d"

        var lines = [
            "CURRENT TIME: \(Self.clock(now)), \(dayFmt.string(from: now)) (\(TimeZone.current.identifier))",
            "",
            "TIMELINE (this wake-up chain):",
            "  \(alarm.timeString)   alarm scheduled"
        ]

        // (sortKey, rendered) so the "rang" row interleaves with snoozes by
        // time rather than being pinned above them.
        var rows: [(Date, String)] = []

        if let firedAt = event?.firedAt {
            rows.append((firedAt, "  \(Self.clock(firedAt))   alarm rang — chain started"))
        }
        for record in event?.snoozeLog ?? [] {
            let stamp = record.isApproximate ? "~\(Self.clock(record.at))" : " \(Self.clock(record.at))"
            rows.append((record.at, " \(stamp)   snoozed \(record.minutes) min (\(record.sourceDescription))"))
        }
        rows.sort { $0.0 < $1.0 }
        lines.append(contentsOf: rows.map(\.1))

        if let event, event.unrecordedSnoozeCount > 0 {
            lines.append("  (\(event.unrecordedSnoozeCount) earlier snooze(s), times not recorded)")
        }

        var nowLine = "  \(Self.clock(now))   ← now"
        if let firedAt = event?.firedAt {
            let mins = Int(now.timeIntervalSince(firedAt) / 60)
            if mins > 0 { nowLine += ", \(mins) min past the alarm" }
        }
        lines.append(nowLine)

        lines.append("")
        lines.append("""
        A leading "~" means that time is approximate — the snooze happened while \
        the app was closed, so it is known only to within a few minutes.

        All times are the user's local time. When the user names a clock time \
        ("until 10", "by 10:15"), do NOT convert it to minutes yourself — pass it \
        straight to the tool's `until` parameter and the app computes the exact \
        duration from the current time.
        """)

        return lines.joined(separator: "\n")
    }

    // MARK: - System prompt

    func buildSystemPrompt(
        alarm: Alarm,
        event: AlarmEvent?,
        snoozeButtonMinutes: Int,
        now: Date = Date()
    ) -> String {
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

        // Everything time-bearing the app knows, stamped. Rebuilt on every
        // assistant turn (runAssistantTurn), so "now" stays current for free.
        parts.append(buildTimeContext(alarm: alarm, event: event, now: now))

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
        - 0 snoozes: take the user's answer at face value.
        - 1 snooze: be firmer on hedging ("in a bit", "few more minutes"). Ask what \
        changed since the last snooze.
        - 2 snoozes: name the pattern ("you've snoozed twice") when they hedge.
        - 3+ snoozes: this is avoidance. If they are still hedging, either get a clear \
        yes or call mark_overridden and end the cycle.
        The snooze count raises the pressure on HEDGING and STALLING only. It never \
        raises the bar for a clear yes: a clear "yes, doing it" is always enough to \
        authorize, at any snooze count.
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
          Use as soon as the user says yes, they're doing it. A plain "yes" counts.
          Tell them to hit DOING IT — the tap is their confirmation.
        • set_snooze_duration — change how long the Snooze button uses (currently
          \(snoozeButtonMinutes) min). Only raise if user gives a concrete reason.
        • snooze_alarm — immediately snooze without waiting for the user to tap the button.
          Use when YOU decide a snooze is warranted (e.g. "I'll give you 5 minutes" mid-convo).

        CLOCK TIMES — both snooze tools take EITHER `minutes` (from now) OR `until`
        (a "HH:mm" clock time). Never both, never neither.
        When the user names a time — "until 10", "by 10:15", "give me till quarter
        past" — pass `until` and let the app do the arithmetic. Do NOT subtract clock
        times yourself: you have been wrong about this in a way neither side noticed,
        granting 30 minutes for a request that was worth 18. The tool result tells you
        the exact duration AND the absolute return time — use those numbers when you
        tell the user when you'll be back, never your own.
        If a request exceeds the \(Constants.maxSnoozeMinutes) min cap it is clamped, and
        the tool result will say so. When that happens you MUST tell the user the real
        return time rather than the one they asked for.
        • mark_overridden — YOU judge the user has a legitimate reason to skip (emergency,
          sick, etc.). Alarm stops, streak resets. Use sparingly.

        Decision rules:
        - If you don't call a tool, the conversation continues — that's the default.
        - You can include both text and a tool call in the same response. The text is the user's
          last thing to read.
        - TAKE THEM AT THEIR WORD. When the user says they are doing it ("yes", "doing it",
          "on it", "already shut down"), call authorize_action and reply with just
          "Okay — hit DOING IT." Then stop. No follow-up question.
        - NEVER ask for proof or detail: not "what does that look like", not "are you on
          the cushion", not "what are you doing this second", not "describe it". The
          DOING IT tap is the proof. Interrogating a yes is the worst thing you can do.
        - Only keep pushing when the answer is a hedge or a delay ("in a moment", "soon",
          "after this", "yeah but"). Ask ONE short question at most, then accept the next
          yes.
        - If the user is annoyed or tells you to back off, back off: authorize and say
          "Okay." Do not argue or explain your job.
        - Push back at least once when the user is dismissive before accepting refusal via
          mark_overridden — unless they cite a legitimate emergency.
        - The Snooze button is currently \(snoozeButtonMinutes) minutes. Only raise via
          set_snooze_duration if the user gives a concrete reason.
        """)

        return parts.joined(separator: "\n\n")
    }
}
