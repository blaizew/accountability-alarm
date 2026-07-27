# Coach time awareness

**Date:** 2026-07-26
**Status:** approved; all open questions resolved. Ready for an implementation
plan.
**Depends on:** commit `4505b36` (AlarmKit countdown snooze)

## The incident

An alarm set for 9:30 PM rang. The user hit the alarm-screen button several
times, then opened the Coach at 9:42 PM and asked for "a few more minutes,
until 10." The Coach snoozed for 30 minutes.

The device log confirms the mechanism verbatim. At 21:42:20 the Coach replied
*"That's 30 minutes past your commitment"* — 9:30 → 10:00. Then:

```
21:42:50  set_snooze_duration  requested=30  before=4  after=30
21:43:04  snooze_alarm {"minutes":30,"user_committed":true}  → fires=1800s
```

The alarm was scheduled to return at **22:13**, not 22:00. The user needed 18
minutes and got 30, and neither party knew they disagreed.

30 was the right answer to the wrong question: the only time anchor in the
system prompt is the alarm's *scheduled* time.

## What the Coach currently knows about time

| Fact | Available? |
| --- | --- |
| Current wall-clock time | No |
| When the alarm actually rang (`AlarmEvent.firedAt`) | Stored, never sent |
| When each snooze was taken | Not stored at all |
| How many snoozes (`snoozeCount`) | Stored but **broken** — see §3 |
| Timestamps on prior messages | Stored, stripped when the transcript is built |
| Alarm's scheduled time | Yes — the sole anchor |

`buildSystemPrompt` (`Services/ConversationEngine.swift:110`) passes
`alarm.timeString` and `Snooze count this session: N`. `reFireTrigger`
(`ViewModels/ConversationViewModel.swift:130`) renders prior messages as bare
`ROLE: content`, discarding the timestamp each message already carries.

## Goal

Every piece of time-bearing information the app already has reaches the Coach,
stamped — and clock-time arithmetic moves out of the model and into the app.

---

## 1. Timestamped snooze records

```swift
struct SnoozeRecord: Codable, Sendable, Hashable {
    let at: Date
    let minutes: Int
    let source: Source

    enum Source: String, Codable, Sendable {
        case countdown    // system "Snooze 5 min" button (AlarmKit .countdown)
        case snoozeButton // in-conversation Snooze button
        case coach        // the LLM's snooze_alarm tool
        case safetyNet    // auto 5-min reschedule; conversation opened, never resolved
    }
}
```

`AlarmEvent` gains `snoozeLogData: Data?` with a computed `snoozeLog:
[SnoozeRecord]`, mirroring the existing `conversationLogData` /
`conversationLog` pattern, plus `recordSnooze(minutes:source:)` that appends a
record and increments `snoozeCount` together so the two cannot drift.

Events already on the device have counts but no records and are not migrated.
A chain where `snoozeCount > snoozeLog.count` renders the difference as
"(N earlier snoozes, times not recorded)" rather than implying the timeline is
complete.

## 2. TIME block in the system prompt

New `buildTimeContext(alarm:event:now:)` on `ConversationEngine`, `now`
injected (default `Date()`) for testability. Placed above the snooze-count
ladder:

```
CURRENT TIME: 9:42 PM, Saturday July 26 (America/Los_Angeles)

TIMELINE (this wake-up chain):
  9:30 PM   alarm scheduled
  9:31 PM   alarm rang — chain started
  9:33 PM   snoozed 5 min (system Snooze button)
  9:36 PM   snoozed 5 min (opened the conversation, closed the app without resolving)
  9:39 PM   snoozed 5 min (system Snooze button)
  9:42 PM   conversation opened  ← now, 12 min past the alarm

All times are the user's local time. When the user names a clock time
("until 10", "by 10:15"), do NOT convert it to minutes yourself — pass it
straight to the tool's `until` parameter and the app computes the duration.
```

`buildSystemPrompt` is already rebuilt on every assistant turn
(`ConversationViewModel.swift:264`), so "now" stays current for free.

**Precision caveat.** `event.firedAt` is set when the chain's `AlarmEvent` row
is created — the first engagement, not the literal ring instant. It is off by
seconds to about a minute. The timeline labels it "alarm rang" and shows the
scheduled time separately rather than claiming precision the data lacks.

---

## 3. Snooze accounting is broken, and the timeline depends on it

This section was added after reading the device log. It is a prerequisite for
§2, not an optional extra.

