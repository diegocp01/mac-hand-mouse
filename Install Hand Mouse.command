#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
if ! xcrun --find swiftc >/dev/null 2>&1; then
    echo "First install Apple's Command Line Tools: xcode-select --install"
    echo "When installation finishes, double-click this installer again."
    read -r -p "Press Return to close. "
    exit 1
fi
echo "Building Hand Mouse. Quit any running copy before reinstalling."
INSTALL_BUILD=$(mktemp -d "${TMPDIR:-/tmp}/hand-mouse-install.XXXXXX")
trap 'rm -rf "$INSTALL_BUILD"' EXIT
HAND_MOUSE_BUILD_DIR="$INSTALL_BUILD" bash scripts/build.sh
INSTALL_DIR="${HAND_MOUSE_INSTALL_DIR:-$HOME/Applications}"
mkdir -p "$INSTALL_DIR"
ditto "$INSTALL_BUILD/Hand Mouse.app" "$INSTALL_DIR/Hand Mouse.app"
codesign --verify --deep --strict "$INSTALL_DIR/Hand Mouse.app"
echo "Installed: $INSTALL_DIR/Hand Mouse.app"
echo "Next: enable Accessibility in the app, then Start camera and allow camera access."
if [ "${HAND_MOUSE_NO_OPEN:-0}" != 1 ]; then open "$INSTALL_DIR/Hand Mouse.app"; fi
