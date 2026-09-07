# Hand Mouse safety notes

## Why Accessibility matters

Click injection uses `CGEvent` posted to `.cghidEventTap`. macOS only delivers those
events when the process is Accessibility-trusted (`AXIsProcessTrusted`). Without that
permission the app can preview the camera and move nothing; with it, a pinch can click
whatever sits under the cursor.

## Blast radius of a false positive

An accidental pinch is a real left-click at the current pointer location. That can
dismiss dialogs, submit forms, toggle settings, or activate UI the user was only aiming
at. Pointer motion alone is lower blast radius than click injection.

## Safe defaults (this patch)

- **Control mouse pointer** defaults **ON** — pointing helps aim and verify tracking.
- **Allow pinch clicks** defaults **OFF** — no `leftMouseDown`/`leftMouseUp` until the
  user explicitly enables the checkbox (`UserDefaults` key `allowPinchClicks`).
- Injection is gated by `SafetyPolicy.shouldInjectClick` (gesture + allowClicks + AX +
  pointer control). White flash / `clickedUntil` only fire on a real inject.
- Esc remains the panic kill-switch: pauses the camera and resets detector/filter state.

## Wave-2 ideas (notes only — not in this patch)

- Dwell or tap confirmation under an Elon-style click-mode picker.
- Velocity / motion gate so a moving pinch cannot click mid-swipe.
- Separate right-click / drag modes behind the same allow-clicks latch.
