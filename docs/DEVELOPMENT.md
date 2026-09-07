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
| `Sources/main.swift` | Window, preview, permissions, mouse events |
| `Tests/main.swift` | Deterministic gesture and pointer checks |

Defaults: 25 ms smoothing, pinch below 0.34 palm widths for 30 ms, reopening above 0.48 for 100 ms, 300 ms click cooldown, and pointer freeze below 0.38 palm widths. Camera and inference latency are additional to smoothing time.

Tests cover confirmation, gentle pinches, duplicate prevention, reopening, cooldown, tracking loss, pointer settling, overshoot, freezing, and display-coordinate mapping. They do not use a physical camera or send mouse clicks. CI is configured for Apple Silicon and Intel; its hosted results require an actual GitHub run.

## Install verification

```sh
HAND_MOUSE_INSTALL_DIR="$PWD/build/test-install" HAND_MOUSE_NO_OPEN=1 bash "Install Hand Mouse.command"
```

The installer builds under `build/install/`, copies the app to `~/Applications` by default, verifies its signature, and opens it. Overrides above permit an isolated test without starting the camera or changing a user's installed app. To uninstall, quit Hand Mouse and move `~/Applications/Hand Mouse.app` to the Trash.

## Release package

```sh
bash scripts/package.sh
```

Produces `dist/Hand-Mouse-<version>-macos-universal.zip` and a SHA-256 file, containing both `arm64` and `x86_64` slices plus documentation and license. Packaging builds under `build/release/`, verifies the signature and architectures, and does not publish anything. Generated apps, caches, archives, and local environment files are ignored by Git.

Packages are **ad-hoc signed, not Developer ID signed or notarized**. Gatekeeper may block downloaded binaries. Building from reviewed source is the supported installation path; a broadly distributed binary release should use Developer ID signing and notarization. No signing certificate or private key belongs in the repository.

Current live testing is on Apple Silicon. Intel and older supported macOS versions need physical hardware testing even after cross-compilation and automated tests succeed.
