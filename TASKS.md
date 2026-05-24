# Tasks — Accountability Alarm

Durable backlog for things that need to happen outside of a normal coding session.

---

## [ ] Apply for Critical Alerts entitlement

**Why this matters**
Without this entitlement, the alarm is hard-capped by the user's ringer volume slider and is silenced by the Silent switch, Do Not Disturb, and Focus modes. Apple Clock bypasses all of these because it's a system app — third-party apps need explicit per-app permission from Apple via the Critical Alerts entitlement.

The code is already scaffolded — `AccountabilityAlarm.entitlements` declares `com.apple.developer.usernotifications.critical-alerts`, `NotificationService.alarmSound()` builds a critical-volume `UNNotificationSound`, and notifications use `interruptionLevel: .critical`. All of it no-ops gracefully until Apple grants the entitlement.

**Where to apply**
https://developer.apple.com/contact/request/notifications-critical-alerts-entitlement

**What to write in the justification**
Apple gates this aggressively. Their stated bar is *"critical to the user's well-being or safety."* General productivity / wake-up alarms historically get denied. The framing most likely to land:

> Accountability Alarm is an iOS app for users who configure alarms with a recorded
> personal commitment about something materially important to their wellbeing —
> consistent sleep, missed medication, getting children to school on time, leaving
> work to be present with family. When the alarm fires, the user must verbally
> convince an LLM (using their own previously-recorded reasoning) before the alarm
> stops. The mechanism only works if the alarm is loud enough to wake the user
> through Silent mode, DnD, and Focus — the user has explicitly opted into being
> woken regardless of system state when they set the alarm.
>
> Critical Alerts is essential to the core function; without it, the app degrades
> to a glorified reminder that the user can sleep through. Users will be informed
> in onboarding that this app uses Critical Alerts and given the standard system
> permission prompt.

**Realistic expectations**
- Approval can take days to weeks.
- Apple may request more detail or deny — expect possibly multiple rounds.
- Productivity / habit-tracking apps frequently get denied. Have a fallback story ready (next task).
- You do **not** need to launch on the App Store first; a paid developer account is sufficient.

**Once approved**
1. Xcode → target → Signing & Capabilities → "+ Capability" → **Critical Alerts**. This wires `AccountabilityAlarm.entitlements` to the build.
2. Rebuild and reinstall. No code changes.
3. Verify: set the phone to Silent, schedule an alarm 1 minute out, lock the phone. It should still ring at full volume.

---

## [ ] Investigate iOS 26 AlarmKit as a fallback / alternative

**Why this matters**
Apple shipped a real third-party alarm API in iOS 26 (AlarmKit). It lets apps schedule actual alarms — not notifications — that ring through Silent at alarm-tier volume, **without** needing the Critical Alerts entitlement. This is the modern correct path and would meaningfully change the loudness situation regardless of Apple's entitlement decision.

**What to do**
1. Read the AlarmKit docs (Apple Developer).
2. Spike a small migration from `UNUserNotificationCenter`-based scheduling to AlarmKit in `NotificationService`.
3. Confirm AlarmKit alarms can still launch into our conversation flow when tapped (custom intents / app launches).
4. Decide: AlarmKit-only, Critical-Alerts-only, or both (AlarmKit for ringing + Critical Alerts notifications as backup nudges).

---

## [ ] Remaster `alarm-sound.caf` for max perceived loudness

**Why this matters**
The current `alarm-sound.caf` is likely mastered conservatively. Aggressive normalization + limiting can yield 6-12 dB of perceived loudness gain with no code or entitlement changes.

**What to do**
1. Open `AccountabilityAlarm/AccountabilityAlarm/Resources/alarm-sound.caf` in Audacity or Logic.
2. Normalize to -1 dBFS.
3. Apply a hard limiter with ceiling at -0.3 dBFS.
4. Optionally: add a slight high-frequency boost (~3 kHz) — human ears are most sensitive there, makes it feel louder without clipping.
5. Re-export as CAF and replace.