### 3.1 Evidence

Every conversation tonight opened with `snoozeCount=0`, across three re-rings:

```
21:30:19  conversation opened (restored 0 prior messages, snoozeCount=0)
21:36:28  conversation opened (restored 1 prior messages, snoozeCount=0)
21:41:49  conversation opened (restored 2 prior messages, snoozeCount=0)
```

### 3.2 Cause

`SnoozeStopIntent` was the only thing incrementing `snoozeCount` on the
alarm-screen path. Commit `4505b36` replaced it with AlarmKit's native
`.countdown` snooze, which is handled entirely by the system and fires no
intent of ours. Nothing has incremented the count from the alarm screen since
2026-07-23.

### 3.3 Consequences

- The escalation ladder in `buildSystemPrompt` — "2 snoozes: name the pattern",
  "3+: this is avoidance" — has been dead for three days. The Coach saw a
  first-time conversation every round. It said "You snoozed already" at 21:41
  only because it could read the restored transcript.
- **The §2 timeline would render tonight as zero snoozes.** The feature's own
  data source is broken.

Also visible in the log: tonight's re-rings are all explained by the 5-minute
safety-net reschedule that fires when the conversation is opened and the app
closed without resolving (`rescheduleSnooze ... fires=300s` at 21:30, 21:36,
21:41). Whether the user *also* tapped "Snooze 5 min" at any point is
**unknown** — the system countdown leaves no trace. Closing that gap is the
point of §3.4.

### 3.4 Capturing the countdown snooze

`AlarmKitService.startObserving()` (`AlarmKitService.swift:64`) already
consumes `AlarmManager.shared.alarmUpdates` but keeps only the alarm IDs,
discarding each alarm's `state`. Extend it to read `state` and treat an
`.alerting → .countdown` transition as a snooze, calling
`recordSnooze(minutes:source:.countdown)`.

**Unverified:** the observer runs in-process, and whether a detached
`for await` loop receives updates while the app is suspended — the normal case
when the user snoozes from the lock screen — is not established.

It is not a single point of failure, because `AlarmManager.alarms` is a
**synchronous** property, and `Alarm` exposes `state` (`.scheduled`,
`.countdown`, `.paused`, `.alerting`). Reading it at app open reveals a
snooze in progress with no dependence on the observer having run. So the
degradation is in timestamp precision, not in detection:

| | Mechanism | Result |
| --- | --- | --- |
| Best | Observer fires live | Exact transition time |
| Fallback | Sync poll of `AlarmManager.alarms` at app open / `reconcileOnAppOpen` | Snooze detected; start time bounded to the preceding `postAlert` window (5 min) |

`Alarm` carries `state` and `countdownDuration` but **no** countdown start or
fire date, which is why the fallback can only bound the time. Those fields
(`startDate`, `fireDate`) exist on `AlarmPresentationState.Countdown`, but that
is the ActivityKit content state, reachable via the Live Activity rather than
off `Alarm`. Whether our process can read it is unverified and the design does
not depend on it — treat it as a possible precision upgrade, not a plan.

Implement the observer path and verify on device. If it does not fire while
suspended, fall back to the sync poll and mark those timeline entries
approximate ("~9:33 PM") rather than presenting a bounded guess as observed.

**Blast radius if the observer never fires.** The alarm and the snooze itself
are unaffected — AlarmKit owns both, and this code is read-only bookkeeping.
§4, §5, §6, and the `CURRENT TIME` line in §2 do not touch snooze records at
all, so the fix for the original incident stands either way. Only the
system-button rows of the §2 timeline lose precision.

### 3.5 Every snooze counts

**Decided (Blaize, 2026-07-26): all snoozes count toward the escalation
ladder** — `.countdown`, `.snoozeButton`, `.coach`, and `.safetyNet` alike.
`recordSnooze` increments `snoozeCount` for every source without exception;
there is no "doesn't really count" case.

The `.safetyNet` reschedule — conversation opened, app closed without resolving
— counts too. It is behaviourally avoidance, and it is exactly what happened
three times on 2026-07-26.

The `source` field is still recorded and still rendered in the timeline, but it
informs the Coach's *tone*, never the count. A user who walked away from an
open conversation and one who deliberately tapped Snooze are both at the same
rung of the ladder; the Coach just gets to know which happened.

---

## 4. Absolute time in the snooze tools

`snooze_alarm` and `set_snooze_duration` each gain an optional `until`
alongside `minutes`:

