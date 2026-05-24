# Handoff: Accountability Alarm — LEDGER

A native iOS alarm app where each alarm carries a **reason** (a voice/text recording of why the user set it). When the alarm fires, an LLM uses that reason to argue with the user — citing their own words back at them — until the user either complies, overrides with an explicit reason, or snoozes.

This handoff documents the **LEDGER** visual direction: a dense, monospace, terminal-influenced aesthetic in the spirit of Linear. Dark mode only.

---

## About the design files

The HTML files in this bundle are **design references**, not production code. They were built with React + Babel transpiled in-browser, inline styles, and synthetic data. Treat them as the visual + behavioural specification for the real implementation.

The target is **a native iOS app** (the original brief is included as `ORIGINAL_BRIEF.md`). Build it in SwiftUI (recommended) or your team's preferred iOS stack. The LLM, speech-to-text, alarm scheduling, persistence, and notification escalation all need real implementations — the prototype fakes them.

If the team decides to ship as a React Native / Flutter / web app instead, the design translates fine; just preserve the typography, density, and behaviour described below.

## Fidelity

**Hi-fi.** Colours, type ramp, spacing, and screen layouts are all final. Reproduce them pixel-close. The synthetic copy (alarm labels, reason text, AI conversation lines) is illustrative — replace with real user content and a real LLM at runtime.

---

## What the product does (read this first)

The novel mechanic is **the alarm argues with you on the LLM's authority, but with *your own* reasoning.**

1. **At setup**, the user records *why* this alarm matters. Free-form text or voice (transcribed). The reason is mandatory.
   - Example: *"I want to be in bed by 10 so I can wake at 6 and write before work. Last week I averaged 5.5 hours and my standups were foggy. The 'one more thing' on Claude Code is what keeps me up — it'll still be there tomorrow."*

2. **When the alarm fires**, instead of just playing a sound, the phone opens a full-screen **Conversation** screen. An LLM, prompted with the user's reason + their alarm metadata, opens with a gentle nudge.

3. **The user responds** (voice or text). The LLM escalates through 4 named stages — **Nudge → Math → Mirror → Preview** — each one drawing on a different rhetorical move:
   - **Nudge**: simple reminder of the reason.
   - **Math**: the concrete cost of delay (e.g., "five more minutes = 6:35 wake = no writing block").
   - **Mirror**: quote the user's own words back at them, with a citation.
   - **Preview**: forecast tomorrow's regret ("you'll be foggy at standup again").

4. **Three outcomes** end the conversation:
   - **Comply** — logged as success; streak increments.
   - **Snooze (9m)** — logged; resumes at next snooze interval.
   - **Override** — *requires* a one-line written reason ("on-call, pager fire"). Logged for future-self to read.

5. **History** shows the ledger of past firings: outcome per event, plus aggregate rate (% complied), avg snoozes, avg time-to-comply.

---

## Screens

Four screens total. The prototype is `Ledger Prototype.html` — open it in a browser to interact with the live design.

### 1. Alarm List (`LList`)

The home screen.

**Layout**
- Vertical scroll, fills the device viewport.
- Top status bar (iOS system).
- Header bar with all-caps mono microcopy (`ALARMS · 4/5 ON` on the left, current local time on the right). 1px bottom hairline.
- Section title: kicker line (`// next: bed — write at 6 am · 10:00 pm`) + large mono title (`Alarms`) + count badge (`[5]`).
- A vertical stack of alarm rows.
- A dashed-border "new commitment" button at the bottom of the scroll.
- Fixed bottom tab bar: `Alarms` / `History`.

**Alarm row anatomy** (top → bottom)
- 2px-wide vertical stripe on the left edge, in the alarm's escalation colour (only when alarm is on).
- Meta line (10.5px mono uppercase, `letter-spacing: 0.4px`):
  - Left cluster: `#NNN` index · day-range · escalation glyph + label.
  - Right cluster: a 24×18 "fire" button (▶ glyph) and a toggle pill (30×16, white when on).
- Time + label row: 32px mono number (`10:00`), 14px AM/PM suffix in muted, then a 13px muted mono label clipped with ellipsis.
- Reason snippet: 12px muted mono, 10px left padding, 1px left hairline, quoted.
- Tail line: 10.5px mono uppercase, three columns: `last ● <outcome>` (coloured by outcome) · `streak <N>` · `edit ›` (right-aligned, dimmer).

