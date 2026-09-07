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
APP="$BUILD_DIR/Hand Mouse.app"
MIN_MACOS=$(/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' Info.plist)
read -r -a ARCHS <<< "${HAND_MOUSE_ARCHS:-$(uname -m)}"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$BUILD_DIR/module-cache" "$BUILD_DIR/bin"
BINARIES=()
for ARCH in "${ARCHS[@]}"; do
    case "$ARCH" in arm64|x86_64) ;; *) echo "Unsupported architecture: $ARCH" >&2; exit 1 ;; esac
    BINARY="$BUILD_DIR/bin/HandMouse-$ARCH"
    xcrun swiftc -swift-version 5 -O -target "$ARCH-apple-macosx$MIN_MACOS" \
        -module-cache-path "$BUILD_DIR/module-cache" \
        Sources/Gesture.swift Sources/FrameMailbox.swift Sources/Camera.swift Sources/main.swift \
        -framework AppKit -framework AVFoundation -framework Vision -framework ApplicationServices \
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
codesign --force --sign - --identifier com.local.handmouse "$APP"
codesign --verify --deep --strict "$APP"
echo "Built: $APP"
