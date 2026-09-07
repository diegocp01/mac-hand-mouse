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

## Defaults and input gates

- **Control mouse pointer** defaults **ON** — pointing helps aim and verify tracking.
- **Allow clicks** defaults **ON** for new installs. Starting the camera can therefore
  enable real gesture clicks once Accessibility and pointer control are enabled.
  A saved OFF choice stays off (`allowClicks`, with `allowPinchClicks` migration).
  The camera still starts paused; optional practice sends no system input and exits
  with real clicks off. Uncheck Allow clicks for movement-only use.
- Injection is gated by `SafetyPolicy.shouldInjectClick` (gesture ∧ allowClicks ∧ AX ∧
  pointer control). White flash / `clickedUntil` only fire on a real inject.
- **Pinch** is the default click mode. **Point forward** is experimental and requires
  a fresh pointing-to-forward transition before a countdown. Hand scale is estimated
  automatically during ordinary pointing; no capture or practice gate is required.
  Existing Dwell selections migrate to Point forward with clicks off once.
- Optional practice returns before OS event dispatch; its results additionally expose no system
  location or click. Switching from practice to system output resets gesture intent.
- Esc remains the panic kill-switch: pauses the camera and resets gesture/filter state.
- Sleep, session deactivation, and display changes pause capture until Start camera is pressed again.
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
- Separate right-click / drag / scroll modes behind the same allow-clicks latch.
- Tap-to-click (cut unless synthetic proofs hold).
