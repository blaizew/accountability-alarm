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

`SnoozeStopIntent` was the only code of ours that ran on the alarm-screen path.
Commit `4505b36` replaced it with AlarmKit's native `.countdown` snooze, which
the system handles end to end and which fires no intent of ours. Since
2026-07-23, a snooze taken from the alarm screen executes no app code at all.

### 3.3 Consequences

The damage is worse than a miscount. `SnoozeStopIntent` also *created* the
chain's `AlarmEvent`; the only other creator is the conversation opening. So a
user who snoozes from the alarm screen and has not yet talked to the Coach has
**no `AlarmEvent` at all** — not an event with a wrong count.

Confirmed on a clean case 2026-07-27: a test alarm rang, "Snooze 5 min" was
tapped, and the store showed no new `AlarmEvent` row, no log entry, and
`snoozedUntil=nil` / `pendingSnoozeIdString=nil` on the alarm.

Downstream:

- When the user finally opens the Coach, `AlarmEvent.openChain` finds nothing
  and starts a fresh event at `snoozeCount=0`. The entire snooze history of
  that wake-up chain is **gone**, not merely miscounted.
- The escalation ladder in `buildSystemPrompt` — "2 snoozes: name the pattern",
  "3+: this is avoidance" — has been dead since 2026-07-23. On 2026-07-26 the
  Coach opened at `snoozeCount=0` three times running. It said "You snoozed
  already" at 21:41 only because it could read the restored transcript.
- **The §2 timeline would render those snoozes as zero.** The feature's own
  data source is broken.

So §3 must create the chain event, not just increment a counter, when a
countdown snooze is detected.

### 3.4 Capturing the countdown snooze

`AlarmKitService.startObserving()` (`AlarmKitService.swift:64`) already
consumes `AlarmManager.shared.alarmUpdates` but keeps only the alarm IDs,
discarding each alarm's `state`. Extend it to read `state` and treat an
`.alerting → .countdown` transition as a snooze, calling
`recordSnooze(minutes:source:.countdown)`.

**VERIFIED on device 2026-07-27** with a temporary instrumented build. Test:
alarm scheduled 09:48, app backgrounded (not force-quit), alarm rang, "Snooze
5 min" tapped at ~09:48:05, store pulled before reopening, app reopened
09:49:35, store pulled again.

Results:

- **Background capture is unreliable, not absent.** In this run the first pull
  showed no trace of the ring or the snooze — a backgrounded process is
  suspended and cannot execute or write. But Test B later logged an observer
  line at 21:10:34 with no app open and no reconcile, ~15 minutes after that
  alarm rang. So AlarmKit does sometimes wake the process (the alert is a Live
  Activity), just late and not at the transition. Treat background delivery as
  possible but undependable; the design must not rely on it.
- **On resume the observer replays the transition sequence**, not merely the
  final state — it delivered `alerting` and then `countdown` for the same
  alarm. Detection therefore distinguishes "rang and was snoozed" from "merely
  counting down". Observed once; treat as a bonus signal, do not build logic
  that *requires* seeing `alerting`.
- **The synchronous poll independently confirms** `.countdown` at
  `reconcileOnAppOpen`. Two detection paths, not one.
- **All timestamps are resume-time.** The snooze occurred ~09:48:05; every
  entry reads 09:49:35. Exact event timing is unrecoverable.
- **No `AlarmEvent` was created** by the ring or the snooze, re-confirming
  §3.1–3.3 on a clean case.

**Consequence for the design.** Detection is reliable; precision is not.
Record the snooze on the first observation after the fact and bound its time:

```
snoozeStart ∈ [ max(scheduledRingTime, T − postAlert), T ]
```

where `T` is the observation. The bound is never worse than the 5-minute
countdown window — in the verification run, `[09:48:00, 09:49:35]` against an
actual of ~09:48:05. Render these entries as approximate (`~9:48 PM`), never
as observed times.

`Alarm` carries `state` and `countdownDuration` but **no** countdown start or
fire date, which is why the bound exists. Those fields (`startDate`,
`fireDate`) live on `AlarmPresentationState.Countdown` — the ActivityKit
content state, reachable via the Live Activity rather than off `Alarm`.
Unverified, and the design does not depend on it; treat as a possible
precision upgrade, not a plan.

**API note:** `AlarmManager.alarms` is a *throwing* property
(`try manager.alarms`), despite the `.swiftinterface` rendering it as a plain
getter. The sync poll can fail, not merely be imprecise — handle the throw.

**Blast radius.** The alarm and the snooze itself are unaffected in every case
— AlarmKit owns both, and this code is read-only bookkeeping. §4, §5, §6, and
the `CURRENT TIME` line in §2 do not touch snooze records at all, so the fix
for the original incident stands regardless.

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

### 3.5b Reconcile now mis-records snoozed nights as "ignored"

