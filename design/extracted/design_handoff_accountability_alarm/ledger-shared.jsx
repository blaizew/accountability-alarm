// ledger-shared.jsx — palette, fonts, glyphs, demo data, conversation scripts
// (Renamed from screens-ledger.jsx tokens so the prototype can co-exist.)

const lPalette = {
  bg:       "#0a0a0c",
  bg2:      "#121216",
  bg3:      "#18181d",
  bg4:      "#1e1e25",
  hair:     "rgba(255,255,255,0.06)",
  hair2:    "rgba(255,255,255,0.12)",
  hair3:    "rgba(255,255,255,0.18)",
  fg:       "#e9e9ec",
  muted:    "rgba(232,232,236,0.58)",
  dim:      "rgba(232,232,236,0.36)",
  dimmer:   "rgba(232,232,236,0.22)",
  accent:   "#ffffff",
  ringNudge:   "oklch(0.74 0.08 240)",   // cool
  ringMath:    "oklch(0.78 0.07 90)",    // straw
  ringMirror:  "oklch(0.72 0.13 55)",    // amber
  ringPreview: "oklch(0.65 0.18 28)",    // red
  goodGreen:   "oklch(0.72 0.12 145)",
  warnYellow:  "oklch(0.78 0.13 88)",
  badRed:      "oklch(0.65 0.18 28)",
};

const lFonts = {
  mono: '"JetBrains Mono", "IBM Plex Mono", ui-monospace, monospace',
  sans: '"Inter Tight", -apple-system, system-ui, sans-serif',
};

const lGlyph = {
  leaf:  ({ size = 10, c = "currentColor" }) => (
    <svg width={size} height={size} viewBox="0 0 10 10" fill="none">
      <path d="M1 9 Q1 1 9 1 Q9 9 1 9 Z" stroke={c} strokeWidth="1" />
      <path d="M1 9 L9 1" stroke={c} strokeWidth="0.8" />
    </svg>
  ),
  hand:  ({ size = 10, c = "currentColor" }) => (
    <svg width={size} height={size} viewBox="0 0 10 10" fill="none">
      <rect x="2.5" y="2" width="5" height="6.5" rx="1" stroke={c} strokeWidth="1" />
      <path d="M5 4.5v2" stroke={c} strokeWidth="1" />
    </svg>
  ),
  flame: ({ size = 10, c = "currentColor" }) => (
    <svg width={size} height={size} viewBox="0 0 10 10" fill="none">
      <path d="M5 1 Q2 4 2 6.5 Q2 9 5 9 Q8 9 8 6.5 Q8 4 5 1 Z" stroke={c} strokeWidth="1" />
    </svg>
  ),
  chev:  ({ size = 10, c = "currentColor" }) => (
    <svg width={size} height={size} viewBox="0 0 10 10" fill="none">
      <path d="M3 2l4 3-4 3" stroke={c} strokeWidth="1.2" strokeLinecap="square" />
    </svg>
  ),
  chevL: ({ size = 10, c = "currentColor" }) => (
    <svg width={size} height={size} viewBox="0 0 10 10" fill="none">
      <path d="M7 2L3 5l4 3" stroke={c} strokeWidth="1.2" strokeLinecap="square" />
    </svg>
  ),
  dot:   ({ size = 6, c = "currentColor" }) => (
    <svg width={size} height={size} viewBox="0 0 6 6"><circle cx="3" cy="3" r="3" fill={c}/></svg>
  ),
  plus:  ({ size = 12, c = "currentColor" }) => (
    <svg width={size} height={size} viewBox="0 0 12 12" fill="none">
      <path d="M6 1v10M1 6h10" stroke={c} strokeWidth="1.4" strokeLinecap="square" />
    </svg>
  ),
  mic:   ({ size = 16, c = "currentColor" }) => (
    <svg width={size} height={size} viewBox="0 0 16 16" fill="none">
      <rect x="6" y="2" width="4" height="8" rx="2" stroke={c} strokeWidth="1.2"/>
      <path d="M3 8c0 2.8 2.2 5 5 5s5-2.2 5-5M8 13v2" stroke={c} strokeWidth="1.2" strokeLinecap="square"/>
    </svg>
  ),
  play:  ({ size = 9, c = "currentColor" }) => (
    <svg width={size} height={size} viewBox="0 0 9 9" fill={c}>
      <path d="M2 1 L8 4.5 L2 8 Z"/>
    </svg>
  ),
  x:     ({ size = 10, c = "currentColor" }) => (
    <svg width={size} height={size} viewBox="0 0 10 10" fill="none">
      <path d="M1 1l8 8M9 1l-8 8" stroke={c} strokeWidth="1.2" strokeLinecap="square"/>
    </svg>
  ),
};

