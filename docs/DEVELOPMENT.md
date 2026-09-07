# Development and packaging

Requires macOS 13+ and Xcode Command Line Tools with Swift 5.7+ (or full Xcode).

```sh
bash scripts/test.sh
bash scripts/build.sh
open "build/Hand Mouse.app"
```

Builds explicitly target the minimum macOS version in `Info.plist`. The default build targets the current Mac's architecture. To build a universal app, run `HAND_MOUSE_ARCHS="arm64 x86_64" bash scripts/build.sh`. Quit running copies before replacing them; ad-hoc rebuilding may invalidate Accessibility approval.

## Code map

| File | Responsibility |
| --- | --- |
| `Sources/Gesture.swift` | Pinch state machine, tuning, smoothing |
| `Sources/Camera.swift` | Camera capture and Vision landmarks |
| `Sources/FrameMailbox.swift` | Bounded delivery of the newest result |
| `Sources/main.swift` | Window, preview, permissions, mouse events |
| `Tests/main.swift` | Deterministic gesture and pointer checks |

Defaults: 25 ms pointer smoothing; Balanced pinch threshold 0.42 hand-scale units, confirmation after at least two samples and 25 ms, reopening above 0.60 for 70 ms, and a 300 ms click cooldown. Precise uses 0.34 and Easy uses 0.50, with release 0.18 above each threshold. Confirmation tolerates 0.06 units of threshold jitter. The hand scale is the greater of palm width and 0.75 times wrist-to-middle-base distance, corrected for frame aspect ratio.

The pointer holds its aimed position during confirmation and while a pinch remains held. Missing pinch observations preserve readiness for at most 120 ms, but cancel confirmation evidence; longer gaps disarm. A pinch attempted during cooldown is consumed rather than delayed. Camera results are coalesced to the latest frame and callbacks from old sessions are rejected. Camera and inference latency are additional to smoothing time.

Tests cover confirmation, gentle pinches, duplicate prevention, reopening, cooldown, tracking loss, pointer settling, overshoot, freezing, and display-coordinate mapping. They do not use a physical camera or send mouse clicks. CI is configured for Apple Silicon and Intel; its hosted results require an actual GitHub run.

## Install verification

```sh
INSTALL_CHECK=$(mktemp -d)
HAND_MOUSE_INSTALL_DIR="$INSTALL_CHECK" HAND_MOUSE_NO_OPEN=1 bash "Install Hand Mouse.command"
# After inspection, remove the temporary app so macOS does not confuse copies.
rm -rf "$INSTALL_CHECK"
```

The installer builds in a temporary directory that it removes afterward, copies the app to `~/Applications` by default, verifies its signature, and opens it. Overrides above permit an isolated test without starting the camera or changing a user's installed app. To uninstall, quit Hand Mouse and move `~/Applications/Hand Mouse.app` to the Trash.

## Release package

```sh
bash scripts/package.sh
```

Produces `dist/Hand-Mouse-<version>-macos-universal.zip` and a SHA-256 file, containing both `arm64` and `x86_64` slices plus documentation and license. Packaging uses a temporary build directory that it removes afterward, verifies the signature and architectures, and does not publish anything. Generated apps, caches, archives, and local environment files are ignored by Git.

Packages are **ad-hoc signed, not Developer ID signed or notarized**. Gatekeeper may block downloaded binaries. Building from reviewed source is the supported installation path; a broadly distributed binary release should use Developer ID signing and notarization. No signing certificate or private key belongs in the repository.

Current live testing is on Apple Silicon. Intel and older supported macOS versions need physical hardware testing even after cross-compilation and automated tests succeed.

## Repair a stale local permission

If permission is on but the app still reports it missing, quit Hand Mouse. Reset only this app's Accessibility record:

```sh
tccutil reset Accessibility com.local.handmouse
```

Reopen the app, click **Show this app in Finder**, then add that exact copy to Privacy & Security → Accessibility (called Device Control and Data Access on macOS 27). Enable it and restart Hand Mouse. This does not grant permission by itself or change other apps' permissions.

Ad-hoc signatures change with rebuilt code. Multiple development copies with the same bundle identifier can make System Settings show a different copy. Keep one active installed copy and remove temporary test bundles. Do not weaken signature checks or use a shared wildcard signing requirement to avoid permission prompts.
