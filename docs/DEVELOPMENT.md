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
| `Sources/Gesture.swift` | Pinch detection, hold timer primitive, tuning, smoothing, preference migration |
| `Sources/ForwardClick.swift` | 2D pose features, automatic hand reference, intentional forward-click state machine |
| `Sources/InteractionEngine.swift` | Production pipeline, cursor acquisition, freshness/permission gates, gesture/filter ordering |
| `Sources/InputMotion.swift` | Cursor acquisition, scroll geometry/deltas, and activation lifecycle policy |
| `Sources/ResumeShortcut.swift` | Exclusive global pause/resume shortcut registration |
| `Sources/Camera.swift` | Camera capture and Vision landmarks |
| `Sources/FrameMailbox.swift` | Bounded delivery of the newest result |
| `Sources/main.swift` | Window, camera lifecycle, feedback orchestration, permissions, mouse events |
| `Sources/PracticeTasks.swift` | Deterministic click, scroll, and released-drag practice completion model |
| `Sources/FeedbackUI.swift` | Determinate click ring, status card, task practice surface, nonactivating cursor overlay |
| `Sources/StartupUI.swift` | Startup palette, four-card gesture guide, setup state, and static camera-off artwork |
| `Sources/FeedbackGeometry.swift` | Screen-edge caption placement with a ring centered on the click target |
| `Tests/main.swift` | Deterministic gesture and pointer checks |
| `Tests/RecoveryScrollTests.swift` | Hand return, physical mouse takeover, scrolling, practice isolation, and activation gates |
| `Tests/InteractionEngineTests.swift` | Production pipeline at 15/30/60 fps, intent/cancel/rearm, automatic reference and practice isolation |
| `Tests/GestureGuideSnapshot.swift` | Camera-free default and narrow gesture-guide review states |
| `Tests/PracticeViewSnapshot.swift` | Camera-free task, completion, and narrow practice review states |
| `Tests/UIRenderSupport.swift` | AppKit layout assertions and PNG raster support for UI review |
| `Tests/install.sh` | Isolated installer replacement, failure rollback, and running-app guards |
| `scripts/sign.sh` | Persistent local signing identity, explicit certificate mode, and disposable ad-hoc mode |
| `scripts/verify-update-identity.sh` | Reject updates that would discard an existing certificate-backed identity |
| `Tests/signing.sh` | Changed binaries retain identity; different signers and ad-hoc downgrades are rejected |

Defaults: velocity-adaptive pointer smoothing from 8–50 ms; Balanced pinch threshold 0.42 hand-scale units, confirmation after at least two samples and 25 ms, reopening above 0.60 for 70 ms, and a 300 ms click cooldown. Precise uses 0.34 and Easy uses 0.50, with release 0.18 above each threshold. Confirmation tolerates 0.06 units of threshold jitter. The hand scale is the greater of palm width and 0.75 times wrist-to-middle-base distance, corrected for frame aspect ratio.

`InteractionEngine` evaluates the gesture before applying index motion, preserving the pre-gesture aim during a pinch or forward press. Forward mode requires a forward transition relative to an automatically estimated hand reference before invoking the hold timer; neither normal motion nor stillness starts it. Palm motion is measured independently of the frozen pointer. Changing settings cancels active progress. Hold duration is configurable at 0.65, 1, or 1.5 seconds and retains the existing `dwellDurationPreset` preference. The standalone Pinch detector tolerates missing pinch observations for at most 120 ms, but the production engine cancels all input immediately on a missing index or interrupts on a callback gap over 120 ms. Returning hands must reacquire the current cursor before gesture detection resumes. A pinch attempted during cooldown is consumed rather than delayed. Camera results are coalesced to the latest frame and callbacks from old sessions are rejected. Camera and inference latency are additional to smoothing time. See the [forward gesture design](FORWARD_CLICK.md) for automatic adaptation, thresholds, and limitations.

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