function lStyleGlyph(style, size = 10, c = "currentColor") {
  if (style === "gentle") return <lGlyph.leaf size={size} c={c} />;
  if (style === "firm")   return <lGlyph.hand size={size} c={c} />;
  return <lGlyph.flame size={size} c={c} />;
}

function lRingColor(id) {
  return id === "nudge"   ? lPalette.ringNudge
       : id === "math"    ? lPalette.ringMath
       : id === "mirror"  ? lPalette.ringMirror
       : id === "preview" ? lPalette.ringPreview
       : lPalette.dim;
}

const RINGS_L = [
  { id: "nudge",   label: "Nudge",   sub: "Gentle reminder",   offsetMin: 0  },
  { id: "math",    label: "Math",    sub: "What it costs",     offsetMin: 10 },
  { id: "mirror",  label: "Mirror",  sub: "Your own words",    offsetMin: 20 },
  { id: "preview", label: "Preview", sub: "Tomorrow preview",  offsetMin: 30 },
];

const STYLES_L = [
  { id: "gentle",     label: "Gentle",     desc: "Asks once. Accepts an override quickly." },
  { id: "firm",       label: "Firm",       desc: "Pushes back twice. Wants a reason." },
  { id: "relentless", label: "Relentless", desc: "Won't accept an override without a plan." },
];

const DAYS_L = ["S", "M", "T", "W", "T", "F", "S"];

// ──────────────────────────────────────────────────────────────
// Demo alarm data — varied (not all bedtime)
// ──────────────────────────────────────────────────────────────
const DEMO_ALARMS = [
  {
    id: "a1",
    time: "10:00", period: "PM",
    label: "Bed — write at 6 AM",
    daysLabel: "Mon – Fri",
    daysSet: [1,2,3,4,5],
    escalation: "firm",
    on: true,
    lastOutcome: "complied", streak: 3,
    reason: "I want to be in bed by 10 so I can wake at 6 and write before work. Last week I averaged 5.5 hours and standups were foggy by 2 PM. The 'one more thing' on Claude Code is what keeps me up — it'll still be there tomorrow.",
    reasonShort: "Wake at 6 to write. The deploy can wait.",
    sleep: { enabled: true, target: 8.0, morning: { name: "Writing block", time: "06:15" } },
  },
  {
    id: "a2",
    time: "02:30", period: "PM",
    label: "Walk before standup",
    daysLabel: "Mon – Fri",
    daysSet: [1,2,3,4,5],
    escalation: "gentle",
    on: true,
    lastOutcome: "snoozed", streak: 0,
    reason: "I get foggy after lunch and I know it. Twenty minutes outside or the afternoon is gone. Standup at 3:30 — I want to actually contribute.",
    reasonShort: "Outside or the afternoon is gone.",
    sleep: { enabled: false },
  },
  {
    id: "a3",
    time: "06:00", period: "PM",
    label: "Stop work · see family",
    daysLabel: "Mon – Fri",
    daysSet: [1,2,3,4,5],
    escalation: "relentless",
    on: true,
    lastOutcome: "overridden", streak: 0,
    reason: "My kids are 7 and 5 and I keep saying 'ten more minutes.' The bug is not more important than dinner. I will close the laptop. There is no production fire that can't wait until 8.",
    reasonShort: "Kids > the bug. Close the laptop.",
    sleep: { enabled: false },
  },
  {
    id: "a4",
    time: "09:00", period: "AM",
    label: "Writing block",
    daysLabel: "Mon – Fri",
    daysSet: [1,2,3,4,5],
    escalation: "firm",
    on: true,
    lastOutcome: "complied", streak: 2,
    reason: "Pages first, code second. I have one hour and I've been ducking it for three weeks. The Slack messages can wait an hour.",
    reasonShort: "Pages first, code second.",
    sleep: { enabled: false },
  },
  {
    id: "a5",
    time: "12:00", period: "PM",
    label: "Lunch · away from desk",
    daysLabel: "Mon – Fri",
    daysSet: [1,2,3,4,5],
    escalation: "gentle",
    on: false,
    lastOutcome: "ignored", streak: 0,
    reason: "Eat away from the screen or the afternoon disappears in a haze.",
    reasonShort: "Eat away from the screen.",
    sleep: { enabled: false },
  },
];

