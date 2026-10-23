# Fist Bump — design

Date: 2026-10-21. Status: draft for Blaize's approval.

## Intent

Replace the "Doing It ↑" button with a fist bump. When the Coach authorizes
the user to end the alarm, a 👊 emoji grows toward the user and stops in the
middle of the screen. The user taps it ("bumps" it). The phone gives a haptic
hit, confetti blows up from the fist, the fist leaves the screen with an
animation, and the alarm chain ends exactly as the old button ended it.

Why: the "Doing It" tap is the physical confirmation that keeps a half-asleep
"yes" from killing the alarm on its own. The fist keeps that two-step rule
and makes the confirmation feel like a win instead of a form submit. It is
also the first of a family of gesture interactions (high five next).

## Goals

- The bump replaces the "Doing It ↑" button. It does the same thing
  (`resolveAction`, dismiss alarm, close the view).
- The bottom of the conversation has one button only: a wide Snooze.
- Every bump feels different. The removal animation and the confetti style
  are picked at random each time. Consecutive bumps never repeat the same
  removal animation.
- The haptic is a real "hit": a dull thud followed by a sharp click.
- A Settings screen lets Blaize tune the bump on his phone: haptic preset
  (with preview), removal animation (random or a specific one), confetti
  pattern and shapes (random or specific), fist size, and a "Try it" button
  that plays the whole bump without an alarm.

## Non-goals

- No high five or other gestures yet. Build the fist so a second emoji and
  a second animation set can plug in later, but do not build them.
- No bump sound effects. AlarmKit owns alarm sound. Text-to-speech of
  Coach messages works as it does today.
- No change to the Coach's judgment logic. Only the wording that mentions
  the button changes, plus the turn-limit fix in step 7 below.
- No feature toggle to bring the old button back. Rollback is a reinstall
  from `main`.
- No change to the data model. SwiftData schema stays as is.

## Anti-goals (what would make this a failure)

- The bump fires on a stray touch while the fist is still growing. The fist
  is tappable only after it has stopped.
- The bump is lost if the app is killed mid-animation. `resolveAction` must
  run at the tap, not after the animation.
- The user is stuck: the fist is up, the Coach authorized, but the user
  changed their mind and cannot snooze. Snooze stays live on the stage.
- Any third-party package. Haptics, confetti, and animations are plain
  Apple frameworks (SwiftUI, Core Haptics, UIKit feedback generators).
- Animation hitches on the real phone. Confetti runs in a `Canvas` driven by
  `TimelineView`, not hundreds of SwiftUI views.

## Constraints

- SwiftUI + MVVM + SwiftData, iOS 26, dark mode only, the amber palette in
  `Views/Ledger/LedgerDesign.swift` (`L.Palette.*`, `L.Mono.font`).
- No third-party packages (security posture).
- The app has no unit test target today. Builder: add one only if it costs
  under an hour. Otherwise verify by simulator screenshots and the device
  install, and say which you did.
- Work happens in the worktree at
  `~/Claude/projects/.worktrees/accountability-alarm-fist-bump` on branch
  `wt/fist-bump`, branched from local `main` at `a6ac390`.
- Done means installed on bPhone2 and felt by Blaize, not built in the
  simulator. See the project `CLAUDE.md` for the device install.

## The experience, step by step

1. The Coach calls `authorize_action`.
2. The conversation view switches from chat mode to the **bump stage**. The
   message list, the voice/text tabs, and the input row go away. Animate
   the swap with a short cross-fade (about 0.3 s).