`ForwardClickDetector.progress` and `remainingSeconds` are read-only values derived from observed frame timestamps. Rendering never advances the detector or triggers a click. Reset, cancel, tracking loss, and post-click phases clear progress. A fresh movement-pose observation and forward transition are required to rearm, including after interruption. The UI hides stale feedback if delivery stops, using a 100 ms watchdog in common run-loop modes and the 120 ms tracking grace measured from the last received frame. Frames at least 200 ms old, future-dated frames, and duplicate/out-of-order timestamps cannot move or click.

Practice uses the actual target display bounds in the same engine, then scales its simulated pointer into a normalized task canvas. `InteractionDestination.practice` permits simulation without Accessibility but exposes no `systemLocation`, `systemClick`, `systemScrollY`, or system drag output; the practice handler returns before OS dispatch. The click task consumes only an engine click on its drawn button. The list consumes only engine scroll deltas. Sentence selection completes only after an engine drag begins on the sentence, spans its visible endpoints, and releases. Missing, stale, blocked, source-changed, and watchdog-interrupted input cancels partial selection and requires a fresh release. Task switches reset both the model and all engine transient state. Practice enables only the gesture needed by the selected task and leaves all system-facing controls off when finished.

The cursor panel ignores mouse events, never becomes key or main, and uses no screen recording. Quartz pointer coordinates convert to AppKit using the primary screen's top edge. The label stays inside the target screen, while the ring remains at the actual click location. The panel supports other applications' Spaces/full-screen contexts and hides when its target display is unavailable. Duplicate overlay content is excluded from accessibility; the app exposes a labeled progress indicator, percentage, and state announcements without announcing every countdown frame. No decorative progress animation runs ahead of detector state.

Sleep, display sleep, user-session deactivation, and display configuration changes pause capture; resuming requires the explicit Start action or global shortcut. Runtime capture errors, interruptions, selected-camera disconnects, and five consecutive Vision failures invalidate the session and offer an explicit retry. Pausing also releases the configured inputs/outputs, so the next Start discovers connected cameras again; callbacks from removed outputs are rejected. A normal no-hand frame is not treated as a processing failure. The built-in front camera remains preferred.

## Recovery, scrolling, and keyboard activation

See [v1.5 interaction recovery](RECOVERY_AND_SCROLL.md) for the activation policy, relative cursor anchoring, scroll gesture, keyboard registration, regression coverage, and manual test checklist. These features change the production pipeline, not just the visual feedback.

Validation before release: with a live camera, confirm Start/Pause, no-hand recovery, Pinch, setup-free forward clicks, optional practice, cancel/rearm, clicks off during a countdown, Escape, Accessibility loss, and cursor ring alignment on additional displays/full-screen apps. Use the practice canvas and app's Test click target. Synthetic tests do not verify physical tracking or delivery to other apps.

## Gesture interface review

The main window opens at 900×800 points and supports a 720×650-point minimum. Its
four-card guide separates the card selected for learning from the gesture that is
currently live. Move and Click are always available; Scroll and Select text show
their off state until the corresponding control is enabled. The camera remains off
until Start is activated. These visuals never authorize movement, change gesture
thresholds, advance a detector, or claim that tracking is live.

The camera-free guide renderer exercises the production `GestureGuideView` at a
900×370 default size and a 620×350 narrow size. It asserts resolved Auto Layout and
checks for fully clipped controls before writing review images:

```sh
mkdir -p build/ui-review
xcrun swiftc -swift-version 5 Sources/StartupUI.swift Tests/UIRenderSupport.swift Tests/GestureGuideSnapshot.swift -o /tmp/hand-mouse-gesture-render
/tmp/hand-mouse-gesture-render "$PWD/build/ui-review"
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

The September 7, 2026 review rendered both guide sizes without ambiguous layout or
fully clipped controls. `bash scripts/test.sh` passed 187 core, 465 interaction,
3,377 recovery/scroll, 526 two-hand drag, 415 one-hand drag, 16 source-update, and
1,002 two-finger tap checks, plus the update shell regressions. An isolated arm64
application build completed with ad hoc signing and passed strict code-signature
verification. The Mac login was
locked, so a layer-backed full-window offscreen raster was blank and was excluded
from visual evidence; native full-window and interaction review remains required on
an unlocked session.
