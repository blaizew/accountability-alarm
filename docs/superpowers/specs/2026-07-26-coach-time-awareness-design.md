# Coach time awareness

**Date:** 2026-07-26
**Status:** approved, not yet implemented

## The incident

An alarm set for 9:30 PM rang. The user hit the system Stop button several
times, then opened the Coach at 9:42 PM and asked for "a few more minutes,
until 10." The Coach called `snooze_alarm` with 30 minutes.

30 was the right answer to the wrong question. The only time anchor in the
system prompt is the alarm's *scheduled* time — "9:30 PM" — so the model
computed 9:30 → 10:00. The user needed 18 minutes and got 30, and neither
party knew they disagreed.

## What the Coach currently knows about time

Almost nothing.

| Fact | Available? |
| --- | --- |
| Current wall-clock time | No |
| When the alarm actually rang (`AlarmEvent.firedAt`) | Stored, never sent |
| When each snooze was taken | Not stored at all — only a count |
| Timestamps on prior messages (`ConversationMessage.timestamp`) | Stored, stripped when the transcript is built |
| Alarm's scheduled time | Yes — the sole anchor |

`buildSystemPrompt` (`Services/ConversationEngine.swift:110`) passes
`alarm.timeString` and `Snooze count this session: N`. `reFireTrigger`
(`ViewModels/ConversationViewModel.swift:130`) renders prior messages as bare
`ROLE: content`, discarding the timestamp each message already carries.

## Goal

Every piece of time-bearing information the app already has reaches the Coach,
stamped — and clock-time arithmetic moves out of the model and into the app.

## Design

### 1. Timestamped snooze records

New value type:

```swift
struct SnoozeRecord: Codable, Sendable, Hashable {
    let at: Date
    let minutes: Int
    let source: Source

    enum Source: String, Codable, Sendable {
        case systemStop      // system Stop button, via SnoozeStopIntent
        case snoozeButton    // in-conversation Snooze button
        case coach           // the LLM's snooze_alarm tool
    }
}
```

`AlarmEvent` gains `snoozeLogData: Data?` with a computed `snoozeLog:
[SnoozeRecord]`, mirroring the existing `conversationLogData` /
`conversationLog` pattern.

Three sites currently do `snoozeCount += 1` by hand:

- `Intents/SnoozeStopIntent.swift:101` → `.systemStop`
- `ViewModels/ConversationViewModel.swift:190` (`resolveSnooze`) → `.snoozeButton`
- `ViewModels/ConversationViewModel.swift:379` (`snooze_alarm` dispatch) → `.coach`

All three route through a new `AlarmEvent.recordSnooze(minutes:source:)` that
increments the count *and* appends the record, so the two can't drift.

`snoozeCount` remains the authority for the skepticism ladder. Events already
stored on the device have counts but no records; they are not migrated. A
chain with `snoozeCount > snoozeLog.count` renders the unaccounted snoozes as a
single "(N earlier snoozes, times not recorded)" line rather than implying the
timeline is complete.

### 2. TIME block in the system prompt

New `buildTimeContext(alarm:event:now:)` on `ConversationEngine`, with `now`
injected (defaulting to `Date()`) so it is testable. Placed above the
snooze-count ladder:

```
CURRENT TIME: 9:42 PM, Saturday July 26 (America/Los_Angeles)

TIMELINE (this wake-up chain):
  9:30 PM   alarm scheduled
  9:31 PM   alarm rang — chain started
  9:33 PM   snoozed 5 min (system Stop button)
  9:36 PM   snoozed 3 min (system Stop button)
  9:39 PM   snoozed 3 min (system Stop button)
  9:42 PM   conversation opened  ← now, 12 min past the alarm

All times are the user's local time. When the user names a clock time
("until 10", "by 10:15"), do NOT convert it to minutes yourself — pass it
straight to the tool's `until` parameter and the app computes the duration.
```

`buildSystemPrompt` is already rebuilt on every assistant turn
(`ConversationViewModel.swift:264`), so "now" stays current for free.

**Precision caveat.** `event.firedAt` is set when the chain's `AlarmEvent` row
is created — the first Stop tap or the conversation opening — not the literal
ring instant. It is off by seconds to about a minute. The timeline labels it
"alarm rang" and shows the scheduled time on its own line rather than claiming
precision the data does not have.