3. The stage shows, top to bottom:
   - The Coach's **send-off**: the text the Coach wrote in the same response
     as the `authorize_action` call, in the existing message style. The
     prompt tells the Coach to write the send-off there (see "The Coach's
     side"). If the response had no text, the space stays empty. No extra
     API call is made. (My call: the tool result is queued today and only
     goes out with the next user message, which never comes on the stage.
     Using the same-response text avoids a new turn.)
   - The **fist**: 👊 rendered as `Text` with a large font. It starts at
     5 percent scale with a light blur and grows to full size over about
     0.9 s with an ease-out curve, like a fist approaching the camera. Full
     size is 65 percent of the screen width (setting, 50 to 75 percent).
     It stops in the vertical center of the stage. Once stopped it
     "breathes": a slow 1.00 to 1.03 scale loop so it looks alive.
   - The **hint**: after 2 s with no tap, "(bump the fist)" fades in under
     the fist, in `L.Mono.font` caps, dim color.
  - There are three glyphs: fist, left hand, and right hand. Each bump picks
    one at random unless one is pinned in Settings under HAND. The left hand
    is the mirrored ✋. For hands the hint reads "(high five)". Haptic,
    confetti, removal, and size apply to any glyph.
   - The **Snooze** button: one button, full width, same look as today's
     snooze button, same action (`resolveSnooze`, dismiss alarm, close).
4. The user taps the fist. The tap target is the fist's full frame. Taps
   during the grow animation do nothing.
5. On the tap, in this order:
   - `vm.resolveAction(context:)` runs at once. The data is saved before
     any animation plays.
   - The haptic preset plays.
   - The confetti bursts from the fist's center in a random style.
   - The fist leaves by a random removal animation (about 1.0 s).
   - The hint and send-off fade out with the fist.
   - 2.2 s after the tap, `appState.dismissAlarm()` and `dismiss()` run,
     same as the old button. Confetti is sized to be done by then: 2.0 s
     total, rain falls for 1.2 s. The close does not wait for anything.
     (My call: the close is a `fullScreenCover` slide, and it takes the
     confetti with it, so the confetti ends first.)
   - Text-to-speech: in voice mode the send-off is spoken like any other
     Coach message, as soon as it lands, while the fist grows. If speech is
     still playing at the close, it is cut. (My call.)
6. Reduce Motion on: the fist appears at full size with a fade, no breathing,
   no confetti, removal is a plain fade. The haptic still plays.
7. Turn limit: `sendMessage` runs the override check after the assistant
   turn when the session hits `maxConversationTurns * 2` messages. If that
   same turn called `authorize_action`, skip the override check. The user
   said yes and the Coach agreed, so the bump must resolve as compliance,
   not as overridden. (My call. This is a mechanical limit check, not the
   Coach's judgment. Today the same case leaves a "Doing It" button that
   does nothing.)

## The Coach's side

The Coach does not know about the fist. It knows that `authorize_action`
ends the conversation and that its reply after the call is a send-off.

Change these in `Services/ConversationEngine.swift` and
`ViewModels/ConversationViewModel.swift` (search for "DOING IT"):

- Tool description for `authorize_action`: it ends the conversation. The
  reply after the call is one or two sentences that send the user off,
  tied to what they committed to. Example: "Feet on the floor. Go get that
  run." Not "hit DOING IT".
- The send-off is written in the same response as the tool call. The Coach
  generates it fresh every time from the context it already has in its
  system prompt: the alarm label, the user's commitment fields, and what
  they said in this conversation. It is never a fixed string, and the app
  never hard-codes a fallback line. The tool description says: "Write your
  send-off as the text of this same response: one or two sentences, in
  your own words, that name what they are about to do and send them off
  to do it. Then stop." The prompt may show one example of the tone, marked
  as an example, never to be reused as is.
- Tool result string: "Authorized. The conversation has ended. Do not
  reply." (The result is queued and never sent, because the user cannot
  send another message from the stage. The string exists for the saved
  transcript only.)
- System prompt: the UI description changes from "a Snooze button and a
  DOING IT button (greyed out until you call authorize_action)" to "a
  Snooze button. When you call authorize_action, the conversation ends and
  the user confirms with a physical tap." Keep every rule about taking a
  yes at face value and not interrogating. Replace the canned reply
  "Okay — hit DOING IT." with the send-off instruction.
- Log line "authorize_action: DOING IT unlocked" becomes
  "authorize_action: bump stage unlocked".

Keep the two-step rule: authorization alone does not end the chain. The
tap on the fist does.

Decision (my call): once the stage is up, the user cannot talk to the Coach.
The Coach cannot walk the authorization back. Snooze is the user's way out.

## Haptics

`Services/HapticService.swift`. Uses `CHHapticEngine` when
`CHHapticEngine.capabilitiesForHardware().supportsHaptics` is true, else
falls back to UIKit feedback generators. Model on the engine handling in
`Services/AlarmSoundService.swift`. Prepare the engine when the stage
appears so the first hit has no delay.

Presets (enum `BumpHaptic`, raw string, stored in `@AppStorage`):

| Preset | Pattern |
|---|---|
| `buzz` | one continuous event, intensity 0.8, sharpness 0.3, 0.25 s |
| `click` | one transient event, intensity 1.0, sharpness 1.0 |
| `thudClick` (default) | transient intensity 1.0 sharpness 0.15 at 0 ms, then transient intensity 0.9 sharpness 1.0 at 60 ms |
| `success` | `UINotificationFeedbackGenerator` `.success` |

Fallback without Core Haptics: buzz and thudClick use `UIImpactFeedbackGenerator(.heavy)`, click uses `.rigid`.

## Confetti