**Interactions**
- Tap the row → opens Edit for that alarm.
- Tap the toggle pill → flips on/off (no nav).
- Tap the ▶ button → fires the alarm (opens Conversation screen). In production this would be a **dev/test affordance** only — real alarms fire on schedule.
- Tap "new commitment" → opens Edit in new-alarm mode.

---

### 2. Alarm Edit (`LEdit`)

Scrolling form. Top-bar `Cancel` / `Save →`. Save is dim until the draft differs from the saved alarm.

Sections, each preceded by a `§ NN · <name>` kicker (10.5px mono uppercase, dim):

**§ 01 · Fires at**
Two scroll columns side by side — hours (1–12, wraps) and minutes (0–59, wraps) — each shows three rows: previous (dimmer), selected (white, brighter, with 1px top + bottom hairline), next (dimmer). A 38px colon between them. To the right: a tappable `AM` / `PM` chip.

Real implementation should use the platform's native picker (UIDatePicker style on iOS). Keep the dense visual.

**§ 02 · Repeat**
Seven equal-width 38px-tall day chips (S M T W T F S). Selected = white background, dark text. Deselected = transparent with 1px hair border.

**§ 03 · Why this matters · required**
The centrepiece. A textarea (5 rows visible, 13px mono, 1.55 line-height) on the slightly-raised `#121216` background. Live word count below. A `● REC` chip to its right starts/stops voice capture (mock in prototype — wire to speech-to-text in production). A 64-bar waveform sits below, partially-filled to indicate "speech detected." This is the field the LLM uses as its source of authority. **Mandatory; Save remains disabled until non-empty.**

**§ 04 · Label**
Single-line text input. 15px mono, white. Transparent background.

**§ 05 · Escalation style**
Three radio-style rows: **Gentle / Firm / Relentless.** Selected row gets a `#18181d` background and a 1px subtle border. Each row: a coloured glyph (leaf / hand / flame), bold label, dim description, white check at the right when selected. Escalation maps to LLM system-prompt aggressiveness — see "LLM contract" below.

**Delete commitment** button at the bottom — destructive, mono uppercase, red border.

**Layout**
- Outer container is a flex column with `paddingTop: 50` (status bar), top bar pinned (`LTopBar`), middle is a `flex: 1, min-height: 0, overflow-y: auto` region, and a 34px bottom safe-area for the home indicator.

---

### 3. Conversation (`LConv`)

The full-screen alarm experience. Replaces the standard iOS alarm UI when the alarm fires.

**Layout**
- Background: solid `#0a0a0c` at the Nudge ring. As the conversation escalates to Mirror and Preview, a subtle radial wash bleeds in from the top — amber at Mirror, red at Preview. Math has a very faint straw wash. Implemented as `radial-gradient(120% 60% at 50% 0%, <colour>/0.10–0.22, transparent 60%)` layered over the base.
- Status bar (iOS).
- Top bar: left side shows live elapsed clock `ALARM FIRING · +Nm · MM:SS`. Right side: `Dismiss ×` (tappable). The left side text colour shifts to the Preview red when ringIdx hits 3.
- **Ring meter**: a 4-segment progress bar. The current segment is 4px tall, the rest are 2px. Reached segments fill in their ring colour; future segments use the dim hairline. Below the bar: `Ring N/4 · <name>` left-aligned, `<descriptor>` right-aligned. All mono 10.5px uppercase.
- Alarm header card: `Now firing` kicker, `<time> · <label>` (truncates with ellipsis), reason snippet in a left-bordered quote block. Bottom hairline.
- **Messages region**: absolutely positioned between header and bottom controls, scrolls. Each message is rendered by `LMessage`:
  - Meta row above: speaker label (`> past-self · <ring>` in ring colour for AI; `you` in muted for user) on the left, 2-digit index on the right.
  - Body: 14px mono, 1.5 line-height. **AI messages**: white, weight grows with ring (400 → 500 → 600 → 700). **User messages**: muted, left-indented 24px.
  - If the AI message has a citation: a superscript `[1]` in the ring colour, then below the body a 2px left-bordered block in the ring colour, 10.5px mono muted: `[1] <citation>` (e.g. *"10:00 PM · the night you set this alarm"*).
- **Bottom panel** (fixed): mode tabs `● voice` / `text`, then the input region, then three outcome buttons.
  - Voice mode: a 56×56 circular mic button in the **current ring colour**. Beside it, a 28-bar reactive waveform. Tap mic to "submit" your voice turn.
  - Text mode: a single-line input + `send →` button (white background when text is non-empty).
  - Three buttons: `Snooze · 9m` (outline), `Comply ↑` (filled white), `Override` (outline). Override opens a one-line text capture overlay.

