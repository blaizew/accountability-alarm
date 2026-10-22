# Rehearsal Mode Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let the user run the full Coach conversation and fist bump on demand, from any alarm or from a built-in sample, with zero writes to the ledger, the alarm, or AlarmKit.

**Architecture:** A rehearsal is a normal `ConversationSession` flagged `isRehearsal`, run against an un-inserted copy of an `Alarm` whose time is set to now. The view model takes a rehearsal setup path that skips every persistence and scheduling call behind one `isRehearsal` flag. The engine's time context accepts an explicit `firedAt` so the prompt matches a real first ring without a stand-in `AlarmEvent`. Entry points: the existing per-row play button (now a rehearsal) and a new "See how it works" row for the sample.

**Tech Stack:** SwiftUI, SwiftData (read-only in rehearsal), existing Claude API path. No packages.

**Spec:** `docs/superpowers/specs/2026-10-21-rehearsal-design.md`

## Global Constraints

- Same worktree and branch as the fist bump (`wt/fist-bump`); build on top of `e902ec4` or later. Paths below are relative to `AccountabilityAlarm/AccountabilityAlarm/` unless they start with `scripts/` or `docs/`.
- A rehearsal must never: insert an `AlarmEvent`; call `context.save()`; call any `AlarmKitService` method; write `alarm.snoozedUntil` or `alarm.pendingSnoozeIdString`; hand the stored `Alarm` to the conversation. Never construct an `AlarmEvent` pointing at a stored alarm for prompt purposes.
- The Coach prompt content in a rehearsal must match a real first ring: alarm time = now, and the timeline shows the "rang" line.
- `LogService` entries from a rehearsal are prefixed `rehearsal: `.
- Compile check (from the worktree's `AccountabilityAlarm/` dir): `xcodebuild -project AccountabilityAlarm.xcodeproj -scheme AccountabilityAlarm -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO -derivedDataPath /tmp/claude-501/dd-fist build 2>&1 | tail -5` → `BUILD SUCCEEDED`. Logic tests: `scripts/bump-tests/run.sh` → `ALL PASSED` (must keep passing; this plan adds no logic tests because every touched type imports SwiftData).
- Simulator: iPhone 17 Pro `83653F8D-88B1-4506-A703-70F1DF8B203E`, bundle `com.blaizew.AccountabilityAlarm`.
- Commit after every task with identity `blaizew` / `blaizew@users.noreply.github.com` and the session trailer lines.
- Sample alarm values are exactly the spec's table.

## Review Focus

1. A real alarm fires during a rehearsal: `triggerAlarm` mints a new session with `isRehearsal: false` and the cover rebuilds (`.id(session.id)`); the real session must not read `rehearsalAlarm`. Covered by Task 2's `ConversationView` alarm resolution being keyed on `isRehearsal`, and the reviewer traces it.
2. END is tapped while the Coach's API call is in flight: the view model keeps running; in rehearsal nothing it does afterwards persists. Reviewer confirms every late write is behind the flag.
3. The Coach calls `snooze_alarm` or `mark_overridden` in a rehearsal: the session completes visibly, nothing is scheduled or saved. Covered by guards at the top of `rescheduleSnooze` and `cancelPendingSnooze` (Task 2).
4. The real alarm path is unchanged: `setup(alarmId:)` still fetches, inserts an `AlarmEvent`, arms the safety net. Reviewer reads the diff for this.
5. The sample alarm never reaches the store: Task 3 checks `ZALARM` for a `Morning run` row after a rehearsal.

---

### Task 1: Rehearsal copy, sample, session flag, and time context

**Files:**
- Modify: `Models/Alarm.swift` (add `rehearsalCopy(now:)`)
- Create: `App/RehearsalSample.swift`
- Modify: `App/AppState.swift` (whole file is 31 lines)
- Modify: `Services/ConversationEngine.swift:138-190` (`buildTimeContext`) and `:190-217` (`buildSystemPrompt`)

**Interfaces:**
- Produces:
  - `extension Alarm { func rehearsalCopy(now: Date = Date()) -> Alarm }`: a new, un-inserted `Alarm` with `hour`/`minute` from `now` (local calendar), and these fields copied: `label`, `reasonText`, `reasonAudioPath`, `desiredBehavior`, `whyWantThis`, `positiveOutcome`, `negativeOutcome`, `longTermImpact`, `exceptionCases`, `targetSleepHours`, `nextMorningEvent`, `nextMorningEventHour`, `nextMorningEventMinute`, `snoozeMinutes`, `repeatDays`. Not copied: `id` (fresh), `events`, `alarmKitIdStrings`, `pendingSnoozeIdString`, `snoozedUntil`, `enabled` (true), `createdAt`.
  - `enum RehearsalSample { static func makeAlarm(now: Date = Date()) -> Alarm }` with the spec table's values and `hour`/`minute` from `now`.
  - `AppState.ConversationSession` gains `let isRehearsal: Bool`. `triggerAlarm(alarmId:)` passes `false`. New: `private(set) var rehearsalAlarm: Alarm?`; `func rehearse(alarm: Alarm)` (sets `rehearsalAlarm = alarm.rehearsalCopy()`, mints a session with the copy's id and `isRehearsal: true`); `func rehearseSample()` (same with `RehearsalSample.makeAlarm()`). `dismissAlarm()` also sets `rehearsalAlarm = nil`.
  - `ConversationEngine.buildTimeContext(alarm:event:now:firedAt: Date? = nil)`: `let fired = firedAt ?? event?.firedAt`; every place the function reads the event's fired time (the "rang — chain started" row and the "N min past the alarm" note) reads `fired` instead, so a non-nil `firedAt` with a nil `event` renders both lines. `buildSystemPrompt(alarm:event:snoozeButtonMinutes:now:firedAt: Date? = nil)` passes it through.

- [ ] **Step 1: Implement the four changes**

Read `buildTimeContext` in full before editing; keep the snooze-row interleaving untouched.

- [ ] **Step 2: Compile check, logic tests, commit**

Run the compile check and `scripts/bump-tests/run.sh`. Then:
```bash
git add AccountabilityAlarm/AccountabilityAlarm/Models/Alarm.swift AccountabilityAlarm/AccountabilityAlarm/App AccountabilityAlarm/AccountabilityAlarm/Services/ConversationEngine.swift
git commit -m "Rehearsal: alarm copy, sample alarm, session flag, explicit firedAt in the time context"
```

---

### Task 2: View model rehearsal path and the conversation screen

**Files:**
- Modify: `ViewModels/ConversationViewModel.swift` (`setup` at ~:63-131; `resolveSnooze` ~:238-252; `rescheduleSnooze` :266; `cancelPendingSnooze` :301; `buildSystemPrompt` call :324; `snooze_alarm` handler ~:480-500; `handleCompliance` :556; `handleOverride` :574; `saveConversation` :591; every `LogService.shared.log(.conversation, …)` call)
- Modify: `Views/ConversationView.swift` (`init` :34, `alarm` computed property ~:40-44, `.interactiveDismissDisabled` :73 unchanged, `vm.setup` :75, `topBar` ~:146-158)
- Modify: `Views/MainTabView.swift:37-41`

**Interfaces:**
- Consumes: Task 1.
- Produces:
  - `ConversationViewModel`: `private(set) var isRehearsal = false`, `private var rehearsalStart = Date()`, `func setup(alarm: Alarm, isRehearsal: Bool, context: ModelContext)`. The existing `setup(alarmId:context:)` is unchanged in behavior: it fetches the alarm and continues as today. Factor the shared tail only if it stays obviously behavior-preserving; otherwise keep the rehearsal path separate and short.
  - `ConversationView.init(alarmId: UUID, isRehearsal: Bool = false)`.

- [ ] **Step 1: View model**

Rehearsal setup: set `isRehearsal`, `rehearsalStart = Date()`, `alarm`, `snoozeButtonMinutes = alarm.snoozeMinutes`; leave `event` nil; append the same `"[alarm fired at …]"` trigger message; log `"rehearsal: conversation opened"`; run the first assistant turn. No `AlarmEvent`, no `openChain`, no `stopAllActive`, no `rescheduleSnooze`.

Guards, each a one-line early return when `isRehearsal`: top of `rescheduleSnooze`, top of `cancelPendingSnooze`, top of `saveConversation`. In `handleCompliance` and `handleOverride`, wrap the `stopAllActive` call in `if !isRehearsal`. In `resolveSnooze`, skip the `Task { rescheduleSnooze }` and the `alarm.snoozedUntil` write when `isRehearsal`; keep the "Okay — N more minutes" message and `isCompleted = true`. Pass `firedAt: isRehearsal ? rehearsalStart : nil` to `buildSystemPrompt`.

Logging: add `private func logConversation(_ text: String, isError: Bool = false) async` that prefixes `"rehearsal: "` when `isRehearsal` and calls `LogService.shared.log(.conversation, …, alarmId: alarm?.id.uuidString, isError:)`; route every `.conversation` log call in the file through it.

- [ ] **Step 2: Conversation view**

`alarm`: when `isRehearsal`, return `appState.rehearsalAlarm`; else the existing fetch. `onAppear`: when `isRehearsal`, `vm.setup(alarm: appState.rehearsalAlarm!, isRehearsal: true, context:)` (guard-let, and if nil, dismiss); else the existing call. `topBar`: the label text is `(isRehearsal ? "REHEARSAL" : "ALARM FIRING") · mm:ss`; when `isRehearsal`, a trailing `Button { tts.stop(); speech.cancelListening(); appState.dismissAlarm(); dismiss() } label: { Text("END").kicker(L.Palette.muted) }.buttonStyle(.plain)` replaces the `Spacer()`'s right side. `MainTabView`: `ConversationView(alarmId: session.alarmId, isRehearsal: session.isRehearsal)`.

- [ ] **Step 3: Compile check, logic tests, grep, commit**

Compile check → `BUILD SUCCEEDED`; `scripts/bump-tests/run.sh` → `ALL PASSED`; `grep -n "LogService.shared.log(.conversation" ViewModels/ConversationViewModel.swift` → only the one inside `logConversation`. Then:
```bash
git add AccountabilityAlarm/AccountabilityAlarm/ViewModels/ConversationViewModel.swift AccountabilityAlarm/AccountabilityAlarm/Views/ConversationView.swift AccountabilityAlarm/AccountabilityAlarm/Views/MainTabView.swift
git commit -m "Rehearsal: side-effect-free conversation path, REHEARSAL top bar with END"
```

---

### Task 3: Entry points, launch hook, and the side-effect check

**Files:**
- Modify: `Views/AlarmListView.swift` (`fireAlarm` :163-166; the row's play `Button` ~:249-256 inside `LAlarmRow`; the `Section` after `newCommitmentButton` ~:77-80; `onAppear` launch hooks ~:99-104)

**Interfaces:**
- Consumes: `appState.rehearse(alarm:)`, `appState.rehearseSample()` (Task 1).

- [ ] **Step 1: Entry points**

`fireAlarm(_:)` calls `appState.rehearse(alarm: alarm)`; update its comment ("Rehearse: opens the conversation with no ledger writes"). The play button in `LAlarmRow` gets `.accessibilityLabel("Rehearse")`. Add `seeHowItWorksRow` after `newCommitmentButton` in the same `Section`, with the same `listRowInsets/Background/Separator` modifiers: a `Button { appState.rehearseSample() }` whose label is an `HStack(spacing: 8) { L.PlayTri(size: 8, color: L.Palette.muted); Text("SEE HOW IT WORKS").kicker(L.Palette.muted) }` with `.padding(.horizontal, L.Space.pageH).padding(.vertical, 12)`, `.buttonStyle(.plain)`. Add `--rehearse-sample` to the launch-argument hook: `if args.contains("--rehearse-sample") { appState.rehearseSample() }`.

- [ ] **Step 2: Simulator run and screenshot**

Build, install, then:
```bash
UDID=83653F8D-88B1-4506-A703-70F1DF8B203E; B=com.blaizew.AccountabilityAlarm
xcrun simctl terminate $UDID $B 2>/dev/null; xcrun simctl launch $UDID $B --rehearse-sample; sleep 8
xcrun simctl io $UDID screenshot /tmp/claude-501/dd-fist/shots/rehearsal.png
```
Read the PNG. Expected: `REHEARSAL · 00:0x` top bar with `END` at the right, the header `h:mm AM/PM · Morning run` showing the current time, the Coach's opening question in the chat, voice/text tabs, and the wide Snooze button. If the Coach message has not arrived (API latency), wait 5 s and re-shoot once. If the API key is missing in the simulator build, say so in the report and show the screen without the Coach message.

- [ ] **Step 3: Side-effect check**

```bash
xcrun simctl terminate $UDID $B
D=$(xcrun simctl get_app_container $UDID $B data)/Library/Application\ Support/default.store
sqlite3 "$D" "select count(*) from ZALARMEVENT; select count(*) from ZALARM where ZLABEL='Morning run';"
```
Record the `ZALARMEVENT` count, run the `--rehearse-sample` launch again, wait 8 s, terminate, and query again. Expected: the `ZALARMEVENT` count is unchanged and the `Morning run` count is 0 both times. Put both outputs in the report.

- [ ] **Step 4: Compile check and commit**

```bash
git add AccountabilityAlarm/AccountabilityAlarm/Views/AlarmListView.swift
git commit -m "Rehearsal: row play button rehearses; See how it works row; --rehearse-sample hook"
```

---

### Task 4: Device install and Blaize's check (coordinator)

- [ ] Device build with `-allowProvisioningUpdates` for bPhone2 (`00008101-000209482693601E`) and `xcrun devicectl device install app`.
- [ ] Blaize taps the play glyph on a real alarm, talks to the Coach, bumps the fist, then opens History and confirms no new entry. Then taps SEE HOW IT WORKS once.
- [ ] Merge and push only when Blaize says so.