`Views/Bump/ConfettiView.swift`. A `TimelineView(.animation)` driving a
`Canvas`. Particles are plain structs (position, velocity, rotation, spin,
shape, color, size, lifetime). Gravity, drag, and a slight horizontal
wobble. Each particle fades in its last 20 percent of life. Confetti runs
about 2.5 s then the view is removed.

The styles are modeled on confettipage.com's "Surprise me" button. That
site does not pick from a list of named styles. It randomizes these
dimensions, and so do we:

**Pattern** (enum `ConfettiPattern`):

| Pattern | What it does |
|---|---|
| `pop` | one burst from the fist center, 360 degree spread, 120 particles |
| `spray` | a fan upward from the fist center, 70 degree spread centered on straight up, strong initial velocity, 100 particles, over 0.4 s |
| `fireworks` | three bursts: the fist center at 0 ms, then two points about 25 percent of the screen width left and right of it, at 150 ms and 300 ms. 60 particles each |
| `rain` | particles fall from the top edge across the full width for 1.5 s, slow, with wobble. 150 particles. The fist still gets a small pop (30 particles) so the bump has a center |

**Shape group** (enum `ConfettiShapes`), after the site's ten groups. Draw
simple shapes with `Path`; use SF Symbols through `context.resolve(Image(systemName:))` where listed.

