# Two-hand L dragging and text selection

The first acquired hand owns the pointer for the camera session. A second hand is
an input modifier, never another pointer. Both thumb/index L poses hold the left
mouse button so moving the original hand drags items or selects text in the target
application. Breaking either pose releases the button. This is an experimental,
off-by-default setting; `Allow clicks` is also required. Ordinary one-hand click
and scroll behavior remains available when dragging is disabled.

## Detection and ownership

- Vision requests up to two observations from the same frame. Ownership selection
  happens on the main thread before the interaction engine, independently of result
  ordering. Only one unambiguous hand may acquire initially. The acquired side is
  retained across settings changes, loss of tracking, and practice transitions;
  an explicit camera restart clears it.
- With an owner, exactly one matching-side observation must exist. A missing owner,
  unknown side, or duplicate same-side candidates cannot substitute the modifier.
  This is handedness continuity, not person identity. Chirality misclassification
  and other people's hands remain real-world limitations.
- Each L requires extended thumb and index, a 60–120 degree angle between them,
  and confidently folded middle/ring/little fingers. Required landmarks use at least
  0.6 Vision confidence. Geometry is corrected for camera aspect ratio and mirrored
  poses. Missing/uncertain landmarks do not count as an L.
- When dragging is enabled, any visible second candidate suppresses ordinary pinch/forward clicks and
  scrolling. It only enables dragging when it is the opposite side and both L
  poses are valid. No position from the modifier feeds cursor movement.

## Interaction and release

Both L poses must persist for at least 250 ms and four frames before mouse-down.
The pointer freezes during confirmation, then anchors to the owner's current index
at the existing target. Subsequent owner movement emits left-mouse-dragged events.
There is one down per gesture, and the final up uses the last drag position.

Breaking either L releases immediately without an extra click or scroll. Losing
one hand, stale/out-of-order frames, invalid display/cursor, physical mouse takeover,
permission loss, preview mode, camera errors, pause/close/quit, system changes, or
settings/destination changes release the button. A lost hand returning in an already
held L pair cannot silently restart: open either hand for at least 120 ms and
three reliable frames, then form the pair again. Low-confidence or ambiguous
landmarks release but cannot rearm. A clearly folded thumb/index or extended
middle/ring/little finger proves release; a marginal L angle alone does not.

`Allow clicks` also gates dragging. Practice runs the same engine but exposes no
system drag output. The practice canvas retains a simulated selection trail.
Entering or leaving practice disables dragging so simulated practice cannot silently
enable system dragging. A cursor-side confirmation ring, active-drag caption, and
release reminder remain visible when another app has focus.

`DragOutput` reconciles desired drag state into down/drag/up events and makes release
idempotent. State commits only after event allocation and dispatch succeed; a failed
move leaves cleanup at the last posted location. The app pairs every explicit engine reset/interrupt with release and
reserves a mouse-up event before posting mouse-down, so cleanup needs no new event
allocation. OS delivery still depends on macOS permissions; forced process termination
cannot execute app cleanup.

## Verification

`bash scripts/test.sh` includes ownership ordering/ambiguity, L geometry across
scales/aspect ratios/mirroring/rotation, 15/30/60 fps production drag behavior in both
click modes, negative display origins, interruption paths, rearming, and practice
isolation. The existing click, scroll, recovery, installer, and signing checks remain.

The proposal has been compiled natively on macOS and exercised with synthetic
production-engine tests. CI also checks Apple Silicon and Intel builds. Neither CI nor geometry fixtures
establish physical gesture accuracy or actual text selection behavior in other apps.

Before merging, physically check on a Mac:

1. Enable two-hand dragging in Gesture settings and Allow clicks. Acquire with either hand. Add the second before/after making its L; confirm it
   never moves the cursor. Start with both visible and verify the one-hand prompt.
2. Aim in TextEdit, hold both L poses, move the owner to select in both directions,
   then release each hand's L separately. Try multiline text and reverse direction.
3. Drag a harmless Finder item and a window; confirm only the owner moves the drag.
4. While dragging, hide either hand, press Escape, pause via shortcut/menu, change
   click settings, enter practice, and close the window. No button should stay held.
5. Return with both L poses held after loss; no new drag until a visible release.
6. Test Pinch and Point forward, clicks off, practice, different cameras/lighting,
   two monitors, physical mouse takeover, and macOS permission changes.

## Platform references

- [Vision maximumHandCount](https://developer.apple.com/documentation/vision/vndetecthumanhandposerequest/maximumhandcount): observations are ordered by relative size, so array order cannot own the pointer.
- [Core Graphics mouse event types](https://developer.apple.com/documentation/coregraphics/cgeventtype): the output sequence is left mouse down, dragged events, then left mouse up.