// ──────────────────────────────────────────────────────────────
// Conversation scripts — keyed by alarm id. Each script is a
// sequence of {role, ring, text, cite?} that plays out as the
// user interacts. Voice replies (user) are pre-baked to keep
// the demo deterministic.
// ──────────────────────────────────────────────────────────────
const CONV_SCRIPTS = {
  a1: [
    { role: "ai",   ring: "nudge",   text: "It's 10:03. You set this so you could wake at 6 and write." },
    { role: "user", ring: "nudge",   text: "Just one more deploy." },
    { role: "ai",   ring: "math",    text: "Five more minutes and you wake at 6:35 minimum — you lose the writing block. You've done that 4 of the last 7 days." },
    { role: "user", ring: "math",    text: "Then I'll write tomorrow." },
    { role: "ai",   ring: "mirror",  text: "You said: \"it'll still be there tomorrow.\" That was about the code. The writing is what you said matters.", cite: "10:00 PM · the night you set this alarm" },
    { role: "user", ring: "mirror",  text: "Fine. Just let me commit this." },
    { role: "ai",   ring: "preview", text: "At 6 AM you'll be sleep-debt. At 2 PM standup you'll be foggy again. That's the pattern you said you wanted to be done with." },
  ],
  a2: [
    { role: "ai",   ring: "nudge",   text: "2:30. Twenty minutes outside before standup — you said that's what keeps you sharp." },
    { role: "user", ring: "nudge",   text: "I'm in flow. Five more minutes." },
    { role: "ai",   ring: "math",    text: "Standup is at 3:30. Twenty minutes walking = back at 2:50, ten to clean up. You said you wanted to actually contribute." },
    { role: "user", ring: "math",    text: "I'll just push through." },
    { role: "ai",   ring: "mirror",  text: "You said: \"outside or the afternoon is gone.\" That's why this alarm exists.", cite: "when you set this alarm" },
  ],
  a3: [
    { role: "ai",   ring: "nudge",   text: "6:00. Laptop closed. Your daughter is going to ask where you are." },
    { role: "user", ring: "nudge",   text: "Ten more minutes — I'm almost done." },
    { role: "ai",   ring: "math",    text: "You said \"ten more minutes\" four times this week. Average actual: 47 minutes. By the time you sit down, dinner's over." },
    { role: "user", ring: "math",    text: "This one's actually quick." },
    { role: "ai",   ring: "mirror",  text: "You said: \"the bug is not more important than dinner. There is no production fire that can't wait until 8.\"", cite: "the night you set this" },
    { role: "user", ring: "mirror",  text: "It can wait until 8." },
    { role: "ai",   ring: "preview", text: "Good. Want me to set a 'pick up the laptop at 8' reminder so you don't lose the thread?" },
  ],
  a4: [
    { role: "ai",   ring: "nudge",   text: "9:00. The hour you set aside. Slack will keep." },
    { role: "user", ring: "nudge",   text: "Just answering one thing first." },
    { role: "ai",   ring: "math",    text: "Three weeks of ducking this hour. You have one hour. If you start now you have 58 minutes. If you finish Slack first you have 41." },
    { role: "user", ring: "math",    text: "Fine. Starting." },
  ],
  a5: [
    { role: "ai",   ring: "nudge",   text: "Lunch. Phone in another room, screen off." },
  ],
};

