# Accountability Alarm — Design Brief

A self-contained explainer for redesigning the interface and user experience. Paste this into claude.ai/design (or any design tool) as the project context.

---

## One-line pitch

An iOS alarm app where dismissing or snoozing triggers a brief AI conversation that plays your own past-self's reasoning back at you — making dismissal psychologically expensive rather than reflexive.

## The problem it solves

Standard alarms fail because dismissing them has zero psychological cost. You glance, swipe, and keep doing whatever you were doing. The app's bet is that alarms should be **conversational, not informational** — engaging you in *why* the alarm exists, not just signaling *that* it exists.

## Core insight

The AI is not a generic assistant. It is **the voice of your clear-headed past self** — the version of you who set the alarm with full reasoning. Its only argument is the user's own words.

## Principles (these should shape the visual & interaction language)

1. **Persuasive, not coercive.** The user can always dismiss. The app makes them engage first. It must never feel like a prison.
2. **Past-you is the advocate.** The product is the user arguing with themselves. The AI is a mirror, not an authority.
3. **Short interactions.** 30–60 seconds per exchange. 2–3 sentences per AI message. No walls of text. UI must feel light and finishable.
4. **Escalating intensity.** 4 rings (Nudge → Math → Mirror → Preview) get progressively more confrontational. The visual system should *feel* this escalation, not just label it.
5. **Voice-first, text fallback.** Default interaction is speaking out loud — the conversation often happens in bed, in the dark, mid-task. Text mode for when voice is impractical (partner sleeping, public).
6. **Data over moralizing.** "You'll get 5.2 hours" not "sleep is important." Numbers, not vibes.

---

## What the app is, structurally

A SwiftUI iOS app, MVVM + service layer, SwiftData for persistence, Claude Haiku for the conversations. Personal tool built by the author for himself, designed clean enough to ship later. Currently functional and being actively used.

### Primary surfaces (5 screens)

