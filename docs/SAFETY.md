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
- **Pinch** is the default click *mode*; **Dwell** is opt-in via the Click mode control.
- Esc remains the panic kill-switch: pauses the camera and resets pinch/dwell/filter state.

## Later ideas (not shipped)

- Velocity / motion gate so a moving pinch cannot click mid-swipe.
- Separate right-click / drag / scroll modes behind the same allow-clicks latch.
