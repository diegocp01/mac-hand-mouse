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

- **Move pointer** defaults **ON** — pointing helps aim and verify tracking.
- **Click** defaults **ON** for new installs. Starting the camera can therefore
  enable real gesture clicks once Accessibility and pointer control are enabled.
  A saved OFF choice stays off (`allowClicks`, with `allowPinchClicks` migration).
  The camera still starts paused; optional practice sends no system input and exits
  with real clicks off. Turn off Click to disable tap clicks.
- Injection is gated by `SafetyPolicy.shouldInjectClick` (gesture ∧ allowClicks ∧ AX ∧
  pointer control). White flash / `clickedUntil` only fire on a real inject.
- **Two-finger tap** is the app's click gesture, including for existing users.
  Raise index + middle, bend both together, then lift to click. Pinch and Point forward
  detectors remain internal for regression coverage; they are not current user options.
- Optional practice returns before OS event dispatch; its results additionally expose no system
  location or click. Switching from practice to system output resets gesture intent.
- Esc remains the panic kill-switch: pauses the camera and resets gesture/filter state.
- Sleep, session deactivation, and display changes pause capture. Start camera or the
  configured global shortcut is required to resume; waking never resumes automatically.
  Held keys cannot repeatedly toggle capture or become a fresh request after waking.
- First activation and reacquisition require index + middle raised, palm toward the
  camera, held steady for at least 250 ms and four observations. The pointer is anchored
  to the current system cursor before movement resumes. Bent fingers, an active scroll
  pinch, a different left/right hand, missing cursor position, or a cursor outside the
  chosen display cannot acquire control.
- **Scroll** defaults **ON** for new installs; a saved OFF choice stays off.
  Pinch thumb + index, hold steady for 250 ms, then move the hand vertically. Scroll
  confirmation suppresses clicks and freezes the pointer. Release or tracking loss
  cancels scrolling with no queued motion or inertia. Raised index + middle alone
  never starts scrolling.
- Practice sends no system movement, clicks, or scrolling. Leaving practice disables
  real clicks and scrolling; simulated success is not proof of physical reliability.
- A tap clicks only after both fingers bend and lift; staying still or holding the
  bend never clicks. Incomplete bends, timeouts, uncertain landmarks, invalid frames,
  and stale delivery cancel intent. Raise both fingers briefly before another tap,
  including after tracking loss. See [tap behavior and validation](TWO_FINGER_TAP.md).
- Tap intent is inferred from 2D features, so pose changes and rotations can still
  produce false positives. Optional practice helps evaluate recognition but is not a reliability guarantee.
- A camera/format change, capture error, tracking loss, or settings change discards
  pending intent. Raise index + middle, palm toward the camera, to reacquire after tracking loss.
- Camera errors and disconnects stop the session and require an explicit retry. No recovery path automatically restarts mouse control.

## Legacy detector behavior

The internal forward-click detector requires a neutral-to-forward pose transition,
then a hold. Staying still alone cannot start its countdown. Withdrawal, lateral
palm motion, uncertain landmarks, invalid frames, and stale delivery cancel it.
A sustained return to the movement pose is required before another click, including
after tracking loss. Its hand reference is estimated automatically during ordinary
pointing and discarded after tracking or source interruptions. These rules remain
covered by regression tests; Point forward is not selectable in the app.

## Later ideas (not shipped)

- Right-click support with an explicit gesture and release behavior.
