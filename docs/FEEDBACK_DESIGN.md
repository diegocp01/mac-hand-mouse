# Camera and dwell feedback

The camera preview answers “Can it see my hand?” The click card answers “What will happen next?” The cursor ring puts the countdown at the target so people can watch what they are clicking instead of looking back at the app.

- Keep camera status and Pause visible, including while scrolling through settings.
- Show a determinate ring, numeric time remaining, and progress bar for dwell. The same detector drives all three; visual feedback never fires a click.
- Clear canceled progress and show when movement starts a fresh countdown. Confirm a sent click with a checkmark, then require movement before rearming.
- Pair color with text and shape. Use a dark outline so the cursor ring remains legible over bright content. Update progress directly without decorative animation.
- With clicks off, allow unrestricted pointing: no dwell countdown, no gesture-induced pointer freeze.
- Keep permissions in an expandable section, opening it when access is lost or camera setup needs attention. Make the window resizable and scrollable for laptop displays.

These decisions were informed by Apple's [Dwell guide](https://support.apple.com/guide/mac-help/use-dwell-mchl437b47b0/mac), [feedback guidance](https://developer.apple.com/design/human-interface-guidelines/feedback), and [accessibility guidance](https://developer.apple.com/design/human-interface-guidelines/accessibility/). Apple's circular dwell indicator provides a familiar reference; the implementation and timing here remain specific to Hand Mouse.

The live-camera feel, VoiceOver experience, and overlay behavior in full-screen apps still need hands-on validation. Automated tests cover observed countdown timing, cancellation, rearming, and cursor-caption geometry across display arrangements.
