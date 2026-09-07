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
| `Sources/ForwardClick.swift` | 2D pose features, calibration capture, intentional forward-click state machine |
| `Sources/InteractionEngine.swift` | Production frame-to-pointer pipeline, freshness/permission gates, gesture/filter ordering |
| `Sources/Camera.swift` | Camera capture and Vision landmarks |
| `Sources/FrameMailbox.swift` | Bounded delivery of the newest result |
| `Sources/main.swift` | Window, camera lifecycle, feedback orchestration, permissions, mouse events |
| `Sources/FeedbackUI.swift` | Determinate click ring, status card, simulated practice canvas, nonactivating cursor overlay |
| `Sources/StartupUI.swift` | Startup palette, live setup milestones, and static camera standby artwork |
| `Sources/FeedbackGeometry.swift` | Screen-edge caption placement with a ring centered on the click target |
| `Tests/main.swift` | Deterministic gesture and pointer checks |
| `Tests/InteractionEngineTests.swift` | Production pipeline at 15/30/60 fps, intent/cancel/rearm, calibration and practice isolation |
| `Tests/install.sh` | Isolated installer replacement, failure rollback, and running-app guards |
| `scripts/sign.sh` | Persistent local signing identity, explicit certificate mode, and disposable ad-hoc mode |
| `scripts/verify-update-identity.sh` | Reject updates that would discard an existing certificate-backed identity |
| `Tests/signing.sh` | Changed binaries retain identity; different signers and ad-hoc downgrades are rejected |

Defaults: velocity-adaptive pointer smoothing from 8–50 ms; Balanced pinch threshold 0.42 hand-scale units, confirmation after at least two samples and 25 ms, reopening above 0.60 for 70 ms, and a 300 ms click cooldown. Precise uses 0.34 and Easy uses 0.50, with release 0.18 above each threshold. Confirmation tolerates 0.06 units of threshold jitter. The hand scale is the greater of palm width and 0.75 times wrist-to-middle-base distance, corrected for frame aspect ratio.

`InteractionEngine` evaluates the gesture before applying index motion, preserving the pre-gesture aim during a pinch or forward press. Forward mode requires a calibrated transition before invoking the hold timer; neither normal motion nor stillness starts it. Palm motion is measured independently of the frozen pointer. Changing settings cancels active progress. Hold duration is configurable at 0.65, 1, or 1.5 seconds and retains the existing `dwellDurationPreset` preference. Missing pinch observations preserve readiness for at most 120 ms, but cancel confirmation evidence; longer gaps disarm. A pinch attempted during cooldown is consumed rather than delayed. Camera results are coalesced to the latest frame and callbacks from old sessions are rejected. Camera and inference latency are additional to smoothing time. See the [forward gesture design](FORWARD_CLICK.md) for calibration, thresholds, and limitations.

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

Reopen the app, expand **Permissions & setup**, click **Show in Finder**, then add that exact copy to Privacy & Security → Accessibility (called Device Control and Data Access on macOS 27). Enable it and restart Hand Mouse. This does not grant permission by itself or change other apps' permissions.

Before v1.3.1, ad-hoc signatures changed with rebuilt code. Migrating that old approval to the persistent signer requires one final repair. Subsequent source builds retain the signer stored outside the checkout. Multiple development copies with the same bundle identifier can still make System Settings show a different copy; keep one active installation. Never replace the certificate requirement with a wildcard or identifier-only rule. The app and installer do not modify the TCC database or reset approvals automatically.


## Camera and click feedback

`ForwardClickDetector.progress` and `remainingSeconds` are read-only values derived from observed frame timestamps. Rendering never advances the detector or triggers a click. Reset, cancel, tracking loss, and post-click phases clear progress. A fresh movement-pose observation and forward transition are required to rearm, including after interruption. The UI hides stale feedback if delivery stops, using a 100 ms watchdog in common run-loop modes and the 120 ms tracking grace measured from the last received frame. Frames at least 200 ms old, future-dated frames, and duplicate/out-of-order timestamps cannot move or click.

Practice uses the actual target display bounds in the same engine, then scales its simulated pointer into the canvas. `InteractionDestination.practice` permits simulation without Accessibility but exposes neither `systemLocation` nor `systemClick`; the OS dispatch path consumes only those system output fields. Setup also returns before reaching dispatch. Changing output destination resets gesture intent. Calibration and camera identity/frame dimensions are kept only in process memory; a source change or capture failure discards the profile.

The cursor panel ignores mouse events, never becomes key or main, and uses no screen recording. Quartz pointer coordinates convert to AppKit using the primary screen's top edge. The label stays inside the target screen, while the ring remains at the actual click location. The panel supports other applications' Spaces/full-screen contexts and hides when its target display is unavailable. Duplicate overlay content is excluded from accessibility; the app exposes a labeled progress indicator, percentage, and state announcements without announcing every countdown frame. No decorative progress animation runs ahead of detector state.

Sleep, display sleep, user-session deactivation, and display configuration changes pause capture; resuming requires Start camera. Runtime capture errors, interruptions, selected-camera disconnects, and five consecutive Vision failures invalidate the session and offer an explicit retry. Pausing also releases the configured inputs/outputs, so the next Start discovers connected cameras again; callbacks from removed outputs are rejected. A normal no-hand frame is not treated as a processing failure. The built-in front camera remains preferred.

Validation before release: with a live camera, confirm Start/Pause, no-hand recovery, Pinch, forward setup/practice/cancel/rearm, clicks off during a countdown, Escape, Accessibility loss, and cursor ring alignment on additional displays/full-screen apps. Use the practice canvas and app's Test click target. Synthetic tests do not verify physical tracking or delivery to other apps.