A second consequence of §3.3, and the reason §3 is urgent rather than merely
desirable.

`recordMissedFirings` (`AlarmKitService.swift:372`) has two guards against
falsely recording a firing the user actually engaged with:

```swift
if let until = alarm.snoozedUntil, until > now { continue }          // :377
if alarm.events.contains(where: { $0.firedAt > window }) { continue } // :389
```

Post-`4505b36`, **both are blind**. A countdown snooze sets no `snoozedUntil`
and creates no `AlarmEvent`, so neither guard fires.

With `missedGraceMinutes = 30`, a user who snoozes from the alarm screen past
30 minutes (six taps) and then opens the app has that night recorded as
`outcome = "ignored"` — the ledger's "slept through it / muted it / swiped it
away" — for a night they were actively fighting the alarm.

It compounds: the inserted event is not `pending`, so `AlarmEvent.openChain`
skips it and the conversation creates a *second* event. One night, two rows,
one of them false.

To be explicit about what is **not** broken: nothing runs while the app is
closed, so no event is closed behind the user's back, and the alarm re-rings
indefinitely regardless — AlarmKit owns the countdown and needs no app code.
AlarmKit imposes no cap on snooze count (`AlarmError.maximumLimitReached`
governs concurrent scheduled alarms, not snoozes). This is a ledger-truth
failure at app open, not an alarm-reliability failure.

#### Delete the grace window; judge on state and firing lifecycle

Fixing §3.4 makes guard `:389` fire again, but that only patches the symptom.
The deeper problem is that `missedGraceMinutes` is a *time-based proxy* for
"is this wake-up chain still in flight?" — and §3.4 established that we can
read the real thing: `Alarm.state` is available synchronously at app open.

A threshold is strictly worse than the signal it approximates. Six taps was
never a designed number; it is 30 minutes divided by the countdown duration,
a quantity nobody chose.

**Test B (2026-07-27) killed two successive replacements before the right rule
emerged.** An ignored alarm rang for 15 minutes, went silent, and then stayed
`.alerting` indefinitely — still `.alerting` 35 minutes after firing, with the
alert on screen and both buttons live. It only cleared when `stopAnyAlerting()`
ran at app open.

