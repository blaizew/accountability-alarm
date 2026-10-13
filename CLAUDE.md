# AccountabilityAlarm — project context

Personal iOS alarm app. When an alarm fires, dismissing/snoozing triggers a
short AI conversation (a "Coach") that holds the user to the commitment they
made when setting the alarm. SwiftUI + MVVM + SwiftData, Claude Haiku for the
conversation, AlarmKit for the alarm surface. Single author (Blaize), actively
dogfooded on his own phone.

## THE PRIMARY TARGET IS A PHYSICAL PHONE — read this first

This app is **installed on and used daily from Blaize's physical iPhone
(bPhone2)**. It has been continuously updated on that device for weeks — that
is the real deployment surface, not the simulator.

**A change is NOT "shipped" until it is installed on the phone.** Building for
the simulator, or committing to git, does neither. When Blaize asks "is this on
my phone yet," the answer is no unless a device install ran *this session*.
Simulator builds and screenshots are for quick visual checks only.

### Deploy to the phone (the actual workflow)

The phone is paired for **wireless** development — no cable needed. Discover it
live (don't hardcode the UDID; it can change):

```
xcrun devicectl list devices          # find bPhone2, grab its identifier
```

Then build for the device and install:

```
cd AccountabilityAlarm
xcodebuild -project AccountabilityAlarm.xcodeproj -scheme AccountabilityAlarm \
  -destination 'platform=iOS,id=<UDID>' -allowProvisioningUpdates \
  -derivedDataPath <scratch>/dd build
xcrun devicectl device install app --device <UDID> \
  <scratch>/dd/Build/Products/Debug-iphoneos/AccountabilityAlarm.app
```

Notes:
- `-allowProvisioningUpdates` is required — device builds are code-signed
  (unlike the simulator's "Sign to Run Locally"). A signing/provisioning prompt
  may appear that only Blaize can approve; surface it, don't try to route around.
- `devicectl device process launch` can auto-launch, but **fails if the phone is
  locked** — install still succeeds, so installing then letting Blaize open it
  is fine.
- Signing uses a free personal-team profile that **expires 7 days after the
  build** — then the app stops launching and needs a rebuild + reinstall. After
  a reinstall, launch can fail with "profile has not been explicitly trusted by
  the user" (FBSOpenApplicationErrorDomain error 3). Fix: Blaize goes to
  Settings → General → VPN & Device Management → Apple Development entry →
  Trust. Only he can do this on the phone. (Seen 2026-10-12.)
- Replacing the app in place preserves its SwiftData store (his real alarms +
  history). Don't uninstall/reinstall — that wipes his data.

### Build variants
- **Device (real testing):** `-destination 'platform=iOS,id=<UDID>'`. AlarmKit
  alert UI, Stop/OpenConversation intents, and lock-screen tint only truly
  exercise on-device.
- **Simulator (quick visual/screenshots):** `-destination 'platform=iOS
  Simulator,id=<UDID>'`. Works on this Mac (iPhone 17 Pro, iOS 26.5). Can't tap
  the sim from this session (AppleScript is denied System Events; simctl has no
  input verb) — so first-run dialogs and tab switches can't be driven headlessly.
- **Compile-only:** `-destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO`.

## Debugging on-device
Full procedure (pull the SwiftData store to read the app's own event log, os_log
collection, crash/hang reports) lives in agent memory: `device-debugging.md` in
this project's memory dir. Key move: pull `Library/Application Support/default.store`
via `devicectl device copy from` and query `ZALARMLOGENTRY` with sqlite3.

## Design / conventions
- Palette is centralized in `AccountabilityAlarm/Views/Ledger/LedgerDesign.swift`
  (`L.Palette.*`). As of 2026-07-16 it's the cbt-i-coach **amber night** scheme
  (warm hue ~45, dark-only). Escalation ramp stays warm; intensity via chroma.
- The AI persona is a **Coach** (renamed from "past-self" 2026-07-19). In prompts,
  "their past self" / "past-you" still refers to *the user's* earlier self and is
  intentionally preserved — the Coach advocates for it.
- Product brief: `design/EXPLAINER.md`. Frozen designer handoff:
  `design/extracted/` — don't edit.
- Dark mode only; `.preferredColorScheme(.dark)` is pinned deliberately.

## Repo
- Git identity: `blaizew` / `blaizew@users.noreply.github.com`.
- Remote `origin` (github.com/blaizew/accountability-alarm) was fully in sync with
  local `main` as of 2026-09-28. Push only when Blaize asks — check
  `git rev-list --left-right --count origin/main...main` for the current gap.
- Bundle id: `com.blaizew.AccountabilityAlarm`.
