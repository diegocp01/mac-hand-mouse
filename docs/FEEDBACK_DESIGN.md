# Camera and click feedback

The camera preview answers “Can it see my hand?” The click card answers “What will happen next?” The cursor ring puts the countdown at the target so people can watch what they are clicking instead of looking back at the app.

- Keep camera status and Pause visible, including while scrolling through settings.
- Show a determinate ring, numeric time remaining, and progress bar only after a deliberate forward gesture is confirmed. The same detector drives all three; visual feedback never fires a click.
- Normal movement and a stationary movement pose show no ring. Withdrawal or sideways motion clears canceled progress. Confirm posted click events with a checkmark, then require withdrawal before rearming.
- Pair color with text and shape. Use a dark outline so the cursor ring remains legible over bright content. Update progress directly without decorative animation.
- With clicks off, allow unrestricted pointing: no countdown, no gesture-induced pointer freeze.
- Teach two poses, then require successful simulated target clicks. Keep setup controls and cancellation visible above the scroll area. Practice pauses all system input.
- Keep permissions in an expandable section, opening it when access is lost or camera setup needs attention. Make the window resizable and scrollable for laptop displays.

These decisions were informed by Apple's [Dwell guide](https://support.apple.com/guide/mac-help/use-dwell-mchl437b47b0/mac), [feedback guidance](https://developer.apple.com/design/human-interface-guidelines/feedback), and [accessibility guidance](https://developer.apple.com/design/human-interface-guidelines/accessibility/). Apple's circular dwell indicator provides a familiar reference; the implementation and timing here remain specific to Hand Mouse.

Version 1.4 replaces automatic dwell activation with an experimental calibrated forward gesture. See [intent detection and testing limits](FORWARD_CLICK.md).

The live-camera feel, VoiceOver experience, and overlay behavior in full-screen apps still need hands-on validation. Automated tests cover observed countdown timing, cancellation, rearming, and cursor-caption geometry across display arrangements.
