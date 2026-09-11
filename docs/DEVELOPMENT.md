# Development and packaging

Requires macOS 13+ and Xcode Command Line Tools with Swift 5.7+ (or full Xcode).

For a fresh checkout:

```sh
git clone https://github.com/diegocp01/mac-hand-mouse.git
cd mac-hand-mouse
bash scripts/test.sh
bash Tests/install.sh
bash Tests/signing.sh
bash scripts/build.sh
open "build/Hand Mouse.app"
```

If you already have a checkout, quit the development copy, then run the test, build, and open commands from its root. `bash "Launch Hand Mouse.command"` builds the current source before opening it; if that exact build is already running, it opens that copy and asks you to quit before rebuilding. To install in `~/Applications` instead, use `bash "Install Hand Mouse.command"`; see the README's [developer setup](../README.md#developer-setup) and [first-launch steps](../README.md#first-launch).

Builds explicitly target the minimum macOS version in `Info.plist`. The default build targets the current Mac's architecture. To build a universal app, run `HAND_MOUSE_ARCHS="arm64 x86_64" bash scripts/build.sh`. Build and install commands refuse to replace an executable that is running from their destination. They stage a fresh app before replacing it, so removed resources cannot linger. Source builds reuse a per-user signing identity, and updates must satisfy the installed app's previous signing requirement. See [signing and permission persistence](SIGNING.md).

To leave an existing development app untouched, use `HAND_MOUSE_BUILD_DIR=/tmp/hand-mouse-review bash scripts/build.sh`. Remove temporary review bundles afterward so macOS does not confuse copies with the same bundle identifier.

## Code map

| File | Responsibility |
| --- | --- |
| `Sources/Gesture.swift` | Legacy two-finger tap and pinch/hold detectors, tuning, smoothing, preference migration |
| `Sources/IntentClick.swift` | One-second point-and-hold clicks, five-finger pinch clicks, and fingertip geometry |
| `Sources/PracticeDiagnostics.swift` | Shared landmark-to-finger evidence, bounded opt-in recording, and camera-free replay |
| `Sources/PracticeDiagnosticsUI.swift` | Read-only camera diagnostics, intent labels, and explicit recording/export controls |
| `Sources/TapGuidance.swift` | Historical two-finger tap instructions retained for regression coverage |
| `Sources/ForwardClick.swift` | Legacy 2D pose features, automatic hand reference, intentional forward-click state machine |
| `Sources/InteractionEngine.swift` | Production pipeline, cursor acquisition, freshness/permission gates, gesture/filter ordering |
| `Sources/InputMotion.swift` | Cursor acquisition, scroll geometry/deltas, and activation lifecycle policy |
| `Sources/ResumeShortcut.swift` | Exclusive global pause/resume shortcut registration |
| `Sources/Camera.swift` | Camera capture and Vision landmarks |
| `Sources/FrameMailbox.swift` | Bounded delivery of the newest result |
| `Sources/main.swift` | Window, camera lifecycle, feedback orchestration, permissions, mouse events |
| `Sources/FeedbackUI.swift` | Determinate click ring, status card, simulated practice canvas, nonactivating cursor overlay |
| `Sources/StartupUI.swift` | Startup palette, five-card gesture guide, setup state, and static camera-off artwork |
| `Sources/FeedbackGeometry.swift` | Screen-edge caption placement with a ring centered on the click target |
| `Tests/main.swift` | Deterministic gesture and pointer checks |
| `Tests/RecoveryScrollTests.swift` | Hand return, physical mouse takeover, scrolling, practice isolation, and activation gates |
| `Tests/InteractionEngineTests.swift` | Production pipeline at 15/30/60 fps, intent/cancel/rearm, automatic reference and practice isolation |
| `Tests/IntentClickTests.swift` | Point-and-hold and right-click timing, cancellation, rearming, and production output gates |
| `Tests/IntentClickUISnapshot.swift` | Camera-free countdown and right-click feedback review states |
| `Tests/GestureGuideSnapshot.swift` | Camera-free default and narrow gesture-guide review states |
| `Tests/GestureDemoTimelineTests.swift` | Deterministic tutorial phase and reduced-motion sequence checks |
| `Tests/PracticeViewSnapshot.swift` | Camera-free task, completion, and narrow practice review states |
| `Tests/UIRenderSupport.swift` | AppKit layout assertions and PNG raster support for UI review |
| `Tests/install.sh` | Isolated installer replacement, failure rollback, and running-app guards |
| `scripts/sign.sh` | Persistent local signing identity, explicit certificate mode, and disposable ad-hoc mode |
| `scripts/verify-update-identity.sh` | Reject updates that would discard an existing certificate-backed identity |
| `Tests/signing.sh` | Changed binaries retain identity; different signers and ad-hoc downgrades are rejected |