// ──────────────────────────────────────────────────────────────
// History (mixed across the alarms above, more varied)
// ──────────────────────────────────────────────────────────────
const HISTORY_L = [
  { id: "h1", alarmId: "a1", date: "Tue · 21 May", time: "10:00 PM", label: "Bed",          outcome: "complied", snoozes: 0, durMin: 47, ring: "mirror" },
  { id: "h2", alarmId: "a3", date: "Tue · 21 May", time: "06:00 PM", label: "Stop work",    outcome: "complied", snoozes: 1, durMin: 12, ring: "math" },
  { id: "h3", alarmId: "a4", date: "Tue · 21 May", time: "09:00 AM", label: "Writing",      outcome: "complied", snoozes: 0, durMin: 18, ring: "nudge" },
  { id: "h4", alarmId: "a1", date: "Mon · 20 May", time: "10:00 PM", label: "Bed",          outcome: "complied", snoozes: 1, durMin: 62, ring: "preview" },
  { id: "h5", alarmId: "a2", date: "Mon · 20 May", time: "02:30 PM", label: "Walk",         outcome: "snoozed_then_complied", snoozes: 2, durMin: 24, ring: "math" },
  { id: "h6", alarmId: "a3", date: "Mon · 20 May", time: "06:00 PM", label: "Stop work",    outcome: "overridden", snoozes: 3, durMin: 38, ring: "preview", overrideReason: "On-call. Pager fire." },
  { id: "h7", alarmId: "a1", date: "Sun · 19 May", time: "10:00 PM", label: "Bed",          outcome: "overridden", snoozes: 2, durMin: 38, ring: "preview", overrideReason: "Friend in town." },
  { id: "h8", alarmId: "a4", date: "Sat · 18 May", time: "09:00 AM", label: "Writing",      outcome: "snoozed_then_complied", snoozes: 3, durMin: 22, ring: "math" },
  { id: "h9", alarmId: "a1", date: "Fri · 17 May", time: "10:00 PM", label: "Bed",          outcome: "complied", snoozes: 0, durMin: 31, ring: "nudge" },
  { id: "h10",alarmId: "a3", date: "Fri · 17 May", time: "06:00 PM", label: "Stop work",    outcome: "complied", snoozes: 0, durMin: 9,  ring: "nudge" },
  { id: "h11",alarmId: "a1", date: "Thu · 16 May", time: "10:00 PM", label: "Bed",          outcome: "ignored",  snoozes: 0, durMin: null, ring: null },
  { id: "h12",alarmId: "a2", date: "Thu · 16 May", time: "02:30 PM", label: "Walk",         outcome: "ignored",  snoozes: 0, durMin: null, ring: null },
  { id: "h13",alarmId: "a1", date: "Wed · 15 May", time: "10:00 PM", label: "Bed",          outcome: "complied", snoozes: 0, durMin: 19, ring: "nudge" },
];

// 28-day heatmap pattern (mostly compliant, scattered misses + 1 override).
// Each cell key matches outcome categories for color mapping.
const PATTERN_28 = [
  "c","c","c","s","c","i","c",
  "c","c","c","c","p","c","c",
  "s","c","c","c","m","i","c",
  "c","c","c","c","c","c","c",
];

Object.assign(window, {
  lPalette, lFonts, lGlyph, lStyleGlyph, lRingColor,
  RINGS_L, STYLES_L, DAYS_L,
  DEMO_ALARMS, CONV_SCRIPTS, HISTORY_L, PATTERN_28,
});
