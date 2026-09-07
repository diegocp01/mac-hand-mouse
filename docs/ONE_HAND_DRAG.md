# One-hand pinch dragging

> Historical design retained for regression coverage. One-hand pinch dragging is unavailable with the current two-finger tap gesture. For current controls, see the [user guide](../README.md#use).

This optional Pinch-mode feature lets one hand aim, click, drag, and select text. Existing pinch clicking and forward clicking keep their behavior when it is off. The startup screen gains no additional text: the opt-in lives under Gesture settings.

## Interaction

- Open thumb + index to acquire and arm. Aim with the index finger.
- A confirmed pinch posts one native left-button down at the frozen aim location.
- Holding without movement remains a press; releasing posts one up, completing a normal click. No extra atomic click is posted.
- After 100 ms of closure settling, palm displacement of at least 8 equivalent screen points sustained for two samples and 25 ms starts dragging. Reanchor to the palm at the held cursor position, then use the existing pointer filter for movement. This prevents index curl from moving the selection.
- Opening the pinch posts up at the last successfully posted location. Reanchor to the index so opening the finger does not jump the pointer.
- Enable either pinch or two-hand L dragging, never both through the UI. The engine gives pinch dragging priority if both flags are supplied. Pinch dragging is cleared when switching to Point forward.
- During a pinch press/drag, a two-finger scroll pose cannot take control. After release, scrolling can start normally. Returning from scrolling requires open acquisition.

## Cleanup and uncertainty

The shared `DragOutput` owns the matching release obligation. A stationary press emits neither repeated downs nor mouse-moved/dragged events. Losing landmarks, frame timing, original handedness, permission, target display, or pointer ownership interrupts the gesture. Pause, settings changes, camera-source changes, and practice transitions use the existing release path. A held pinch cannot restart after loss until visible open acquisition and rearming.

The palm averages wrist, index MCP, middle MCP, and little MCP, all at confidence 0.6 or higher. Pinch dragging additionally requires thumb/index tips at confidence 0.6; ordinary pointing/clicking thresholds remain unchanged. Missing, nonfinite, or out-of-frame palm measurements, or frame-to-frame palm jumps over 0.08 normalized units, disarm the gesture. These conservative thresholds need camera validation.

Releasing a native mouse button is cleanup, not undo: the target app can complete a click or drop already in progress. Once a down has been posted, interruption cannot guarantee cancellation of that app's action.

Practice uses the same detector/filter, but its results expose no system input. A short pinch counts a target hit on release; a sustained moving pinch draws the existing selection trail. Entering and finishing practice clear both drag settings, clicks, and scrolling.

## Validation

`bash scripts/test.sh` covers ordinary pinch compatibility, default-off behavior, left/right hands at 15/30/60 fps, offset displays, closure freeze, jitter, one down/up pair, deliberate palm movement, release reanchoring, tracking/permission/timing/display/settings interruptions, closed return after loss, scroll arbitration, practice isolation, and event-post failures. Existing two-hand lifecycle checks also run.

A universal arm64/x86_64 app build checks camera and AppKit integration. Synthetic tests do not establish physical tracking reliability. Before promoting this experimental interaction, test real text selection and dragging across users/cameras and record macOS, architecture, camera, and lighting, including partial occlusion, rapid movement, pause while pressed, and release over different apps. No real-camera test is claimed for this PR.

Current validation on main including PR #12: 4,970 automated checks passed (415 new one-hand checks plus 4,555 existing checks), including off-center palm initiation and corner-to-corner dragging with the new anchored pointer map. The universal ad-hoc build passed. A separately identified review app, with camera off, verified the checkbox starts off, the drag choices exclude one another, switching to Point forward hides and clears pinch dragging, and returning to Pinch leaves it off. The expanded settings layout was visually inspected. No installed app was replaced.
