# Two-finger tap

The app now selects two-finger tap on launch, including for existing pinch/forward users. Legacy detectors remain internal for regression coverage; they are not selectable click modes. Allow clicks is preserved. Scrolling uses a distinct thumb + index pinch when Pinch to scroll is enabled. Extended index + middle alone never starts scrolling. One-hand pinch dragging is unavailable; optional two-hand L dragging still interrupts tap intent.

Start with index and middle extended, palm visible. Aim with the index, bend both fingers, then extend them again. The camera classifies each finger using aspect-corrected tip/PIP/MCP geometry with confidence >= 0.6. Both extended is raised; both folded is bent; intermediate visible shapes are transitions. Missing confident joints cancel intent.

Bring index + middle together to stop the pointer immediately before bending. The lock starts on the first confident observation at a fingertip gap of at most 30% of palm width, stays through holds and tap timeouts, and releases at 42% to avoid jitter. Separation reanchors movement at the held cursor so hand travel during the lock cannot cause a jump. Missing proximity measurements retain an existing lock; tracking interruption clears it. This stop gesture requires Allow clicks and does not itself click.

A raise must last 0.15 seconds before arming. A tap must contain at least two bent observations, last at least 0.05 seconds, and finish within 0.65 seconds. The pointer freezes from the first transition and reanchors on release/cancel to avoid a fingertip jump. It clicks on the return to raised, never while held bent. Another sustained raise is required before the next tap. Tracking interruption, permissions, pause, destination/settings changes and two-hand dragging clear tap state.

Validation: detector and production-engine regression tests cover normal cycles, stationary hands, single-finger transitions, long holds, missing observations, stale frames, disabled clicks, practice isolation, cursor anchoring and scrolling arbitration. These tests are synthetic, not proof of physical recognition accuracy. Before calling the gesture reliable, test left/right hands, lighting, slow aiming, curled fingers, occlusions and target accuracy with the camera. Bend enough for the camera to see both fingertips fold toward their knuckles; a small downward translation of a straight hand is not a tap.

## Pinch scrolling and precision

A confident thumb/index pinch plus a visible palm enters scroll confirmation immediately and cancels tap intent. Hold the palm steady for 0.25 seconds (at least four observations), then move it vertically while pinched. The existing bounded scroll detector emits no inertia. Release or missing pinch/palm measurements stops scroll output and reanchors the index at the held cursor. Two-hand L dragging retains priority. Practice output stays isolated from system events; scrolling can be enabled separately from clicks.

Precision mode reduces mapped hand displacement to 35% around the current hand anchor. Changing the setting resets acquisition at the current cursor. It is intended for nearby small targets; lower and raise the hand to reposition. Target freeze and scroll speed remain unchanged.

The cursor caption shows `🔒 Pointer locked` while the finger-separation lock holds outside an active tap, scroll, or drag. Practice shows the same lock in its status panel. Physical recognition and comfort still need camera testing.
