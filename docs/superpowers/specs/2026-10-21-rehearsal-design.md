# Rehearsal mode — design

Date: 2026-10-21. Status: approved in chat by Blaize (design as played back; no "fire in 10 seconds" option).

## Intent

Let the user run the whole Coach conversation, including the fist bump, on
demand, without waiting for a real alarm. Two reasons:

- Blaize tests changes (the bump, the Coach's wording) in seconds instead of
  setting an alarm and waiting for it.
- New users see what the app does before they commit to an alarm.

A rehearsal is the real conversation with the real Coach. It is not a canned
script. The only difference from a real alarm: nothing is written down and
nothing is scheduled.

## Goals

- "Rehearse this alarm" from any existing alarm. The Coach gets that alarm's
  real label and commitment fields.
- "See how it works" from the Alarms screen, for users with no alarms. It runs
  the same rehearsal against a built-in sample alarm that is never saved.
- A rehearsal writes nothing to the ledger: no `AlarmEvent`, no outcome, no
  streak change, no saved transcript, no `snoozedUntil`, no AlarmKit schedule
  or cancel. The History tab is identical before and after.
- The screen says it is a rehearsal, and the user can leave at any time.
- The fist bump works in a rehearsal exactly as in a real alarm, including
  haptic, confetti, removal, and the 2.2 s close.

## Non-goals

- No "fire in N seconds" real alarm. The lock-screen alert and the
  "Talk to Coach" button stay untested by this feature.
- No change to the Coach's prompt or judgment. The Coach is not told it is a
  rehearsal. The opening trigger message is the same "[alarm fired at …]".
- No onboarding flow, tutorial text, or tooltips beyond the one entry row.
- No data model change.
- The Settings "Try it" bump demo stays as it is (bump only, no Coach).

## Anti-goals

- A rehearsal that leaks into the ledger: one stray `AlarmEvent`, one saved
  transcript, or one scheduled snooze is a failure.
- A rehearsal that behaves differently from a real alarm in the conversation
  itself (different prompt, different tools, different stage).
- A rehearsal the user cannot exit until the Coach authorizes.
- The sample alarm appearing in the alarm list, or persisting after the
  rehearsal.

## Constraints

- SwiftUI + MVVM + SwiftData, iOS 26.2, dark mode only, Ledger look.
- Work in the same worktree and branch as the fist bump
  (`wt/fist-bump`), after the fist bump plan's final review is clean.
- Real Claude API calls happen during a rehearsal. That is intended.
- No third-party packages.

## How it works

### Session flag and the rehearsal copy

`AppState.ConversationSession` gains `let isRehearsal: Bool`. Two new
entry points on `AppState`:

- `rehearse(alarm: Alarm)`: builds an **un-inserted copy** of the alarm (a
  fresh `Alarm` with every scalar field copied: label, reason and the five
  commitment fields, exception cases, snoozeMinutes, sleep fields), stores
  the copy in `rehearsalAlarm`, and mints a session with
  `isRehearsal: true` and the copy's id. The stored alarm is never handed to
  the conversation, so nothing can write to it.
- `rehearseSample()`: builds the sample `Alarm` (never inserted into any
  `ModelContext`), stores it in `rehearsalAlarm`, and mints the session.

**The copy's time is now.** Both entry points set the copy's `hour` and
`minute` to the current clock, so the Coach's time context reads like an
alarm that just fired, not one that is eight hours late. (My call: the
Coach must behave exactly as on a real first ring, and on a real ring the
alarm time and the current time are the same. The alarm header shows the
copy's time too.)

**The timeline shows a ring.** `ConversationEngine.buildTimeContext` gains a
`firedAt: Date?` parameter. It defaults to `event?.firedAt`; a rehearsal
passes the session's start time, so the "alarm rang — chain started" line
and the "N min past the alarm" note appear exactly as on a real first ring.
Never build a stand-in `AlarmEvent` for this: pointing an `AlarmEvent` at a
stored alarm pulls it into the main context and autosave would write it.

`MainTabView`'s full-screen cover passes the session into `ConversationView`,
which reads `isRehearsal` and resolves its alarm from
`appState.rehearsalAlarm` when rehearsing (the view's own fetch by id is
only for real sessions, because the sample alarm is not in the store).
`dismissAlarm()` clears `rehearsalAlarm`.

### View model in rehearsal

`ConversationViewModel.setup` gains a rehearsal path:
`setup(alarm: Alarm, isRehearsal: true, context:)`. In that path it:

- does not insert an `AlarmEvent`, does not look up an open chain, and
  leaves `event` nil (so every `event?.…` write is a no-op);
- does not call `AlarmKitService` (no `stopAllActive`, no
  `rescheduleSnooze`, no `cancelPendingSnooze`). The guards go at the top
  of `rescheduleSnooze` and `cancelPendingSnooze` themselves, because the
  Coach's `snooze_alarm` and `mark_overridden` tool handlers call them
  and those functions also write `pendingSnoozeIdString`, `snoozedUntil`,
  and save the context;
- does not touch `alarm.snoozedUntil` or `pendingSnoozeIdString` (the copy
  makes this harmless anyway);
- never calls `context.save()`;
- still sends the trigger message and runs the Coach turns as usual;
- still logs to `LogService`, with every message prefixed `rehearsal: ` so the
  Debug tab shows what happened without it being mistaken for a real alarm.

`resolveSnooze` in rehearsal appends the usual "Okay — N more minutes" line,
marks the session completed, and closes. Nothing is scheduled.
`resolveAction` (the bump) marks the session completed and closes. The
Coach's `snooze_alarm` and `mark_overridden` tools behave the same way:
they complete the session visibly and write nothing.

Guard shape: one `isRehearsal` property checked at each of the write sites
listed above. Do not fork the whole view model.

### Screen differences

- Top bar reads `REHEARSAL · mm:ss` instead of `ALARM FIRING · mm:ss`. The
  dot stays. Add a right-aligned `END` kicker button that closes the
  rehearsal at any time (`appState.dismissAlarm()` + `dismiss()`). END is the
  only early exit: the conversation is a full-screen cover, which has no
  swipe-down gesture, so no dismiss-gesture change is made.
- Everything else (alarm header, chat, voice/text tabs, wide Snooze, the
  bump stage) is identical to a real alarm.

### Entry points

- **The per-row play button becomes Rehearse.** `AlarmListView` already
  shows an `L.PlayTri` button on each enabled alarm row that calls
  `appState.triggerAlarm(alarmId:)`, which starts a *real* conversation
  (inserts an `AlarmEvent`, arms the safety-net snooze, writes the ledger).
  That button now calls `appState.rehearse(alarm:)` instead. Its glyph and
  position stay; its accessibility label becomes "Rehearse". (My call: a
  ledger-writing trigger one tap from the list is the stray write this
  feature exists to prevent, and rehearsing from the list means the alarm
  is always the saved one, so there is no unsaved-edits problem. No button
  is added to the edit sheet.)
- **Alarms screen** (`AlarmListView`): a `SEE HOW IT WORKS` row at the
  bottom of the list, always visible, kicker style with a leading
  `L.PlayTri` glyph. It starts the sample rehearsal.

### The sample alarm

Built in code, never saved. Values:

| Field | Value |
|---|---|
| label | `Morning run` |
| hour / minute | 6 / 30 |
| snoozeMinutes | 5 |
| reasonText | `Get up, put on my shoes, and run 5k before work.` |
| desiredBehavior | same as reasonText |
| whyWantThis | `I feel sharp all day when I run first thing.` |
| positiveOutcome | `A calm, focused morning and a clear head at work.` |
| negativeOutcome | `I skip it, feel sluggish, and resent myself by noon.` |
| longTermImpact | `Running four mornings a week is how I stay healthy for the people who count on me.` |
| exceptionCases | empty |

### Debug hook

A `--rehearse-sample` launch argument starts the sample rehearsal on launch,
so the simulator can screenshot the conversation without taps.

## Verification

- Simulator: launch with `--rehearse-sample`; screenshot after the Coach's
  opening message lands (it needs the API key, which is present in the
  worktree). Expected: `REHEARSAL` top bar with `END`, the sample alarm
  header, the Coach's first question, and the wide Snooze button.
- Side-effect check on the simulator: count `ZALARMEVENT` rows in the app's
  `default.store` before and after a rehearsal; they must match. Also
  confirm `ZALARM` has no `Morning run` row.
- Real alarm path unchanged: a normal launch still fetches the alarm by id
  and inserts an `AlarmEvent` as before (reviewer reads the diff for this).
- Device: install on bPhone2; Blaize rehearses a real alarm from its edit
  sheet, talks to the Coach, bumps the fist, then checks History shows no
  new entry.

## Left to the builder

- Exact row styling for `SEE HOW IT WORKS` within the Ledger look.
- How the alarm copy is built (a small `Alarm.rehearsalCopy()` helper is
  expected).
- Whether `isRehearsal` lives on the session only or is also mirrored on the
  view model as a stored property (the latter is expected).