That falsified the first replacement ("`.alerting` ⇒ chain is live, never
ignored"), which would have meant a genuinely ignored alarm is *never* recorded
as ignored — breaking the exact case the code exists for, and only on nights
the user slept through.

It also falsified the second ("`.alerting` past the 15-minute ring duration ⇒
ignored"). 15 minutes is when the *sound* stops. Nothing else changes: state
stays `.alerting`, the alert stays on screen, both buttons stay live, and the
user can still engage at minute 35. It measures an audio policy and says
nothing about whether the firing is still engageable — arbitrariness with a
citation, worse than 30 because it looks principled.

**Delete `missedGraceMinutes` and add nothing in its place.** The question is
not "how long has it been" but "is this firing over, and did anything engage
it" — and reconcile has a definitive answer, because *reconcile is what ends
it*: `stopAnyAlerting()` (`:362`) is what clears a stuck alert.

| State at app open | Firing status | Verdict |
| --- | --- | --- |
| `.countdown` | Live — the user snoozed | Engaged. Create/keep the chain. Never ignored. |
| `.alerting` | Still open, but reconcile is about to end it | No event ⇒ record ignored **at the moment we clear it** |
| `.scheduled` | Already over | No event near the due time ⇒ ignored |

No numbers. What makes it safe is revisability (below): the ledger records its
best current read and corrects itself when better evidence arrives, rather
than stalling on a timer hoping ambiguity resolves.

`missedLookbackHours` stays, doing a different and still-necessary job: don't
backfill firings from a week ago.

#### Two alarms alerting at once

Observed live during Test B: the abandoned 20:55 alarm was still `.alerting`
when the 21:30 alarm fired, and opening the 21:30 Coach silenced both.

`ConversationViewModel.setup` calls `stopAllActive`, which calls
`stopAnyAlerting()` — and that stops **every** alerting alarm, not just its
own. So one alarm's conversation silently clears another's alert, and the app,
not the user, decides the first was abandoned.

**Decided (Blaize, 2026-07-27): scope it.** `stopAllActive` stops only the
alarms belonging to its own `Alarm` record. Two alarms ringing means two
commitments to answer; silencing one for free contradicts the premise. The
broad sweep is kept **only** for true orphans — AlarmKit alarms no `Alarm`
record tracks — which is the ghost-ringer backstop it was written for.

A firing genuinely abandoned this way is recorded as **`ignored`**, reusing the
existing outcome rather than adding a fifth. Nothing engaged with it; that is
what ignored means. (Decided 2026-07-27.)

#### An "ignored" verdict must be revisable

Recording sooner widens an existing hole. `AlarmEvent.openChain` matches only
`outcome == "pending"`, so an `ignored` row is invisible to it: record ignored
at 21:32, user opens the Coach at 21:35, and the night has two rows.

The ledger has to be able to change its mind when new evidence arrives.
`openChain` should adopt a recent `ignored` event for the same firing and
reopen it as `pending`, rather than inserting a second event alongside it.

#### Test B is answered — the reconcile arm is unblocked

Resolved 2026-07-27: an untouched alert lingers `.alerting` indefinitely. The
table above reflects that. No gate remains on §3.

### 3.6 Adjacent bug: restored messages trip the turn limit

Found while reading the 2026-07-26 log. Not caused by this work, but it
corrupts the same `AlarmEvent` records §3 depends on, so it is fixed here.

```
22:13:10  conversation opened (restored 11 prior messages, snoozeCount=1)
22:13:25  user: All right I'm done brushing my teeth now thanks for checking in
22:13:27  override: Max conversation turns reached
```

`ConversationViewModel.swift:170` checks
`messages.count >= Constants.maxConversationTurns * 2` (6 × 2 = 12), but
`messages` includes the messages restored from earlier in the chain. With 11
restored, a single exchange trips the limit and the chain is marked
`overridden`, resetting the streak — while the user was in fact complying.

Any re-opened conversation with a substantial transcript behind it
self-destructs on the first reply.

**Fixed and shipped** in commit `98bd42f` (2026-07-27), ahead of the rest of
this spec: count only this session's turns by excluding the already-tracked
`seededMessageCount`. Installed on bPhone2 the same day.

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
- Re-tuning `missedLookbackHours`. It keeps its current job (don't backfill
  ancient firings) and its current value.

## Build order

§3 first (including §3.6) — the timeline is worthless while snooze accounting is broken, and the
escalation ladder is currently dead in production. Then §1/§2, then §4/§5, then
§6.

## Verification

The project has no test target. `SnoozeResolver` and `buildTimeContext` are
written as pure functions with `now` injected so they are trivially testable if
a target is ever added, and hand-checkable now.

Real verification is a device build and install to bPhone2, then:

**Test A — countdown snooze is recorded.** Let the alarm ring, tap "Snooze
5 min" from the alarm screen, reopen the app, and confirm the store shows
`snoozeCount` incremented and a `.countdown` `SnoozeRecord` written. Do not
build §2 on top of §3 until this passes.

**Test B — what an ignored alert becomes.** *Run 2026-07-27; ANSWERED.* An
alarm rang for 15 minutes, went silent, and stayed `.alerting` indefinitely —
still `.alerting` 35 minutes after firing, alert on screen, both buttons live.
It never returns to `.scheduled` on its own; only `stopAnyAlerting()` at app
open clears it. See §3.5b for the two rules this falsified.

**Test C — no false "ignored" past the old grace window.** Snooze from the
alarm screen more than six times (past 30 minutes), then open the app.
Confirm the store holds exactly **one** event, `pending`, with the right
`snoozeCount` — and no `"ignored"` row. This is the regression test for the
ordering hazard below.

**Ordering hazard.** `reconcileOnAppOpen` runs orphan cleanup →
`recordMissedFirings` (`:357`) → `closeAbandonedChains` (`:358`). The
countdown-snooze detection **must run before `:357`**. If it runs after, the
event does not exist when `recordMissedFirings` checks, the false `"ignored"`
is written anyway, and the event appears a moment later — so the bug survives
while looking fixed. Test C is what catches it.
**Test D — the original incident.** Ring, snooze twice, open the Coach several
minutes later, ask for "until 10", and confirm the alarm returns at 10:00
rather than 30 minutes out.

**Test E — presentation.** Confirm the timeline renders the right clock times
and sources, that approximate entries read `~9:48 PM`, and that a clamped
request ("until midnight") produces the loud message in §4.

### Pulling the device store — pull the WAL too

SwiftData runs SQLite in WAL mode. `default.store` alone is checkpointed and
can be **hours stale**; recent writes live in `default.store-wal`. Pulling only
the main file silently shows you the past. (On 2026-07-26 it presented a store
checkpointed at 21:43 as current, hiding everything after.)

Pull all three files to the same basename so sqlite replays the log:

```
for ext in "" "-wal" "-shm"; do
  xcrun devicectl device copy from --device <UDID> \
    --domain-type appDataContainer --domain-identifier com.blaizew.AccountabilityAlarm \
    --source "Library/Application Support/default.store$ext" \
    --destination <dest>/default.store$ext
done

sqlite3 <dest>/default.store "SELECT datetime(ZTIMESTAMP + 978307200,'unixepoch','localtime'),
  ZCATEGORYRAW, ZMESSAGE FROM ZALARMLOGENTRY ORDER BY ZTIMESTAMP DESC LIMIT 40;"
```

Sanity-check every pull: compare `MAX(ZTIMESTAMP)` against the wall clock
before drawing conclusions from an absence of rows.