### 3. Absolute time in the snooze tools

`snooze_alarm` and `set_snooze_duration` each gain an optional `until`
alongside `minutes`:

```
minutes : integer 1–30    how long from now
until   : string "HH:mm"  24-hour local clock time to ring at
```

JSON Schema cannot express "exactly one of these," so `required` becomes empty
and the dispatcher validates. Neither supplied, or both supplied, returns an
`is_error` tool result so the model retries rather than the app guessing.

Resolution is a pure function:

```swift
enum SnoozeResolver {
    static func resolve(minutes: Int?, until: String?, now: Date) -> Resolution

    enum Resolution {
        /// `minutes` is what to actually schedule; `returnsAt` is the absolute
        /// time that produces; `requested` is non-nil only when the ask was
        /// clamped, carrying what the user actually asked for so the tool
        /// result can name both numbers.
        case ok(minutes: Int, returnsAt: Date, requested: (minutes: Int, at: Date)?)
        /// Neither or both parameters supplied, or `until` failed to parse.
        case invalid(String)
    }
}
```

- `"HH:mm"` parses to the **next** occurrence at or after `now`. `"22:00"` at
  21:42 → tonight 22:00. `"06:00"` at 23:50 → tomorrow 06:00. This is a
  bedtime app; targets crossing midnight are normal, not an edge case.
- `minutes = ceil((target − now) / 60)`, floored at 1, so a target that just
  passed cannot produce a zero or negative snooze.
- Clamped to `Constants.maxSnoozeMinutes` (30 — the existing schema maximum,
  promoted to a named constant).

**Clamping is loud.** The incident is one word from tripping the cap: "until
10" from 9:42 is 18 minutes and fits; "until 11" is 78 and does not. Silently
snoozing 30 while the Coach tells the user "see you at 11" would reproduce the
exact failure being fixed. So a clamped call returns:

```
Requested 11:00 PM = 78 min, over the 30 min cap.
Snoozed 30 min instead — alarm returns at 10:12 PM, not 11:00 PM.
Tell the user this explicitly.
```

### 4. Tool results carry the return time

Today the model gets `"Snoozed for 18 minutes."` — relative, so it can only
tell the user something relative. New form:

```
Snoozed 18 minutes — alarm returns at 10:00 PM.
```

Same shape for `set_snooze_duration`. This is what lets the Coach's closing
line be accurate rather than a restatement of its own arithmetic.

### 5. Timestamped transcript

- `reFireTrigger` renders `USER [9:38 PM]:` / `COACH [9:38 PM]:` from the
  timestamps `ConversationMessage` already stores.
- Synthetic triggers are stamped: `[alarm fired at 9:30 PM]`,
  `[alarm re-fired after snooze at 9:42 PM]`.
- Live turns: **user messages only** get a `[9:42 PM] ` prefix, and only on
  the copy appended to `apiMessages`. The text shown on screen and persisted
  to `conversationLog` stays clean.

Stamping the Coach's live turns would mean rewriting its own words back into
the API history, which reliably teaches models to emit `[9:42 PM]` themselves
in user-visible replies. Stamping only the user's side keeps every gap visible
— a six-minute pause is the delta between consecutive user stamps — with no
mimicry risk. Both roles are still stamped inside the re-fire transcript,
which is framed as a quoted transcript rather than live turn structure.

## Out of scope

- History beyond the current wake-up chain. No cross-night summaries, no
  prior-night transcripts. Considered and deliberately deferred.
- Migrating existing `AlarmEvent` rows to backfill `snoozeLog`.
- Raising the 30-minute snooze cap.

## Verification

The project has no test target. `SnoozeResolver` and `buildTimeContext` are
written as pure functions with `now` injected so they are trivially testable
if a target is ever added, and hand-checkable now.

Real verification is a device build and install to bPhone2, then driving the
original failure: let an alarm ring, snooze twice via the system Stop button,
open the Coach several minutes later, ask for "until 10," and confirm the
alarm returns at 10:00 rather than 30 minutes out. Also confirm the timeline
renders with the right clock times and that a clamped request ("until
midnight") produces the loud message above.
