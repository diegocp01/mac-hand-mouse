# Hand Mouse safety notes

## Why Accessibility matters

Click injection uses `CGEvent` posted to `.cghidEventTap`. macOS only delivers those
events when the process is Accessibility-trusted (`AXIsProcessTrusted`). Without that
permission the app can preview the camera and move nothing; with it, a confirmed gesture
can click whatever sits under the cursor.

## Blast radius of a false positive

An accidental gesture can send a real left-click or right-click at the current pointer
location. Left-clicks can dismiss dialogs, submit forms, toggle settings, or activate
UI the user was only aiming at. Right-clicks can open context menus. Pointer motion
alone has less impact than click injection.

## Defaults and input gates

- **Move pointer** defaults **ON** — pointing helps aim and verify tracking.
- **Click** defaults **ON** for new installs. Starting the camera can therefore
  enable real gesture clicks once Accessibility and pointer control are enabled.
  A saved OFF choice stays off (`allowClicks`, with `allowPinchClicks` migration).
  The camera still starts paused; optional practice sends no system input and exits
  with real clicks off for that session without changing the saved preference.
  Turn off Click to disable both left-click and right-click gestures.
- Injection is gated by `SafetyPolicy.shouldInjectClick` (gesture ∧ allowClicks ∧ AX ∧
  pointer control). White flash / `clickedUntil` only fire on a real inject.
- **Point and hold** is the app's click gesture, including for existing users.
  Aim with the index alone, then raise the middle finger too. The pointer holds its
  target while a ring fills for one second, then sends one left-click. Lower the
  middle finger before another click. Two-finger tap, Pinch, and Point forward
  detectors remain internal for regression coverage; they are not current user options.
- **Right click** requires all five fingertips pinched together with confident
  observations of every fingertip. A short confirmation sends one right-click;
  opening the hand is required before another attempt, including after a canceled
  confirmation. A five-finger pinch suppresses left-clicking and ordinary scrolling.
- Optional practice returns before OS event dispatch; its results additionally expose no system
  location or click. Switching from practice to system output resets gesture intent.
- Esc remains the panic kill-switch: pauses the camera and resets gesture/filter state.
- Sleep, session deactivation, and display changes pause capture. Start camera or the
  configured global shortcut is required to resume; waking never resumes automatically.
  Held keys cannot repeatedly toggle capture or become a fresh request after waking.
- First activation and reacquisition accept a visible hand immediately and anchor at
  the current cursor without injecting a click on that frame. No special pose is
  required for movement. A different left/right hand, missing cursor position, or a
  cursor outside the chosen display cannot acquire control. Clicking still needs
  an observed open-hand or index-only aiming interval before a two-finger hold.
- **Scroll** defaults **ON** for new installs; a saved OFF choice stays off.
  Bring thumb + index + middle fingertips together, hold steady for 250 ms, then
  move the hand vertically. All three fingertips must remain visible and close.
  A thumb/index-only pinch cannot start scrolling. Scroll
  confirmation suppresses clicks and freezes the pointer. Release or tracking loss
  cancels scrolling with no queued motion or inertia. Raised index + middle alone
  never starts scrolling.
- Practice sends no system movement, left-clicks, right-clicks, or scrolling. Leaving practice disables
  real clicks and scrolling; simulated success is not proof of physical reliability.
- A left-click requires the complete one-second hold. Lowering the middle finger,
  excessive hand movement, uncertain landmarks, invalid frames, and stale delivery
  cancel it. Holding both fingers up after a click never repeats it. Return to the
  index-only pose before another click, including after tracking loss.
  See [point-and-hold behavior and validation](POINT_AND_HOLD.md).
- Click intent is inferred from 2D features, so pose changes and rotations can still
  produce false positives. Optional practice helps evaluate recognition but is not a reliability guarantee.
- A camera/format change, capture error, tracking loss, or settings change discards
  pending intent. Show the same hand again to reacquire after tracking loss.
- Camera errors and disconnects stop the session and require an explicit retry. No recovery path automatically restarts mouse control.

## Legacy detector behavior

The internal forward-click detector requires a neutral-to-forward pose transition,
then a hold. Staying still alone cannot start its countdown. Withdrawal, lateral
palm motion, uncertain landmarks, invalid frames, and stale delivery cancel it.
A sustained return to the movement pose is required before another click, including
after tracking loss. Its hand reference is estimated automatically during ordinary
pointing and discarded after tracking or source interruptions. These rules remain
covered by regression tests; Point forward is not selectable in the app.
