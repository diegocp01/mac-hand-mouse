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
| `Sources/InteractionEngine.swift` | `HandInput`, settings, freshness/permission gates, pointer acquisition, and one step per gesture in priority order |
| `Sources/ClickGestures.swift` | Hold-still left click, five-finger right-click pinch, and fingertip cluster geometry |
| `Sources/InputMotion.swift` | Pointer acquisition, finger and palm geometry, scroll deltas, and activation lifecycle policy |
| `Sources/PointerFilter.swift` | Pointer smoothing, soft travel margins, steady aim, and the click-injection safety latch |
| `Sources/TwoHandDrag.swift` | Hand ownership, L-pose geometry, two-hand drag detector, and mouse-button bookkeeping |
| `Sources/Camera.swift` | Camera capture, Vision landmarks, and the per-frame `HandFrame` the engine consumes |
| `Sources/FrameMailbox.swift` | Bounded delivery of the newest result |
| `Sources/main.swift` | Window, settings, camera lifecycle, permissions, mouse events, and the opt-in camera test |
| `Sources/GestureFeedback.swift` | Status-card and cursor-overlay text for each live gesture state |
| `Sources/PreviewView.swift` | Camera preview with the hand skeleton and travel guide |
| `Sources/UpdateFlow.swift` | Menu-driven update check and hand-off to the relaunch helper |
| `Sources/FeedbackUI.swift` | Determinate click ring, status card, simulated practice canvas, nonactivating cursor overlay |
| `Sources/StartupUI.swift` | Startup palette, glass surfaces, and static camera-off artwork |
| `Sources/GestureGuide.swift` | Five-card gesture guide and its deterministic demo timeline |
| `Sources/GestureDemoCanvas.swift` | Hand-drawn tutorial artwork |
| `Sources/LaunchUI.swift` | Launch window layout |
| `Sources/PracticeDiagnostics.swift` | Finger evidence, bounded opt-in recording, readable results, and camera-free replay |
| `Sources/PracticeDiagnosticsUI.swift` | Read-only camera test screen with explicit recording/export controls |
| `Sources/FeedbackGeometry.swift` | Screen-edge caption placement with a ring centered on the click target |
| `Tests/main.swift` | Pointer filter, geometry, frame delivery, safety latch, and feedback layout checks |
| `Tests/InteractionEngineTests.swift` | Every blocking reason cancels a hold; settings changes, takeover, displays, and practice isolation |
| `Tests/StillClickTests.swift` | Hold-still timing, tremor tolerance, cancel-on-move, and rearm distance at 15/30/60 fps |
| `Tests/ClickGestureTests.swift` | Right-click and scroll gestures, their priority over clicking, fingertip geometry, and output gates |
| `Tests/RecoveryScrollTests.swift` | Hand return, physical mouse takeover, scrolling, practice isolation, and activation gates |
| `Tests/SteadyAimTests.swift` | Fine-motion assistance, edge reach, and hold-still clicks at fine-aimed targets |
| `Tests/TwoHandDragTests.swift` | Hand ownership, L geometry, drag lifecycle, and release on every interruption |
| `Tests/PracticeDiagnosticsTests.swift` | Readable results, cancellation reasons, bounded recording, metadata allowlist, and replay |
| `Tests/IntentClickUISnapshot.swift` | Camera-free countdown and right-click feedback review states |
| `Tests/GestureGuideSnapshot.swift` | Camera-free default and narrow gesture-guide review states |
| `Tests/GestureDemoTimelineTests.swift` | Deterministic tutorial phase and reduced-motion sequence checks |
| `Tests/PracticeViewSnapshot.swift` | Camera-free task, completion, and narrow practice review states |
| `Tests/UIRenderSupport.swift` | AppKit layout assertions and PNG raster support for UI review |
| `Tests/install.sh` | Isolated installer replacement, failure rollback, and running-app guards |
| `scripts/sign.sh` | Persistent local signing identity, explicit certificate mode, and disposable ad-hoc mode |
| `scripts/verify-update-identity.sh` | Reject updates that would discard an existing certificate-backed identity |
| `Tests/signing.sh` | Changed binaries retain identity; different signers and ad-hoc downgrades are rejected |

There is one click gesture. Show your hand to move; the pointer anchors at its current position and follows your index fingertip. **Click** by holding the pointer still: after a quarter second of rest a ring appears, and it clicks once when the ring fills 0.75 s later. Moving more than 14 points during the hold cancels it, and the pointer must travel 36 points after a click before another can start, so resting in place never repeats. Pinch all five fingertips for one right-click, then open the hand before another attempt. **Scroll** uses a three-fingertip pinch (thumb + index + middle) with a separate saved setting. See [current gesture behavior and validation](POINT_AND_HOLD.md).

Pointer smoothing is velocity-adaptive from 8–50 ms. The scroll pinch closes below 0.42 hand-scale units and releases above 0.60. The hand scale is the greater of palm width and 0.75 times wrist-to-middle-base distance, corrected for frame aspect ratio.

`InteractionEngine.process` runs the gates (running, permission, pointer enabled, frame freshness, display, cursor, hand ownership, physical takeover), acquires the pointer at the existing cursor, then tries one gesture step at a time: two-hand drag, five-finger right click, three-finger scroll, and finally aiming with the hold-still click. A competing gesture cancels a hold in progress with an explicit reason. The pointer is frozen during right clicks and scrolling, and is reanchored when they end so finger motion never becomes pointer travel. Camera results are coalesced to the latest frame and callbacks from old sessions are rejected. Camera and inference latency are additional to smoothing time.

