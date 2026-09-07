#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
BUILD_DIR="${HAND_MOUSE_BUILD_DIR:-$PWD/build}"
mkdir -p "$BUILD_DIR"
BUILD_DIR=$(cd "$BUILD_DIR" && pwd)
APP="$BUILD_DIR/Hand Mouse.app"
EXECUTABLE="$APP/Contents/MacOS/HandMouse"
if [ -x "$EXECUTABLE" ] && /usr/sbin/lsof -t -- "$EXECUTABLE" >/dev/null 2>&1; then
    echo "Hand Mouse is already running. Quit it before rebuilding."
    open "$APP"
    exit 0
fi
HAND_MOUSE_BUILD_DIR="$BUILD_DIR" bash scripts/build.sh
open "$APP"
