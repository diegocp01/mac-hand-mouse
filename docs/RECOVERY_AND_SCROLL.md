# v1.5 interaction recovery and navigation

PR #4 replaced automatic Dwell clicking with an intentional forward gesture;
PR #7 removed manual pose setup. This change preserves both and completes the next
parts of the roadmap: cursor reacquisition, scrolling, keyboard resume, and practice
for either click mode.
It does not restore automatic Dwell or claim a measured real-world failure rate.

## Cursor takeover policy

`InteractionEngine` receives the current Quartz cursor position each frame. Before
first movement, or after lost/invalid/stale tracking, it requires an open, stable
hand for 250 ms and at least four frames. Pinch mode uses separated thumb/index;
forward mode uses ordinary extended pointing relative to its automatic reference.
When that reference is missing, learning it first takes at least 250 ms of usable
pointing observations; no capture buttons or mandatory practice are added. A held scroll pose cannot
acquire. Movement over 0.025 normalized camera units or 3 cursor points restarts
the waiting interval. Timestamp gaps over 120 ms discard pending activation.

When activation completes, `PointerFilter.reanchor` aligns the current hand target
with the actual cursor. That first accepted frame keeps the cursor exactly where
it is and cannot click or scroll. Subsequent hand motion uses the existing soft
mapping and adaptive smoothing with a relative offset. Display-edge clamping
rebases the offset so reversing direction has no extra dead zone. Lowering and
repositioning the hand provides a clutch when more travel is needed.

The first accepted left/right hand owns that camera session. A different side
cannot take over until an explicit camera restart; an unknown side cannot acquire.
This is handedness continuity, not biometric identity: another person's same-side
hand could satisfy the same activation conditions. Manual cursor displacement
over 12 points interrupts control; the next activation anchors at the new position.
A cursor outside the selected display causes no warp and requires repositioning.

## Scrolling

Scrolling has a separate, off-by-default opt-in. Vision must confidently show index
and middle extended, with ring and little folded. Shape checks use aspect-corrected
joint geometry and confidence ≥ 0.6; uncertain shapes are not treated as intent.
Keep the two-finger pose steady for 250 ms before moving vertically. Confirmation
and active scrolling both suppress click detection and freeze the pointer.

The engine emits pixel scroll deltas proportional to observed vertical movement
(1000 units for a full normalized frame height), capped at 600 units/second.
Fractional remainders preserve slow movement at different frame rates. Displacements
over 0.06 normalized units in one frame cancel. No inertia is generated. Losing
the pose returns to pointer acquisition, clearing click state and preserving the
cursor. Held two-finger poses after interruptions cannot silently resume.

The app posts [Quartz pixel scroll events](https://developer.apple.com/documentation/coregraphics/cgscrolleventunit)
at the fixed cursor location. Applications can interpret these differently. The
caption at the cursor says Scrolling; it is not a click countdown and remains
visible with clicks disabled. Test direction and speed in the target application.

## Global keyboard activation

`ResumeShortcut` uses `RegisterEventHotKey` with exclusive registration. Its
default is Control-Option-Command-H; the preferences offer M or Off. A conflict
is reported in the UI instead of silently sharing the shortcut. Registration
subscribes to that combination's press/release events, not a keyboard stream.
The key latch prevents repeat toggles while held. Separate awake, display-awake,
and active-session gates prevent a wake notification from authorizing resume.
The camera never wakes itself; a fresh explicit action is required. Escape and
the existing close-to-pause behavior remain available.

## Practice and validation

Practice safely works for Pinch and Point forward without manual calibration or
required target hits. The latter learns its reference just as it does outside practice.
The simulated cursor now follows the same acquisition/scroll pipeline as system
control, including actual display dimensions. A scroll counter makes direction
visible. `systemLocation`, `systemClick`, and `systemScrollY` are unavailable on
practice outputs; the UI also returns before OS dispatch. Finishing or canceling
practice switches real clicks and scrolling off.

Run `bash scripts/test.sh` for core, production-forward, and recovery/scroll suites.
The new suite covers 15/30/60 fps, negative display origins, the audit's five-frame
hand-loss reproduction, closed-pinch return, side changes, physical mouse takeover,
callback gaps, scrolling direction/rate/cancellation, permission/settings gates,
simulated input isolation, and overlapping system/key lifecycle events.

Physical checks still required before claiming dependable tracking:

1. Start, activate with an open hand, lower it, and return at several other positions.
   The first return must leave the cursor where it was; try returning already pinched.
2. Move the physical mouse during a hand break. Resume and verify the new position
   is preserved. Check each display and hand separately.
3. In practice, try Pinch targets and both scroll directions. Stop, lose tracking,
   switch modes, and exit; other apps must receive no practice input.
4. Enable real scrolling over an ordinary document. Confirm its direction, stop
   behavior, fixed target, visible caption, and absence of clicks.
5. From another app, use the shortcut to start/pause. Hold it to check repeats,
   choose the alternate key and Off, then test sleep/wake/session switching.
6. Retest forward click cancellation and deliberate rearming, plus Pinch, Escape,
   permission loss, and camera restart. Synthetic landmarks do not replace these checks.
