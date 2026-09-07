#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
if [ "$(uname -s)" != Darwin ]; then
    echo "Hand Mouse requires macOS." >&2
    exit 1
fi
if ! xcrun --find swiftc >/dev/null 2>&1; then
    echo "Install Xcode Command Line Tools with: xcode-select --install" >&2
    exit 1
fi
BUILD_DIR="${HAND_MOUSE_BUILD_DIR:-$PWD/build}"
mkdir -p "$BUILD_DIR"
BUILD_DIR=$(cd "$BUILD_DIR" && pwd)
DEST_APP="$BUILD_DIR/Hand Mouse.app"
refuse_running_target() {
    if [ -x "$DEST_APP/Contents/MacOS/HandMouse" ] && /usr/sbin/lsof -t -- "$DEST_APP/Contents/MacOS/HandMouse" >/dev/null 2>&1; then
        echo "Quit $DEST_APP before rebuilding it." >&2
        exit 1
    fi
}
refuse_running_target
APP_STAGE=$(mktemp -d "$BUILD_DIR/.app-build.XXXXXX")
APP="$APP_STAGE/Hand Mouse.app"
BACKUP_APP="$APP_STAGE/previous.app"
APP_PUBLISHED=0
cleanup() {
    if [ "$APP_PUBLISHED" -ne 1 ] && [ -e "$BACKUP_APP" ]; then
        if [ -e "$DEST_APP" ]; then
            echo "Could not restore the previous app. It remains at: $BACKUP_APP" >&2
            return 1
        fi
        if ! mv "$BACKUP_APP" "$DEST_APP"; then
            echo "Could not restore the previous app. It remains at: $BACKUP_APP" >&2
            return 1
        fi
    fi
    rm -rf "$APP_STAGE"
}
trap cleanup EXIT
MIN_MACOS=$(/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' Info.plist)
read -r -a ARCHS <<< "${HAND_MOUSE_ARCHS:-$(uname -m)}"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$BUILD_DIR/module-cache" "$BUILD_DIR/bin"
BINARIES=()
for ARCH in "${ARCHS[@]}"; do
    case "$ARCH" in arm64|x86_64) ;; *) echo "Unsupported architecture: $ARCH" >&2; exit 1 ;; esac
    BINARY="$BUILD_DIR/bin/HandMouse-$ARCH"
    xcrun swiftc -swift-version 5 -O -target "$ARCH-apple-macosx$MIN_MACOS" \
        -module-cache-path "$BUILD_DIR/module-cache" \
        Sources/Gesture.swift Sources/ForwardClick.swift Sources/InputMotion.swift Sources/ResumeShortcut.swift Sources/InteractionEngine.swift Sources/FrameMailbox.swift Sources/Camera.swift Sources/FeedbackGeometry.swift Sources/FeedbackUI.swift Sources/StartupUI.swift Sources/main.swift \
        -framework AppKit -framework AVFoundation -framework Vision -framework ApplicationServices -framework Carbon \
        -o "$BINARY"
    BINARIES+=("$BINARY")
done
if [ "${#BINARIES[@]}" -eq 1 ]; then
    cp "${BINARIES[0]}" "$APP/Contents/MacOS/HandMouse"
else
    xcrun lipo -create "${BINARIES[@]}" -output "$APP/Contents/MacOS/HandMouse"
fi
cp Info.plist "$APP/Contents/Info.plist"
bash scripts/build-icon.sh "$BUILD_DIR"
cp "$BUILD_DIR/HandMouse.icns" "$APP/Contents/Resources/HandMouse.icns"
bash scripts/sign.sh "$APP"
bash scripts/verify-update-identity.sh "$DEST_APP" "$APP"
refuse_running_target
if [ -e "$DEST_APP" ]; then mv "$DEST_APP" "$BACKUP_APP"; fi
mv "$APP" "$DEST_APP"
APP_PUBLISHED=1
echo "Built: $DEST_APP"