**The override overlay** (replaces the bottom panel in place when triggered)
- Red label `● override · logged`.
- 13px prompt: *"One line. Future-you will read this."*
- Auto-focused text input with red border.
- Cancel / `Override ✓` buttons (red filled on confirm).
- Submitting logs the event with `outcome: "overridden"` + `overrideReason: <text>` so it appears in History.

**Interactions**
- The prototype's "tap mic to advance" is a stand-in for: *user speaks → speech-to-text → send transcript + state to LLM → render next AI reply.*
- The conversation ends in one of: comply / snooze / override / dismiss. Each writes a history event with the appropriate outcome and the ring it ended on.
- If the user runs out the LLM script (prototype) or the LLM gives up (production), the bottom mic dims and copy switches to *"say anything · or pick below."* The decision is then 100% on the user.

---

### 4. History (`LHistory`)

**Layout**
- Top bar: `HISTORY · LAST 30D` (right side intentionally empty — no aggregate count exposed; the user shouldn't be conditioned to hit a "fires" leaderboard).
- Title block: kicker `// across N alarms`, title `History`.
- **Stat trio** (3 cells in a horizontal grid, separated by hairlines):
  1. **Complied** — large green number with `%` suffix in muted; subtitle `complied X/Y` (raw fractions).
  2. **Avg snoozes** — number to 1 decimal; subtitle `<sum> total`.
  3. **Avg comply-t** — minutes from alarm-fire to comply; subtitle `<count> samples`.
  All derived from `events`, not hardcoded.
- **28-day pattern grid**: 4 rows × 7 columns of small squares, colour-coded by the outcome of that day's first alarm. Legend below in a single hairline-uppercase row. Today's cell has a 1px white outline.
- **Recent ledger**: scrolling list of past events. Each row: 2-digit index, date (mono, ~78px wide), time + label (truncates), optional ring-colour square, then the outcome chip in its colour. Overridden events also show the override reason inline in dim.
- Bottom tab bar.

---

## Design tokens

### Colours (oklch + hex)

```ts
// Backgrounds (dark)
bg        #0a0a0c   // base
bg2       #121216   // raised
bg3       #18181d   // raised + 1
bg4       #1e1e25   // raised + 2

// Hairlines
hair      rgba(255,255,255,0.06)
hair2     rgba(255,255,255,0.12)
hair3     rgba(255,255,255,0.18)

// Text
fg        #e9e9ec               // headings, primary
muted     rgba(232,232,236,0.58)
dim       rgba(232,232,236,0.36)
dimmer    rgba(232,232,236,0.22)

// Ring colours (use for escalation, message weight, stat semantics)
ringNudge    oklch(0.74 0.08 240)   // cool blue
ringMath     oklch(0.78 0.07 90)    // straw
ringMirror   oklch(0.72 0.13 55)    // amber
ringPreview  oklch(0.65 0.18 28)    // red

// Outcomes
goodGreen    oklch(0.72 0.12 145)
warnYellow   oklch(0.78 0.13 88)
badRed       oklch(0.65 0.18 28)   // same as ringPreview by design
```

### Escalation style → colour map

| style       | colour      | LLM behaviour                               |
| ----------- | ----------- | ------------------------------------------- |
| Gentle      | ringNudge   | Asks once. Accepts an override quickly.     |
| Firm        | ringMirror  | Pushes back twice. Wants a reason.          |
| Relentless  | ringPreview | Won't accept an override without a plan.    |

### Typography

```
Mono (primary): JetBrains Mono (300, 400, 500, 600, 700)
Sans (rarely used here): Inter Tight (300, 400, 500, 600, 700)
```

The design is **mono-first**. Use the sans only in non-LEDGER contexts. On iOS, SF Mono is an acceptable fallback if JetBrains Mono isn't bundled, but JetBrains Mono is preferred for its consistent ink density.

**Type ramp** (all mono unless noted):

| use                   | size | weight | tracking | transform   |
| --------------------- | ---- | ------ | -------- | ----------- |
| Hero number (time)    | 64   | 300–500| -2       | —           |
| Time in row           | 32   | 400    | -0.8     | —           |
| Section title         | 26   | 500    | -0.4     | —           |
| Alarm header          | 18   | 500    | -0.3     | —           |
| Body / message        | 14   | 400–700| —        | —           |
| Reason snippet        | 12   | 400    | —        | —           |
| Microcopy / kicker    | 10.5 | 400    | 0.6      | uppercase   |
| Sublabel              | 9.5  | 400    | 0.4–0.6  | uppercase   |
| Stat number           | 24   | 500    | —        | tabular-nums|
| Outcome chip          | 10–10.5 | 400 | 0.4      | uppercase   |

All numerics that change must use `font-variant-numeric: tabular-nums`.

### Spacing

There is no formal scale — the design uses these values consistently:
`2, 4, 6, 8, 10, 12, 14, 16, 18, 20, 24, 28, 30, 38, 50`.

Treat the **16px horizontal page padding** and **14px vertical row padding** as canonical.

### Borders, radii, shadows

- Border radius: **0 everywhere.** No rounded corners. Toggle pills are an exception (`16` rounded).
- Borders: `1px solid <hair|hair2>` — always one of the three hairlines.
- **No drop shadows.** Use hairlines to separate planes.

### Icons / glyphs

All glyphs are inline SVG, drawn at small sizes (9–22px), 1–1.2px stroke, square caps. See `lGlyph` in `ledger-shared.jsx` for the full set: leaf (gentle), hand (firm), flame (relentless), chev, dot, plus, mic, play, x.

**Do not import an off-the-shelf icon set** — Material/SF/Lucide will fight the aesthetic. If you need a new glyph, draw it to match: 1px stroke, square endpoints, ~10–14px box.

---

## State

```ts
type Alarm = {
  id: string;
  time: "HH:MM";              // 12h
  period: "AM" | "PM";
  label: string;
  daysLabel: string;          // human, e.g. "Mon – Fri"
  daysSet: number[];          // 0-indexed; Sun = 0
  escalation: "gentle" | "firm" | "relentless";
  on: boolean;
  lastOutcome: "complied" | "snoozed" | "ignored" | "overridden";
  streak: number;             // consecutive complies
  reason: string;             // the LLM's source of truth — required, non-empty
  reasonShort: string;        // first-sentence summary, auto-derived
};

type HistoryEvent = {
  id: string;
  alarmId: string;
  date: string;               // human "Tue · 21 May"
  time: string;               // "10:00 PM"
  label: string;              // copied from alarm at fire-time
  outcome: "complied" | "snoozed_then_complied" | "overridden" | "ignored";
  snoozes: number;
  ring: "nudge" | "math" | "mirror" | "preview" | null; // ring it ended on; null if ignored
  overrideReason?: string;
  durMin: number | null;      // null unless complied with timing data
};
```

### State transitions

- **Toggle**: flips `alarm.on`. No history side-effect.
- **Edit save**: replaces alarm in collection; preserves `lastOutcome`, `streak`.
- **Edit delete**: removes alarm; existing history events keep their `alarmId` pointer (treat as tombstoned).
- **Fire**: opens conversation screen; no state change yet.
- **Resolve**: writes a `HistoryEvent` based on outcome.
  - `comply` → `outcome: "complied"`, `snoozes: 0`, `streak += 1`
  - `snooze` → `outcome: "snoozed_then_complied"` (logged once the resulting next-fire resolves; in the prototype this is conflated for simplicity), `snoozes: 1`, `streak` unchanged
  - `override` → `outcome: "overridden"`, `overrideReason: <text>`, `streak = 0`
  - `dismiss` → `outcome: "ignored"`, `streak = 0`

Streaks need a real production rule: probably "consecutive non-overridden, non-ignored firings."

---

## LLM contract

The most important piece of the build. Sketch only — the team should iterate.

### Inputs to the LLM at fire-time

```jsonc
{
  "alarm": {
    "label": "Bed — write at 6 AM",
    "time": "10:00 PM",
    "reason": "<the full reason text the user recorded>",
    "escalation": "firm",
    "createdAt": "<iso>"
  },
  "context": {
    "now": "<iso>",
    "minutesPastFire": 3,
    "ring": "nudge",                       // or math/mirror/preview
    "recentHistory": [                     // last 7 events for this alarm
      { "outcome": "complied", "date": "..." },
      { "outcome": "ignored",  "date": "..." }
    ]
  },
  "conversation": [
    { "role": "ai",   "text": "It's 10:03. You set this so you could wake at 6 and write." },
    { "role": "user", "text": "Just one more deploy." }
  ]
}
```

### Ring system prompt (sketch)

- **Nudge (ring 0)**: One short sentence. Reference the reason or the label. No data. No moralising.
- **Math (ring 1, +10 min)**: One paragraph. Lean on concrete consequence. If the reason mentions sleep, write, exercise, family, etc., compute the cost. If `recentHistory` shows a pattern, surface it ("you've done that 4 of the last 7 days").
- **Mirror (ring 2, +20 min)**: Quote the user's `reason` verbatim. The UI will render a citation block beneath your message — emit a citation field `cite: "<short anchor>"` in your structured output (e.g. *"10:00 PM · the night you set this"*).
- **Preview (ring 3, +30 min)**: Forecast tomorrow. Use the reason's stated stakes (writing block, standup, kids' dinner, etc.). One paragraph.