The app selects **Point and hold** for every launch. Start or reacquire with the index alone extended, palm toward the camera, and hold briefly. Move the index fingertip to aim, then raise the middle finger for a one-second left-click countdown at the held target. The ring fills during the hold; lower the middle finger to prepare another click. Pinch all five fingertips for one right-click, then open the hand before another attempt. **Scroll** uses a three-fingertip pinch (thumb + index + middle) and has a separate saved setting. See [current gesture behavior and validation](POINT_AND_HOLD.md). Two-finger tap, Pinch, and Point forward clicking remain internal regression paths with no selectable app modes.

Pointer smoothing remains velocity-adaptive from 8–50 ms. Legacy pinch detector defaults: Balanced threshold 0.42 hand-scale units, confirmation after at least two samples and 25 ms, reopening above 0.60 for 70 ms, and a 300 ms click cooldown. Precise uses 0.34 and Easy uses 0.50, with release 0.18 above each threshold. Confirmation tolerates 0.06 units of threshold jitter. The hand scale is the greater of palm width and 0.75 times wrist-to-middle-base distance, corrected for frame aspect ratio.

`InteractionEngine` evaluates the gesture before applying index motion, preserving the pre-gesture aim during the two-finger hold or five-finger pinch. Excessive hand movement cancels a left-click hold even while the pointer is frozen. A canceled right-click confirmation requires the hand to open before rearming. Its legacy tap/pinch/forward paths also preserve their pre-gesture aim. Legacy forward mode requires a forward transition relative to an automatically estimated hand reference before invoking the hold timer; neither normal motion nor stillness starts it. Palm motion is measured independently of the frozen pointer. Changing settings cancels active progress. The legacy hold presets are 0.65, 1, or 1.5 seconds, retained with the existing `dwellDurationPreset` preference; they do not change the active one-second left-click hold. The standalone Pinch detector tolerates missing pinch observations for at most 120 ms, but the production engine cancels all input immediately on a missing index or interrupts on a callback gap over 120 ms. Returning hands must reacquire the current cursor before gesture detection resumes. A legacy pinch attempted during cooldown is consumed rather than delayed. Camera results are coalesced to the latest frame and callbacks from old sessions are rejected. Camera and inference latency are additional to smoothing time. See the [legacy forward gesture design](FORWARD_CLICK.md) for automatic adaptation, thresholds, and limitations.

Tests cover confirmation, gentle pinches, duplicate prevention, reopening, cooldown, tracking loss, malformed observations, pointer settling, overshoot, freezing, and display-coordinate mapping. The integration suite runs the same `InteractionEngine` used by the app, including freshness and permission gates. It does not use a physical camera or send mouse clicks. CI runs these tests plus installer regressions, app builds, and signature checks on Apple Silicon and Intel.

## Install verification

```sh
INSTALL_CHECK=$(mktemp -d)
HAND_MOUSE_INSTALL_DIR="$INSTALL_CHECK" HAND_MOUSE_NO_OPEN=1 bash "Install Hand Mouse.command"
# After inspection, remove the temporary app so macOS does not confuse copies.
rm -rf "$INSTALL_CHECK"
```

The installer builds in a temporary directory, stages a fresh bundle beside the destination, verifies it, then replaces the old app with rollback if the replacement fails verification. It checks the destination executable before building and again before replacement. Temporary files are removed after success; if rollback itself fails, it reports the location of the recoverable previous app. Overrides above permit an isolated test without starting the camera or changing a user's installed app. To uninstall, quit Hand Mouse and move `~/Applications/Hand Mouse.app` to the Trash.

## Release package

```sh
bash scripts/package.sh
```

