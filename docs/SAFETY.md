# Hand Mouse safety notes

## Why Accessibility matters

Click injection uses `CGEvent` posted to `.cghidEventTap`. macOS only delivers those
events when the process is Accessibility-trusted (`AXIsProcessTrusted`). Without that
permission the app can preview the camera and move nothing; with it, a confirmed gesture
can click whatever sits under the cursor.

## Blast radius of a false positive

An accidental click is a real left-click at the current pointer location. That can
dismiss dialogs, submit forms, toggle settings, or activate UI the user was only aiming
at. Pointer motion alone is lower blast radius than click injection.

## Safe defaults

- **Control mouse pointer** defaults **ON** — pointing helps aim and verify tracking.
- **Allow clicks** defaults **OFF** — no `leftMouseDown`/`leftMouseUp` until the user
  explicitly enables the checkbox (`UserDefaults` key `allowClicks`; older builds used
  `allowPinchClicks` and are migrated on launch).
- Injection is gated by `SafetyPolicy.shouldInjectClick` (gesture ∧ allowClicks ∧ AX ∧
  pointer control). White flash / `clickedUntil` only fire on a real inject.
- **Pinch** is the default click mode. **Point forward** is experimental and requires
  a fresh pointing-to-forward transition before a countdown. Hand scale is estimated
  automatically during ordinary pointing; no capture or practice gate is required.
  Existing Dwell selections migrate to Point forward with clicks off once.
- Optional practice returns before OS event dispatch; its results additionally expose no system
  location or click. Switching from practice to system output resets gesture intent.
- Esc remains the panic kill-switch: pauses the camera and resets gesture/filter state.
- Sleep, session deactivation, and display changes pause capture. Start camera or the
  configured global shortcut is required to resume; waking never resumes automatically.
  Held keys cannot repeatedly toggle capture or become a fresh request after waking.
- First activation and reacquisition require at least 250 ms of steady, open-hand
  evidence. The pointer is anchored to the current system cursor before movement resumes.
  Closed pinches, held scroll poses, a different left/right hand, missing cursor position,
  or a cursor outside the chosen display cannot acquire control.
- **Allow two-finger scrolling** defaults **OFF** and has its own saved opt-in. Scroll
  confirmation suppresses clicks, freezes the pointer, and requires a deliberate pose.
  Loss of the pose or tracking cancels scrolling with no queued motion or inertia.
- Practice sends no system movement, clicks, or scrolling. Leaving practice disables
  real clicks and scrolling; simulated success is not proof of physical reliability.
- Forward clicking requires a neutral-to-forward pose transition, then a hold. Staying
  still alone cannot start the countdown. Withdrawal, lateral palm motion, uncertain
  landmarks, invalid frames, and stale delivery cancel it. A sustained return to the
  movement pose is required before another click, including after tracking loss.
- Forward intent is inferred from 2D features, so pose changes and rotations can still
  produce false positives. Optional practice helps evaluate recognition but is not a reliability guarantee.
- A camera/format change, capture error, tracking loss, or settings change discards
  pending intent and the automatic reference. Normal pointing rebuilds it without setup.
- Camera errors and disconnects stop the session and require an explicit retry. No recovery path automatically restarts mouse control.

## Later ideas (not shipped)

- Velocity / motion gate so a moving pinch cannot click mid-swipe.
- Separate right-click and drag modes with explicit permission and release behavior.
- Tap-to-click (cut unless synthetic proofs hold).
