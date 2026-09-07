# Forward clicking without pose setup (experimental)

> Historical design for the internal Forward detector. Point forward is no longer selectable in the app. For current startup and click instructions, see [Two-finger tap](TWO_FINGER_TAP.md).

## User flow

Select Point forward and start the camera. Allow clicks defaults on for new installs;
a saved off choice is preserved. Move your extended
index to aim; point it toward the camera as if touching the screen to start the
cursor timer. Pull back or move sideways to cancel. Return to ordinary pointing
before another click. Holding the movement pose alone never starts a timer.

There are no capture buttons, taught poses, or practice requirements. The app
estimates a hand reference automatically while the user aims, without requiring a
stationary cursor. Practice is optional and can be finished with zero target hits.
It sends no system pointer, click, or scroll input and leaves real clicks and scrolling off when finished.
The Allow clicks preference otherwise persists across launches, as it does for Pinch.
The old Dwell preference still migrates with clicks off once.

## Detection

Apple's [Vision hand observation](https://developer.apple.com/documentation/vision/vnhumanhandposeobservation)
provides image-space landmarks. This implementation uses 2D features rather than
measured finger depth. It does not assume that every hand or camera looks identical.

`AutomaticForwardReference` observes an extended index with usable joints. It averages
palm scale and index reach over at least 250 ms and four continuous observations.
Finger reach is relative to palm size; distances are corrected for camera aspect.
Reference adaptation can run while pointing moves. Initial cursor takeover and
recovery after tracking loss separately require 250 ms of steady neutral pointing,
then anchor to the existing cursor. See [cursor recovery](RECOVERY_AND_SCROLL.md). Reference samples tolerate 6% logarithmic
scale variation and 0.12 palm units of reach variation; unknown hands, invalid data,
and gaps over 120 ms reset observation. No frames, landmarks, or references are saved.

A reference requires reach of at least 1.05 palm units so a returned forward hold
does not become an aiming pose during pointer reacquisition. Click evidence is the reduction of index reach relative to that
reference, with 45% shortening representing a full forward gesture. Palm enlargement
contributes no positive click evidence; palm scale must remain between two-thirds
and 1.5 times the reference. Greater shortening saturates at 125% instead of rejecting
a stronger point. The previous fixed scale/reach projection could reject a direct
point without palm enlargement or a deeply foreshortened index. Extended pointing automatically readapts to changed distance
when the reference differs by at least 8% in log scale or 0.15 palm units in reach.
Adaptation requires at least 90% of the previous extended reach and is disabled
during gesture confirmation, countdown, and the completed-click state. Updating
the reference discards pending click intent.

The click detector retains its confirmation and cancellation rules:

- An observed movement pose for 180 ms and at least three samples rearms.
- Crossing 45% of the expected forward transition freezes the previous aim.
- Reaching 78% for at least 100 ms and three samples starts the timer. Confirmation
  must complete within 800 ms; the hold must retain at least 60% forward pose.
- Palm displacement over 18 display points, sustained lateral drift over 16
  points/second, withdrawal, or unusable tracking cancels independently of the cursor.
- Hold presets remain 0.65, 1, and 1.5 seconds. A completed hold clicks once, then
  requires withdrawal and the existing 450 ms cooldown before another gesture.
- Loss of tracking, camera/format changes, settings changes, and output-destination
  changes discard the reference. Ordinary pointing rebuilds it automatically.

Seven joints still require Vision confidence of at least 0.6. Folded, nearly occluded,
unknown-side, or malformed hands fail closed. Removing the wizard does not remove
these input checks, Accessibility permission, or the explicit Allow clicks control.

## Feedback when no click starts

The app distinguishes missing finger landmarks, an automatic reference that is not
yet available, a required return to aiming, and a large hand-distance change. None of
these states shows a countdown. The camera skeleton indicates hand tracking only;
it does not prove a forward gesture was recognized. No screenshot or personal
camera data is bundled in the repository.

## Validation and limits

The production-engine tests use no injected profile or pose-capture calls. They
exercise no-setup clicking with both hand sides, three hand scales, three index
lengths, and 15/30/60 fps. Tests also cover moving while the reference is learned,
ordinary pointing with noise, distance readaptation, starting with a forward pose,
tracking interruption, click cancellation, rearming, and practice isolation. Additional
regressions cover strong shortening with no palm enlargement, excess distance changes, specific blocked-gesture feedback, and click-preference
migration. Synthetic landmark chains also pass through ForwardPose.measure before
the production interaction engine.

These are synthetic observations, not measured physical success or false-positive
rates. Hand rotation can resemble foreshortening; pointing into the lens can hide
finger joints. The shared thresholds need physical testing across users, cameras,
and lighting. Keep the mode experimental and use Pinch if recognition is unreliable.

Before merging/releasing, check:

1. A fresh Point forward selection allows clicks without capture or practice.
2. Move normally at different speeds: no click ring while aiming or merely stopping.
3. Point toward the screen: one countdown at the cursor, one click, then withdrawal.
4. Pull back, move sideways, hide the hand, or pause mid-countdown: no delayed click.
5. Try both hands, different seating distances, and finger lengths without a wizard.
6. Open optional practice, then finish immediately: no target-count lock or system input.
7. Relaunch with the saved mode: no setup gate; the reference rebuilds during pointing.
