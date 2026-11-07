#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
if ! xcrun --find swiftc >/dev/null 2>&1; then
    echo "First install Apple's Command Line Tools: xcode-select --install"
    echo "When installation finishes, double-click this installer again."
    read -r -p "Press Return to close. "
    exit 1
fi
INSTALL_DIR="${HAND_MOUSE_INSTALL_DIR:-$HOME/Applications}"
TARGET_APP="$INSTALL_DIR/Hand Mouse.app"
TARGET_EXECUTABLE="$TARGET_APP/Contents/MacOS/HandMouse"
refuse_running_target() {
    if [ -x "$TARGET_EXECUTABLE" ] && /usr/sbin/lsof -t -- "$TARGET_EXECUTABLE" >/dev/null 2>&1; then
        echo "Hand Mouse is running from: $TARGET_APP" >&2
        echo "Quit that copy, then run this installer again." >&2
        exit 1
    fi
}
refuse_running_target

echo "Building Hand Mouse."
INSTALL_BUILD=$(mktemp -d "${TMPDIR:-/tmp}/hand-mouse-install.XXXXXX")
INSTALL_STAGE=""
PREVIOUS_APP=""
TARGET_PUBLISHED=0
REPLACEMENT_COMPLETE=0
cleanup() {
    result=$?
    if [ "$REPLACEMENT_COMPLETE" -ne 1 ] && [ "$TARGET_PUBLISHED" -eq 1 ] && [ -e "$TARGET_APP" ]; then
        mv "$TARGET_APP" "$INSTALL_STAGE/Failed Hand Mouse.app" 2>/dev/null || {
            echo "Could not move the failed replacement aside: $TARGET_APP" >&2
            result=1
        }
    fi
    if [ "$REPLACEMENT_COMPLETE" -ne 1 ] && [ -n "$PREVIOUS_APP" ] && [ -e "$PREVIOUS_APP" ]; then
        if [ -e "$TARGET_APP" ]; then
            echo "Previous app remains recoverable at: $PREVIOUS_APP" >&2
            result=1
        elif ! mv "$PREVIOUS_APP" "$TARGET_APP" 2>/dev/null; then
            echo "Could not restore the previous app from: $PREVIOUS_APP" >&2
            result=1
        fi
    fi
    if [ -n "$INSTALL_STAGE" ]; then
        if [ "$REPLACEMENT_COMPLETE" -eq 1 ]; then
            rm -rf "$INSTALL_STAGE"
        elif [ -n "$PREVIOUS_APP" ] && [ -e "$PREVIOUS_APP" ]; then
            echo "Installer recovery files remain at: $INSTALL_STAGE" >&2
        else
            rm -rf "$INSTALL_STAGE"
        fi
    fi
    rm -rf "$INSTALL_BUILD"
    trap - EXIT
    exit "$result"
}
trap cleanup EXIT
HAND_MOUSE_BUILD_DIR="$INSTALL_BUILD" bash scripts/build.sh
BUILT_APP="$INSTALL_BUILD/Hand Mouse.app"
codesign --verify --deep --strict "$BUILT_APP"

mkdir -p "$INSTALL_DIR"
INSTALL_STAGE=$(mktemp -d "$INSTALL_DIR/.hand-mouse-install.XXXXXX")
STAGED_APP="$INSTALL_STAGE/Hand Mouse.app"
ditto --norsrc --noextattr "$BUILT_APP" "$STAGED_APP"
codesign --verify --deep --strict "$STAGED_APP"
bash scripts/verify-update-identity.sh "$TARGET_APP" "$STAGED_APP"

refuse_running_target
if [ -e "$TARGET_APP" ]; then
    PREVIOUS_APP="$INSTALL_STAGE/Previous Hand Mouse.app"
    mv "$TARGET_APP" "$PREVIOUS_APP"
fi
mv "$STAGED_APP" "$TARGET_APP"
TARGET_PUBLISHED=1
codesign --verify --deep --strict "$TARGET_APP"
REPLACEMENT_COMPLETE=1

UPDATE_STATE_DIR="${HAND_MOUSE_UPDATE_STATE_DIR:-$HOME/Library/Application Support/Hand Mouse}"
if mkdir -p "$UPDATE_STATE_DIR" && chmod 700 "$UPDATE_STATE_DIR"; then
    SOURCE_STATE=$(mktemp "$UPDATE_STATE_DIR/.source-checkout.XXXXXX")
    SOURCE_CHECKOUT="${HAND_MOUSE_SOURCE_CHECKOUT:-$(pwd -P)}"
    if [ -d "$SOURCE_CHECKOUT" ]; then
        SOURCE_CHECKOUT=$(cd "$SOURCE_CHECKOUT" && pwd -P)
    fi
    printf '%s\n' "$SOURCE_CHECKOUT" > "$SOURCE_STATE"
    chmod 600 "$SOURCE_STATE"
    mv "$SOURCE_STATE" "$UPDATE_STATE_DIR/source-checkout"
else
    echo "Warning: Check for Updates could not save the source checkout." >&2
fi

echo "Installed: $TARGET_APP"
echo "Next: enable Accessibility in the app, then Start camera and allow camera access."
if [ "${HAND_MOUSE_NO_OPEN:-0}" != 1 ]; then open "$TARGET_APP"; fi