1. **Alarm List** — home tab. List of alarms with time, label, escalation style, repeat days, on/off toggle. Empty state when none exist. Plus button to add.
2. **Alarm Edit** — modal sheet. Time wheel picker, label field, repeat-day picker (S/M/T/W/T/F/S circles), the **"Why does this alarm matter?"** text + voice recording field, escalation style picker (Gentle/Firm/Relentless), optional sleep settings (target hours + morning event).
3. **Conversation** — full-screen modal that appears when an alarm fires and the user taps the notification. Ring indicator at top, chat transcript in the middle, input area at the bottom (text field OR mic button depending on mode), dismiss in nav bar.
4. **History** — second tab. Top: 3 stat cards (compliance %, avg snoozes, total). Below: reverse-chronological list of events with outcome icon, alarm label, date, snooze count.
5. **Morning Check-in** *(planned, model exists but UI doesn't)* — quick 1–10 energy rating post-wake. Feeds back into pattern data the AI cites later.

---

## Detailed screen breakdown

### Screen 1 — Alarm List

**Current state:** Standard iOS list. Each row shows time in 40pt rounded-light font, then a row of small secondary text (label · escalation icon+label · repeat description). Toggle on the right. Tap to edit, swipe to delete.

**Job to be done:** At a glance, see what alarms exist and whether they're on. Get to "add" or "edit" in one tap.

**Visual opportunity:** Currently feels indistinguishable from Apple's stock Clock app. Could communicate "these aren't just alarms, they're commitments" — surface the *reason* or escalation style more prominently. Consider showing the next firing time, or last outcome ("complied 3/5 last week"), or a stripe of color for escalation level.

### Screen 2 — Alarm Edit

**Current state:** Standard iOS Form with 5–7 sections stacked vertically: Time (wheel), Label, Repeat (day circles), **Why does this matter?** (multi-line text + voice record button + transcription indicator), Escalation Style (3 radio rows with icon + label + description), optional Sleep Settings toggle revealing Sleep Target hours + Morning Event name+time.

**Job to be done:** Capture intent fast. The "reason" field is the heart of the product — it's what the AI will quote back. Voice should feel as first-class as text, ideally more so.

**Visual opportunity:** The reason field is buried as one section among many. It should feel like the centerpiece. The escalation picker (3 modes with semantic icons — leaf/hand/flame) is a chance for personality. Day picker is currently flat circles — could be more expressive.

### Screen 3 — Conversation *(the most important screen)*

**Current state:** Standard chat UI. RingIndicator at top (4 small colored dots + ring name). LazyVStack of MessageBubbles (accent-colored bubbles right-aligned for user, gray left-aligned for AI). Bottom: voice/text mode toggle, then either a TextField with send button OR a big mic button. Dismiss button in nav bar.

**Critical context:**
- This screen appears in the middle of the night, in bed, in the dark, when the user is groggy or resistant. **High-contrast, low-strain, no-ceremony.**
- The alarm sound is *playing* in the background while this is happening (it pauses when the user opens the conversation; the AI can choose to resume it, snooze it, or stop it via hidden tags).
- The ring escalates over the conversation. Visual state should make the user *feel* the escalation — color temperature, weight, urgency.
- Voice mode is the default expectation. The mic should be inviting, the transcript should be readable from arm's length.
- The user might be one-handed, eyes-closed, half-asleep.

**Job to be done:** Make the user actually engage with the AI's argument, then route to one of three outcomes — **comply** (alarm stops), **snooze** (alarm resumes in N minutes), or **override** (alarm stops, logged as override).

**Visual opportunity:** This is where the entire product lives. It should not look like Messages. It should feel like a confrontation with yourself — intimate, focused, slightly uncomfortable. The 4 rings (Nudge → Math → Mirror → Preview) need a visual progression that the user feels in their chest, not just reads.

### Screen 4 — History

**Current state:** 3 stat cards across the top (compliance %, avg snoozes, total). Below, a list of events with outcome icon (green check / yellow / red / gray), alarm label, date, snooze count.

**Job to be done:** Show the pattern. Make the user see their own behavior over time. This is where reflection happens.

**Visual opportunity:** Currently a basic list. Could be a streak counter, a calendar heatmap, a chart of compliance over time, a "your top excuses" summary. The point is to make the user's pattern visible enough to be uncomfortable.

### Screen 5 — Morning Check-in *(planned)*

**Current state:** Doesn't exist in UI. `MorningCheckin` model exists (date, energyRating 1–10, sleepDurationEstimate, notes).

**Job to be done:** Capture how the user feels in the morning in under 5 seconds — so the AI can later say "Last time you stayed up this late, you rated 3/10." This is the feedback loop that gives the AI's arguments teeth.

**Visual opportunity:** Greenfield. Should feel fast, frictionless, almost reflexive. Big number tap, optional swipe for notes.

---

## Data model (simplified)

- **Alarm** — time, label, repeat days, reasonText, reasonAudioPath, optional targetSleepHours, optional nextMorningEvent (name + time), escalationLevel (gentle/firm/relentless), enabled, createdAt.
- **AlarmEvent** — alarm, firedAt, outcome (complied / snoozed_then_complied / overridden / ignored / pending), snoozeCount, overrideReason, conversationLog (array of messages), complianceTimeMinutes.
- **ConversationMessage** — role (user/assistant), content, timestamp.
- **MorningCheckin** — date, energyRating (1–10), sleepDurationEstimate, notes.

## Key enums

- **EscalationLevel** — gentle (leaf icon), firm (hand.raised), relentless (flame). Controls AI tone *and* how many times it pushes back before accepting an override.
- **EscalationRing** — nudge (0 min, "Gentle reminder"), math (+10 min, "Sleep math"), mirror (+20 min, "Your own words"), preview (+30 min, "Tomorrow preview"). Currently visualized as 4 colored dots: green / yellow / orange / red.

---

## Tone & voice (for any UI copy)

- Direct, calm, second-person. Never cute, never patronizing.
- Numbers over adjectives. "5.2 hours of sleep" not "not enough sleep."
- Uses *your own words* — copy should feel like it's quoting you, not lecturing you.
- Empty states and microcopy should land somewhere between Apple's restraint and a therapist's warmth.
- Avoid gamification language ("Great job!", "Streak!", "Achievement unlocked!") unless used very deliberately. The product is not a habit-tracker — it's a mirror.

## What this app is NOT

- Not a habit tracker. Not Streaks. Not Headspace. No badges, no points, no avatars.
- Not a wellness app. No pastel gradients, no "be kind to yourself" copy.
- Not Apple Clock. The stock clock is the *thing this is reacting against.*
- Not a chatbot toy. The AI is a means, not the product. The product is the user's relationship with their own commitments.

## Suggested aesthetic territory (open for exploration)

Not prescriptive — the redesign should explore these directions. Possible reference points:
- Editorial / serious-tool feel (Linear, Things 3, Reflect, Stoic) over consumer-app feel.
- Dark mode first — the conversation often happens in bed, in the dark.
- Restrained typography with one expressive display face for moments of emphasis (a quoted reason, the time, the ring name).
- Color used semantically — escalation rings should map to a real felt temperature shift across the conversation, not just hue swaps.
- Motion that feels considered, not decorative. The ring transitions and the moment the AI starts speaking are the two highest-leverage motion moments.

---

## Current pain points the redesign should address

1. **The product is invisible in the alarm list.** It looks like Apple Clock with extra metadata. A new user wouldn't understand what makes this different.
2. **The "reason" field is buried.** It's the heart of the product, sized like an afterthought.
3. **The conversation screen looks like Messages.** No sense of confrontation, escalation, or stakes. The ring indicator (4 dots) is too quiet given how much it should be telling the user.
4. **Voice mode feels secondary** even though it's the primary intended interaction. The mic appears only after toggling out of text mode.
5. **History is statistical, not reflective.** Numbers are correct but don't make you *feel* your patterns.
6. **No visual identity.** Uses iOS defaults end-to-end. The redesign is a chance to give the product a personality that matches its thesis.

## What must stay the same

- iOS native (SwiftUI). Whatever the redesign proposes must be buildable in SwiftUI without exotic dependencies.
- The 5-screen information architecture (List, Edit, Conversation, History, Morning Check-in) is sound. Don't restructure for its own sake.
- The 4-ring escalation model and the 3 escalation styles are core product mechanics. Visual language should support them, not replace them.
- Voice + text input both supported on the conversation screen.
- Accessibility: large-text-friendly, VoiceOver-friendly, usable one-handed in the dark.

---

## Asks for the redesign

Produce a coherent visual system covering all 5 screens, with particular care on the **Conversation** screen (highest-leverage surface) and the **Alarm Edit** screen (where intent gets captured). Show the 4-ring escalation as a felt progression. Treat the **reason field** as the product's centerpiece. Give the app an identity that signals "this is not Apple Clock" within the first second of opening it.