```
minutes : integer 1–30    how long from now
until   : string "HH:mm"  24-hour local clock time to ring at
```

JSON Schema cannot express "exactly one of these," so `required` becomes empty
and the dispatcher validates. Neither supplied, or both supplied, returns an
`is_error` tool result so the model retries rather than the app guessing.

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

- `"HH:mm"` resolves to the **next** occurrence at or after `now`. `"22:00"` at
  21:42 → tonight 22:00. `"06:00"` at 23:50 → tomorrow 06:00. This is a bedtime
  app; targets crossing midnight are normal, not an edge case.
- `minutes = ceil((target − now) / 60)`, floored at 1, so a target that just
  passed cannot produce a zero or negative snooze.
- Clamped to `Constants.maxSnoozeMinutes` (30 — the existing schema maximum,
  promoted to a named constant).

**Clamping is loud.** The incident is one word from tripping the cap: "until
10" from 9:42 is 18 minutes and fits; "until 11" is 78 and does not. Silently
snoozing 30 while the Coach says "see you at 11" would reproduce the exact
failure being fixed. A clamped call returns:

```
Requested 11:00 PM = 78 min, over the 30 min cap.
Snoozed 30 min instead — alarm returns at 10:12 PM, not 11:00 PM.
Tell the user this explicitly.
```

## 5. Tool results carry the return time

Today the model gets `"Snoozed for 18 minutes."` — relative, so it can only
tell the user something relative. New form:

```
Snoozed 18 minutes — alarm returns at 10:00 PM.
```

Same shape for `set_snooze_duration`. This is what lets the Coach's closing
line be accurate rather than a restatement of its own arithmetic.

## 6. Timestamped transcript

- `reFireTrigger` renders `USER [9:38 PM]:` / `COACH [9:38 PM]:` from the
  timestamps `ConversationMessage` already stores.
- Synthetic triggers are stamped: `[alarm fired at 9:30 PM]`,
  `[alarm re-fired after snooze at 9:42 PM]`.
- Live turns: **user messages only** get a `[9:42 PM] ` prefix, and only on the
  copy appended to `apiMessages`. The text shown on screen and persisted to
  `conversationLog` stays clean.

Stamping the Coach's live turns would mean rewriting its own words back into
the API history, which reliably teaches models to emit `[9:42 PM]` themselves
in user-visible replies. Stamping only the user's side keeps every gap visible
— a six-minute pause is the delta between consecutive user stamps — with no
mimicry risk. Both roles are still stamped inside the re-fire transcript, which
is framed as a quoted transcript rather than live turn structure.

---

## Out of scope

- History beyond the current wake-up chain. No cross-night summaries, no
  prior-night transcripts. Considered and deliberately deferred.
- Migrating existing `AlarmEvent` rows to backfill `snoozeLog`.
- Raising the 30-minute snooze cap.

## Build order

§3 first — the timeline is worthless while snooze accounting is broken, and the
escalation ladder is currently dead in production. Then §1/§2, then §4/§5, then
§6.

## Verification

The project has no test target. `SnoozeResolver` and `buildTimeContext` are
written as pure functions with `now` injected so they are trivially testable if
a target is ever added, and hand-checkable now.

Real verification is a device build and install to bPhone2, then:

1. **§3 first, on its own.** Let the alarm ring, tap "Snooze 5 min" from the
   alarm screen, and confirm via the pulled device log that `snoozeCount`
   increments and a `.countdown` `SnoozeRecord` is written. This is the step
   that validates the unverified risk in §3.4 — do not build §2 on top of it
   until it passes.
2. Reproduce the original failure: ring, snooze twice, open the Coach several
   minutes later, ask for "until 10", and confirm the alarm returns at 10:00
   rather than 30 minutes out.
3. Confirm the timeline renders the right clock times and sources.
4. Confirm a clamped request ("until midnight") produces the loud message in §4.

Device log query (per the project's debugging procedure):

```
xcrun devicectl device copy from --device <UDID> \
  --domain-type appDataContainer --domain-identifier com.blaizew.AccountabilityAlarm \
  --source "Library/Application Support/default.store" --destination <dest>

sqlite3 <dest> "SELECT datetime(ZTIMESTAMP + 978307200,'unixepoch','localtime'),
  ZCATEGORYRAW, ZMESSAGE FROM ZALARMLOGENTRY ORDER BY ZTIMESTAMP DESC LIMIT 40;"
```