The escalation style modifies tone:
- **gentle**: warm, brief, accept "no" after one round.
- **firm**: matter-of-fact, push back twice.
- **relentless**: insistent; if the user tries to override, ask for an alternative plan ("when, then?") before allowing it.

### Output schema

```ts
{
  text: string;
  cite?: string;          // only for Mirror ring messages
  giveUp?: boolean;       // true if the LLM judges the user has good reason; UI dims the mic
}
```

### Cost / latency

Each ring → at most 1 LLM call. A conversation rarely exceeds 6 turns. Voice transcription is the slower hop — favour streaming STT into the prompt so the model can start before the user finishes talking.

### Refusal cases

If the user's `reason` is empty (shouldn't happen — UI blocks it) or insulting / abusive, the LLM should default to a generic Nudge and not escalate.

---

## Animations & transitions

The prototype is largely static. The few animations to ship:

- **Ring meter segment advance**: 300ms ease-out; the active segment grows from 2 → 4px tall, the colour bleeds in.
- **Background ring wash**: 400ms ease-out when the ring index increments. (Implement as the wash gradient interpolating opacity, not crossfade — the base solid stays.)
- **Toast**: slide up + fade in (~280ms), hold ~1.7s, fade out (~400ms). One-toast policy; new toast pre-empts the current.
- **Toggle pill**: 120ms ease for both the background and the handle slide.
- **Override panel reveal**: slide up from the bottom over 200ms, replacing the input region. Auto-focus the text field.