Produces `dist/Hand-Mouse-<version>-macos-universal.zip` and a SHA-256 file, containing both `arm64` and `x86_64` slices plus documentation and license. Packaging uses a temporary build directory that it removes afterward, verifies the signature and architectures, and does not publish anything. Generated apps, caches, archives, and local environment files are ignored by Git.

Packages and CI artifacts default to **ad-hoc signing**, while normal builds/installs default to **persistent local signing**. Gatekeeper may block downloaded binaries. Building from reviewed source is the supported installation path; a broadly distributed binary release should use Developer ID signing and notarization. See [release signing options](SIGNING.md#developer-and-release-modes). No private signing material belongs in the repository.

Current live testing is on Apple Silicon. Intel and older supported macOS versions need physical hardware testing even after cross-compilation and automated tests succeed.

## Repair a stale local permission

If permission is on but the app still reports it missing, quit Hand Mouse. Reset only this app's Accessibility record:

```sh
tccutil reset Accessibility com.local.handmouse
```

Reopen the app, expand **Permissions**, click **Show in Finder**, then add that exact copy to Privacy & Security → Accessibility (called Device Control and Data Access on macOS 27). Enable it and restart Hand Mouse. This does not grant permission by itself or change other apps' permissions.

Before v1.3.1, ad-hoc signatures changed with rebuilt code. Migrating that old approval to the persistent signer requires one final repair. Subsequent source builds retain the signer stored outside the checkout. Multiple development copies with the same bundle identifier can still make System Settings show a different copy; keep one active installation. Never replace the certificate requirement with a wildcard or identifier-only rule. The app and installer do not modify the TCC database or reset approvals automatically.


## Camera and click feedback

The active left-click feedback reads the point-and-hold detector's progress and displays its ring throughout the one-second countdown. The pointer remains at the selected target. Completed, canceled, and rearming states replace the countdown with the next action. Right-click feedback distinguishes confirmation from reopening. `TapGuidance` retains the historical **Aim → Bend → Lift** instructions for legacy tests. Rendering never advances a detector or triggers a click.

In the legacy forward path, `ForwardClickDetector.progress` and `remainingSeconds` are read-only values derived from observed frame timestamps. Reset, cancel, tracking loss, and post-click phases clear progress. A fresh movement-pose observation and forward transition are required to rearm, including after interruption. All modes hide stale feedback if delivery stops, using a 100 ms watchdog in common run-loop modes and the 120 ms tracking grace measured from the last received frame. Frames at least 200 ms old, future-dated frames, and duplicate/out-of-order timestamps cannot move or click.

Practice uses the actual target display bounds in the same engine, then scales its simulated pointer into the canvas. `InteractionDestination.practice` permits simulation without Accessibility but exposes no `systemLocation`, `systemClick`, `systemRightClick`, or `systemScrollY`; the OS dispatch path consumes only those system output fields. The practice handler also returns before reaching dispatch. Changing output destination resets gesture intent. The legacy forward reference and camera identity/frame dimensions stay in process memory. Tracking loss, a source change, or capture failure discards that reference; it rebuilds automatically during pointing. Reference adaptation is frozen during a legacy forward gesture and never starts a timer by itself.

The cursor panel ignores mouse events, never becomes key or main, and uses no screen recording. Quartz pointer coordinates convert to AppKit using the primary screen's top edge. The label stays inside the target screen, while the ring remains at the actual click location. The panel supports other applications' Spaces/full-screen contexts and hides when its target display is unavailable. Duplicate overlay content is excluded from accessibility; the app exposes a labeled progress indicator, percentage, and state announcements without announcing every countdown frame. No decorative progress animation runs ahead of detector state.

Sleep, display sleep, user-session deactivation, and display configuration changes pause capture; resuming requires the explicit Start action or global shortcut. Runtime capture errors, interruptions, selected-camera disconnects, and five consecutive Vision failures invalidate the session and offer an explicit retry. Pausing also releases the configured inputs/outputs, so the next Start discovers connected cameras again; callbacks from removed outputs are rejected. A normal no-hand frame is not treated as a processing failure. The built-in front camera remains preferred.

## Recovery, scrolling, and keyboard activation

See [current point-and-hold and pinch-scroll behavior](POINT_AND_HOLD.md) for the index-only starting pose and thumb + index + middle scrolling. The [v1.5 interaction recovery notes](RECOVERY_AND_SCROLL.md) retain the original activation policy, relative cursor anchoring, keyboard registration, and legacy regression coverage; their old click modes and scrolling pose are historical.

Validation before release: with a live camera, confirm Start/Pause and no-hand recovery with the index alone extended, palm toward the camera. Check aiming, the ring filling during the one-second two-finger hold, cancellation by lowering the middle finger or moving too far, and no repeats until the middle finger is lowered. Check five-finger right-clicking, cancellation when a fingertip is hidden, and reopening after both successful and canceled attempts. Turn Click off during a pending hold. Try optional practice, thumb + index + middle pinch scrolling, Escape, Accessibility loss, and cursor feedback alignment on additional displays/full-screen apps. Use the practice canvas and app's Test click target. Synthetic tests do not verify physical tracking or delivery to other apps.

## Gesture interface review

The main window opens at 900×800 points and supports a 720×650-point minimum. Its
five-card guide separates the card selected for learning from the gesture that is
currently live. Move, Click, and Right click remain visible; Scroll and Select text show
their off state until the corresponding control is enabled. The camera remains off
until Start is activated. These visuals never authorize movement, change gesture
thresholds, advance a detector, or claim that tracking is live.

Startup and recovery instructions consistently name the index alone extended, palm
toward the camera, and a brief steady hold before aiming.

The camera-free guide renderer exercises the production `GestureGuideView` at a
900×370 default size and a 620×350 narrow size. It asserts resolved Auto Layout and
checks for fully clipped controls before writing review images:

```sh
mkdir -p build/ui-review
xcrun swiftc -swift-version 5 Sources/StartupUI.swift Tests/UIRenderSupport.swift Tests/GestureGuideSnapshot.swift -o /tmp/hand-mouse-gesture-render
/tmp/hand-mouse-gesture-render "$PWD/build/ui-review"
xcrun swiftc -swift-version 5 Sources/FeedbackGeometry.swift Sources/FeedbackUI.swift Sources/StartupUI.swift Tests/UIRenderSupport.swift Tests/IntentClickUISnapshot.swift -o /tmp/hand-mouse-intent-render
/tmp/hand-mouse-intent-render "$PWD/build/ui-review"
```

The practice renderer covers click, scroll, and selection at the default width,
narrow 620-point task layouts, completed click and scroll states, and a released
sentence-selection success state:

```sh
xcrun swiftc -swift-version 5 Sources/PracticeTasks.swift Sources/FeedbackGeometry.swift Sources/StartupUI.swift Sources/FeedbackUI.swift Tests/UIRenderSupport.swift Tests/PracticeViewSnapshot.swift -framework AppKit -framework AVFoundation -o /tmp/hand-mouse-practice-render
/tmp/hand-mouse-practice-render "$PWD/build/ui-review"
```

Before release, also review the complete native window at both supported window
sizes and use keyboard navigation and VoiceOver with camera off. Then exercise
Start/Pause, Practice, Permissions, settings disclosure, live gesture badges, and
each physical gesture. Static renders validate layout, task state, and gesture wording; they do
not validate camera recognition, native-window focus, or event delivery.

The earlier four-card review on September 7, 2026, before Point and hold, rendered both guide sizes without ambiguous layout or
fully clipped controls. `bash scripts/test.sh` passed 187 core, 465 interaction,
3,377 recovery/scroll, 526 two-hand drag, 415 one-hand drag, 16 source-update, and
1,002 two-finger tap checks, plus the update shell regressions. An isolated arm64
application build completed with ad hoc signing and passed strict code-signature
verification. The Mac login was
locked, so a layer-backed full-window offscreen raster was blank and was excluded
from visual evidence; native full-window and interaction review remains required on
an unlocked session.

PR #23 integration preserves the animated tutorial and task practice introduced in #22. Both practice and live control use point-and-hold. The tutorial demonstrates a one-second hold, index-only aiming, three-fingertip scrolling, and all-five-fingertip right-clicking. Compile UI renderers with `Sources/PracticeTasks.swift` when using `Sources/FeedbackUI.swift`.


## Native launch layout

The window uses a native behind-window frosted backdrop, translucent content panels, and clear glass for the persistent Start/Pause and Practice controls. Full-size content extends the backdrop under the titlebar while safe-area constraints keep the header clear of window controls. macOS 27 adds native interactive glass when built with a supporting SDK; macOS 26 keeps clear glass, and older systems use visual-effect materials. Text and controls retain full view opacity. Reduce Transparency or Increase Contrast makes the backdrop and panels opaque; Reduce Motion disables interactive glass and cosmetic transitions. Hover/selection highlights and section reveals ease between states without moving controls on hover or animating detector progress. The five animated tutorials and three task-based practice exercises are preserved. The default content size is 920×720; the minimum window is 720×650.

Render the complete camera-free layout with:

```sh
xcrun swiftc -swift-version 5 Sources/StartupUI.swift Sources/PracticeTasks.swift Sources/FeedbackGeometry.swift Sources/FeedbackUI.swift Sources/LaunchUI.swift Tests/UIRenderSupport.swift Tests/LaunchUISnapshot.swift -o /tmp/hand-mouse-launch-render
/tmp/hand-mouse-launch-render "$PWD/build/ui-review"
```

The renderer, also run by `bash scripts/test.sh`, checks 24 light/dark, size, and disclosure states, resizing, five keyboard-accessible selectors, and visibility of Start/Pause while scrolling. It additionally checks opaque accessibility fallbacks, Reduce Motion policy, backdrop input passthrough, full control opacity, and native glass/interactivity availability. Static renders do not establish the live desktop blur or interactive animation appearance; review those in a visible window. Physical hand tracking and native event delivery require separate live-camera tests.

## Practice diagnostics verification

`Sources/FeatureFlags.swift` defines `FeatureFlags.diagnostics = false`. This default omits the diagnostics preview/panel and gates recording, export, observation, and replay entry points without changing normal gesture recognition. Flip the constant to `true` locally and rebuild to test diagnostics; restore `false` before committing or publishing a build. `bash scripts/test.sh` checks the disabled screen/replay gates by default, or runs the 20 diagnostics UI states when the local flag is enabled.

`bash scripts/test.sh` also builds and runs `Tests/PracticeDiagnosticsTests.swift`. It checks the shared camera classifier's original confidence/geometry boundaries, cancellation reasons, opt-in/bounded recording, metadata allowlisting, and JSON round-trip replay through the production practice engine at 15/30/60 fps. To analyze a recording explicitly exported from Click Practice, use `build/practice-diagnostics-tests --replay "/path/to/hand-mouse-diagnostics.json"`. Replay uses selected-hand landmarks and observed pinch ratios after Vision; it does not test Vision inference or hand selection from camera images. Attempt labels are user annotations, not inferred ground truth.

With the local diagnostics flag enabled, render the production diagnostics panel inside the launch layout without requesting camera or Accessibility access:

```sh
xcrun swiftc -swift-version 5 -module-cache-path "$PWD/build/module-cache" Sources/FeatureFlags.swift Sources/Gesture.swift Sources/IntentClick.swift Sources/ForwardClick.swift Sources/InputMotion.swift Sources/TwoHandDrag.swift Sources/OneHandDrag.swift Sources/InteractionEngine.swift Sources/PracticeDiagnostics.swift Sources/PracticeDiagnosticsUI.swift Sources/StartupUI.swift Sources/PracticeTasks.swift Sources/FeedbackGeometry.swift Sources/FeedbackUI.swift Sources/LaunchUI.swift Tests/UIRenderSupport.swift Tests/PracticeDiagnosticsUISnapshot.swift -o build/diagnostics-ui-render
build/diagnostics-ui-render "$PWD/build/diagnostics-ui"
```

This checks collapsed, holding, canceled, recording, and paused/exportable states at both supported widths and in light/dark appearances. Manual camera validation should additionally confirm mirrored skeleton alignment, readable finger scores, one-second holds, early cancellation, no repeated clicks, no OS input in Practice, explicit recording start/stop, and export after Escape. Keep live recordings outside version control. Neither these renders nor synthetic replay proves physical recognition quality; this feature deliberately leaves the detector thresholds unchanged.