| Group | Shapes |
|---|---|
| `clean` | small squares (the site's default) |
| `classic` | circles, rectangles (paper strips, long and short), zig-zag strip, semicircle |
| `stars` | circles, `star.fill` |
| `sparkles` | circles, `sparkle`, 4-point sparkle path |
| `love` | `heart.fill`, circles, `suit.heart.fill` |
| `cake` | circles, `star.fill`, sprinkle (short rounded strip) |
| `bubbles` | hollow circles, two stroke widths |
| `garden` | circles, flower (5-petal path), `leaf.fill` |
| `cards` | `suit.club.fill`, `suit.diamond.fill`, `suit.heart.fill`, `suit.spade.fill` |
| `snow` | circles, `snowflake` |

**Palette**: one four-color set per bump. The pool is the site's 36
palettes (listed below) plus one house palette made from `L.Palette`
(fg, the escalation ambers, and bg3). The house palette is weighted so it
shows up about one in five bumps. On the dark background, skip any palette
color whose luminance is under 0.2 and use the other three.

**Density** and **size**: three steps each (0.6, 1.0, 1.4 multipliers on
particle count and particle size). Random each bump.

Random picks: pattern, shapes, palette, density, size. The settings
screen can pin pattern and shapes; palette, density, and size are always
random.

The 36 palettes from confettipage.com (`Y` array in its config chunk):

```
332f48 f2d9e6 ec4c4c 772c93 | fcfff4 3b395e 6f6ca6 59bec2 | f8fcfb 342926 8b7368 f7bf9b
64e4ec 283145 0078f5 efe5e1 | e1a750 001c2d 455c57 cad7ca | fbfdfc 370787 8661f4 f791f0
faf9fd 10396a f33452 faa742 | 67411c 792061 eb60a5 fbf8ed | ebeff4 221d18 7939e1 c0b5d2
fffcfb 712b3d da604b ebb431 | 433d5d ffcd40 f6f6f8 5e6974 | bed3af 150f00 5c4710 c9c734
094bcf feb959 feffff 6b8eed | fbfefd 00186a 003afb 7aa8f7 | 38251e f3b74d e47a54 a4422c
fbfafb 262f4c e82c5f f8c1ad | fcfefe 5a1a5a ec3c51 fc9f2b | fd0094 9cc835 f5e9c8 ee7705
fdfffc 273788 3b76fc ffaf09 | eaa215 1d181a 3175ad dfd0b8 | 0f2647 59dcfb 9e7cfd 9631f2
22b4a1 ff6262 faa534 f7fac5 | f83a63 0bd5be fbfafa 4f2e8c | 006d56 c7d800 f9f9fb 84ba32
e94459 22c8b2 f6d55e 50032b | 0c0f11 96b78b bd9a5b b62a2b | 275664 f8af08 e65f27 2b2626
ffe7db 162e5b 018577 8be3dc | e84b5e f9db05 fefffc ffbe24 | 3564bd f6c81f f9fefd 9fb0ff
f6fbfa 47220d cd3e71 ada7a6 | ec1e45 fce855 f6fbf6 fe7e99 | fffdff 5c3270 cf2541 cda0a1
fcfdfc 203472 276f9b 0ab5d8 | f8f8fb 2b2727 9f565b dea69a | f3f0db 2e2c4c e73e25 f7ae22
```

## Removal animations

`Views/Bump/FistRemoval.swift`. Enum `FistRemoval` with six cases. Each
runs about 1.0 s. The random pick excludes the previous bump's case, which
is stored in `@AppStorage("bumpLastRemoval")`.

| Case | What happens |
|---|---|
| `burst` | the fist scales up 15 percent in 80 ms, then vanishes as the confetti bursts. The fist "becomes" the confetti. Confetti count is doubled for this case |
| `dissolve` | the fist is rasterized with `ImageRenderer` and cut into a 12 by 12 grid of dots. Each dot drifts up and outward with random speed and fades over 0.6 to 1.0 s |
| `shatter` | the fist is rasterized and cut into a 5 by 5 grid of pieces. Each piece gets a random outward velocity and spin and falls under gravity, fading in the last 30 percent |
| `recoil` | the fist jumps back 12 percent scale and 20 pt down in 120 ms with a spring, then shrinks to zero scale over 0.5 s with an ease-in |
| `pullAway` | the fist shrinks to 5 percent scale, blurs, and fades over 0.9 s with an ease-in. The reverse of the entrance |
| `shockwave` | the fist flashes to white (a white-tinted overlay to 100 percent in 60 ms, back in 200 ms). A ring (1.5 pt stroke, `L.Palette.fg`) expands from the fist edge to 1.6 times the screen width over 0.7 s and fades. The fist fades inside it over 0.5 s |

Dissolve and shatter rasterize once, at tap time, at 2x scale.

## Fist stage structure

- `Views/Bump/BumpStageView.swift`: the stage. Inputs: send-off text
  (optional), fist width fraction, haptic preset, removal pick, confetti
  pick, `onBump`, `onSnooze`, snooze label. Owns the entrance, breathing,
  hint timer, tap, and the removal and confetti overlays. Demo mode
  (`isDemo: Bool`) hides the Snooze button and calls `onBump` with no
  resolve.
- `Views/Bump/FistView.swift`: the emoji with entrance and breathing.
- `Views/ConversationView.swift`: when `vm.actionAuthorized` is true,
  `messagesScroll` and `bottomPanel` are replaced by `BumpStageView`. The
  top bar and alarm header stay. `outcomeButtons` loses the "Doing It ↑"
  button; the Snooze button goes full width. In chat mode the Snooze button
  stays where it is today.
- The send-off is the last assistant message in `vm.messages` at the moment
  `actionAuthorized` turns true. The reply text is appended to `messages`
  before the tool is dispatched, so that message is the one that came with
  the call.

## Settings

A new gear button on the Alarms screen top bar (`LTopBar` right slot, next
to the clock, or a small gear icon at the right if the slot is taken by the
clock) opens `Views/SettingsView.swift` as a sheet. Sections:

- **Fist bump**
  - Haptic: segmented or list picker over the four presets, each row with a
    "Preview" button that plays it.
  - Removal: Random, Burst, Dissolve, Shatter, Recoil, Pull away, Shockwave.
  - Confetti pattern: Random, Pop, Spray, Fireworks, Rain.
  - Confetti shapes: Random and the ten groups.
  - Fist size: slider 50 to 75 percent, step 5, default 65.
  - "Try it": presents `BumpStageView` in demo mode as a full-screen cover.
    The bump plays with the current settings, then the cover closes.

Keys live in `Config/Constants.swift` next to
`downtimeNoticeAcknowledgedKey`. All stored with `@AppStorage`:
`bumpHaptic`, `bumpGlyph`, `bumpRemoval`, `bumpConfettiPattern`, `bumpConfettiShapes`,
`bumpFistWidth`, `bumpLastRemoval`.

Style: same Ledger look as the rest of the app. Mono caps labels, hairline
separators, amber on dark. No system `Form` chrome.

## Verification

- Compile for device with signing (`-allowProvisioningUpdates`).
- Simulator screenshots of: chat mode with the single wide Snooze; the
  stage with the fist stopped and the hint showing; the settings sheet.
- Device install on bPhone2. Blaize runs "Try it" and feels each haptic
  preset, then fires a real alarm and bumps it.
- Confirm in the pulled SwiftData store or the Debug log that a bump logs
  the same completion entries as the old "Doing It" tap.
- Confirm `resolveAction` runs before the animation: kill the app 0.3 s
  after a bump in the simulator and check the alarm resolved.

## Left to the builder

- Exact easing curves, spring values, and particle physics constants.
  Tune by eye on the simulator, then on the phone.
- How the emoji is rasterized for dissolve and shatter (ImageRenderer vs
  a `UIGraphicsImageRenderer` of a `UILabel`). Either is fine.
- Whether the gear goes in the `LTopBar` right slot or beside it.
- Whether to add a unit test target.
- File layout inside `Views/Bump/` beyond the names above.