Avoid spring physics — this is a precise, mono aesthetic, not a friendly one.

---

## What's *not* in the prototype but the real app needs

- **System alarm primitives**: scheduling, ringing through Silent mode, surviving force-quit, Live Activities / lockscreen presence. iOS `UNUserNotificationCenter` won't be enough on its own — investigate `AVAudioSession` background audio for ring playback.
- **Speech-to-text**: SFSpeechRecognizer (on-device when possible) for both reason capture and conversational replies.
- **Voice playback option**: the brief notes the user may want to *hear* their own original reason. Surface that as a tap-target on the conversation header (play the user's stored audio).
- **Audio storage**: opus or m4a; one file per alarm reason; encrypted-at-rest.
- **Persistence**: Core Data or SwiftData. Schema follows the `Alarm` / `HistoryEvent` types above.
- **Permissions flow**: microphone, notifications, focus/critical-alert entitlement.
- **Real LLM call**: see the contract above.
- **Onboarding**: not designed in this prototype; the brief covers the desired feel ("a single screen, voice button big, one sentence of explanation").

---

## Assets

No external assets. All glyphs are inline SVG (defined in `ledger-shared.jsx`).
Fonts: `JetBrains Mono` and `Inter Tight` from Google Fonts — for iOS, bundle the .ttf files directly.

---

## Files in this bundle

| file                              | what it is                                                  |
| --------------------------------- | ----------------------------------------------------------- |
| `Ledger Prototype.html`           | The interactive prototype. Open in a browser.               |
| `ledger-shared.jsx`               | Tokens, glyphs, demo data, conversation scripts.            |
| `ledger-screens.jsx`              | All four screen components and shared chrome bits.          |
| `ios-frame.jsx`                   | iOS 26 device frame used to host the prototype. Not needed in production. |
| `ORIGINAL_BRIEF.md`               | The original product brief that this design responds to.    |
| `README.md`                       | This document.                                              |

To run the prototype: open `Ledger Prototype.html` in any modern browser. No build step.

---

## Open questions for the product team

1. **Snooze accounting** — should `outcome: "snoozed_then_complied"` only be written when the eventual fire is complied with, or should the prototype's simplification (write it on snooze) be kept?
2. **Override "alternative plan" loop** — for the Relentless escalation, should the LLM literally block the override until the user provides a re-scheduled time, or just nudge for one?
3. **Tone tuning** — the prototype's draft conversation lines are illustrative. The team should iterate on the LLM's voice with real users.
4. **Critical-alert entitlement** — Apple gates this. Without it, the alarm can't ring through Silent mode. Plan the entitlement application in parallel with the build.