Tests cover hold-still timing at 15/30/60 fps, tremor inside the still radius, cancel-on-move, rearm distance, right-click confirmation and reopening, scroll confirmation and release, duplicate prevention, tracking loss, malformed observations, pointer settling, overshoot, freezing, and display-coordinate mapping. The integration suites run the same `InteractionEngine` used by the app, including freshness and permission gates. They do not use a physical camera or send mouse clicks. CI runs these tests plus installer and signing checks.

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

See [current gesture behavior](POINT_AND_HOLD.md) for movement, right-click, and thumb + index + middle scrolling. The [v1.5 interaction recovery notes](RECOVERY_AND_SCROLL.md) retain the original activation policy, relative cursor anchoring, keyboard registration, and legacy regression coverage; their old click modes and scrolling pose are historical.

Validation before release: with a live camera, confirm Start/Pause and no-hand recovery with a visible pointing hand. Check aiming, the ring appearing after a brief rest and filling over one second, cancellation by moving away, and no repeats until the pointer has traveled away from the click. Check five-finger right-clicking, cancellation when a fingertip is hidden, and reopening after both successful and canceled attempts. Turn Click off during a pending hold. Try optional practice, thumb + index + middle pinch scrolling, Escape, Accessibility loss, and cursor feedback alignment on additional displays/full-screen apps. Use the practice canvas and app's Test click target. Synthetic tests do not verify physical tracking or delivery to other apps.

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
3,377 recovery/scroll, 526 two-hand drag, 415 one-hand drag, 17 source-update, and
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

The renderer, also run by `bash scripts/test.sh`, checks 48 combinations of automatic/native and forced legacy materials, light/dark appearance, size, and disclosure state, plus resizing, five keyboard-accessible selectors, and visibility of Start/Pause while scrolling. The primary button row requires horizontal content hugging because the legacy visual-effect wrapper has no intrinsic width; forced fallback coverage catches this on newer Macs too. It additionally checks opaque accessibility fallbacks, Reduce Motion policy, backdrop input passthrough, full control opacity, and native glass/interactivity availability. Static renders do not establish the live desktop blur or interactive animation appearance; review those in a visible window. Physical hand tracking and native event delivery require separate live-camera tests.

## Practice diagnostics verification

`Sources/FeatureFlags.swift` defines `FeatureFlags.diagnostics = false`. This default omits the diagnostics preview/panel and gates recording, export, observation, and replay entry points without changing normal gesture recognition. Flip the constant to `true` locally and rebuild to test diagnostics; restore `false` before committing or publishing a build. `bash scripts/test.sh` checks the disabled screen/replay gates by default, or runs 32 guided camera-test UI states when the local flag is enabled. The Camera test entry point is separate from Practice: the test replaces the marketing/practice workspace, keeps recording/save/navigation controls outside its details scroller, and collapses technical measurements by default.

`bash scripts/test.sh` also builds and runs `Tests/PracticeDiagnosticsTests.swift`. It checks finger evidence confidence/geometry boundaries, hold-still cancellation reasons, opt-in/bounded recording, metadata allowlisting, and JSON round-trip replay through the production practice engine at 15/30/60 fps. To analyze a recording explicitly exported from Click Practice, use `build/practice-diagnostics-tests --replay "/path/to/hand-mouse-diagnostics.json"`. Replay uses selected-hand landmarks and observed pinch ratios after Vision; it does not test Vision inference or hand selection from camera images. Attempt labels are user annotations, not inferred ground truth.

With the local diagnostics flag enabled, render the production diagnostics panel inside the launch layout without requesting camera or Accessibility access:

```sh
xcrun swiftc -swift-version 5 -module-cache-path "$PWD/build/module-cache" Sources/FeatureFlags.swift Sources/PointerFilter.swift Sources/ClickGestures.swift Sources/InputMotion.swift Sources/TwoHandDrag.swift Sources/InteractionEngine.swift Sources/PracticeDiagnostics.swift Sources/PracticeDiagnosticsUI.swift Sources/StartupUI.swift Sources/GestureGuide.swift Sources/GestureDemoCanvas.swift Sources/PracticeTasks.swift Sources/FeedbackGeometry.swift Sources/FeedbackUI.swift Sources/LaunchUI.swift Tests/UIRenderSupport.swift Tests/PracticeDiagnosticsUISnapshot.swift -o build/diagnostics-ui-render
build/diagnostics-ui-render "$PWD/build/diagnostics-ui"
```

This checks preview, recording, canceled, successful, saved, paused, advanced-detail, and no-data states at both supported widths and in light/dark appearances. It checks that the camera and actions fit without scrolling, that advanced scrolling cannot move the action buttons, and that the practice game/marketing UI is absent during diagnosis. `DiagnosticResult` produces a local, read-only explanation from actual recorded outcomes and cancellation frames; it does not infer a successful gesture from missing evidence. `CameraTestPolicy` keeps presented tests on the simulated output path, blocks ordinary camera resume while reviewing a finished recording, and stops capture after recording ends. Manual validation should additionally confirm camera permissions, mirrored skeleton alignment, one-second holds, early cancellation, no repeated clicks, no system input during preview/record/review, saving after Escape, and finding the saved JSON. Keep live recordings outside version control. Neither renders nor replay proves physical recognition quality; detection thresholds and the recording schema are unchanged.
