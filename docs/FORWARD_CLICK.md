# Intentional forward clicking (experimental)

## Interaction contract

Moving the index fingertip aims the pointer. Holding the normal movement pose does
not start a click timer. A fresh, calibrated forward pose transition freezes the
previous aim, confirms the gesture, and starts the visible hold timer. Pulling back,
moving sideways, or losing usable tracking cancels. One forward hold produces at
most one click; returning to the movement pose rearms it.

This replaces automatic Dwell clicking. Pinch remains the default. Existing Dwell
preferences select Point forward with real clicks off and setup required. Forward
calibration is discarded at app exit, after a capture error, or when the selected
camera/format changes. Recalibrate if your seating distance, camera angle, or hand changes.
Normal camera pause/resume retains a completed profile for the same camera/format.
In v1.5, initial activation and hand return also require a steady movement pose;
the cursor resumes from its current position. See [recovery and scrolling](RECOVERY_AND_SCROLL.md).

## What the camera can establish

Apple's [Vision hand-pose observation](https://developer.apple.com/documentation/vision/vnhumanhandposeobservation)
provides image-space joints and confidence. This app uses those **2D** observations;
it does not measure finger depth or prove that a person intends to click.

`ForwardPose` measures aspect-corrected palm size and index reach relative to the
palm. Pointing toward the lens can shorten the projected index, and moving forward
can enlarge the palm. Calibration projects those features onto a movement-to-press
axis. Hand rotation, body movement, and lighting can confound this proxy. Occluded,
folded, uncertain, or unknown-side hands fail closed. A reliable-looking practice
run is necessary before real clicks, but does not establish a false-positive rate.

Setup captures two steady poses, then runs two targets with a simulated pointer.
The engine uses desktop dimensions and thresholds, scaling only the drawing into
the practice canvas. Practice requires no Accessibility approval and cannot emit
system pointer or click output. Finishing practice leaves Allow clicks off.
Frames, landmarks, camera identifiers, and calibration are never saved or uploaded.

## Detection details

These are initial tunings to evaluate with physical users, not universal constants:

- Seven required joints need Vision confidence ≥ 0.6. The index must have a coherent
  projected path; a folded or almost fully occluded finger is rejected.
- Each capture needs 0.65 seconds and at least eight continuous, stable samples.
  Missing observations, a different hand, motion, or a gap over 120 ms reset it.
- Calibration requires at least 12% palm enlargement or a 0.35 palm-unit reduction
  in index reach. The logarithmic scale and normalized reach form a two-feature axis.
- At least 180 ms in the movement pose rearms. Crossing 45% of the taught transition
  freezes the target; reaching 78% for at least 100 ms and three samples starts timing.
  Intermediate confirmation must complete within 800 ms.
- The hold requires at least 60% forward pose. A perspective-compensated palm shift
  over 18 display points, or sustained drift above 16 points/second over at least
  160 ms, cancels independently of the frozen fingertip cursor.
- Hold presets are 0.65, 1, and 1.5 seconds. The timer advances only on observed
  frames. A completed click needs withdrawal plus the 450 ms cooldown before rearming.
- Calibration or mode/settings changes, permission loss, camera pause, invalid
  frames, missing hands, and interrupted delivery discard pending intent.

The legacy `DwellDetector` is retained as an internal timer primitive; it is only
called after forward confirmation. Its autonomous dwell behavior is not exposed
as a selectable mode. Pinch detection and its tuning are unchanged.

## Validation

`bash scripts/test.sh` exercises the production engine at 15, 30, and 60 fps:
ordinary movement and stillness without progress, slow approach, explicit press,
target freeze, withdrawal, lateral cancellation, single-frame outliers, post-click
rearm, tracking loss, permission changes, camera aspect correction, and calibration.
Practice tests verify simulated clicks have no system output and cannot carry
intent into desktop mode. These are synthetic landmarks, not physical tracking tests.

Before promoting the experimental mode, use the practice canvas and Test click
button to record these results on actual cameras and hands:

| Exercise | Acceptance check |
| --- | --- |
| Aim slowly, quickly, then stop for several seconds | No countdown during ordinary movement/pose |
| Aim, point forward, and hold | Ring starts after the gesture and clicks the chosen target once |
| Pull back or move sideways during the timer | Ring clears with no click; normal aiming resumes |
| Keep the forward pose after clicking | No repeated click |
| Withdraw, aim, and press again | A fresh timer can click the same or another target |
| Hide a joint or briefly remove the hand | No queued/resumed click when the hand returns |
| Shift posture or rotate the hand without clicking | Check for false intent; recalibrate or use Pinch if unreliable |
| Cancel setup, switch modes, pause, relaunch | Clicks remain off until deliberately enabled; unfinished setup is discarded |
| Retry after camera failure or change camera | New calibration required |
| Use another app, a full-screen Space, or a second display | Ring stays at the actual target and passes input through |

Physical gesture success, false-positive rate, and camera/lighting coverage remain
unverified for this change. Keep it opt-in and use Pinch if practice is inconsistent.
