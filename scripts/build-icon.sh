#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
ICON_BUILD="${1:-$PWD/build}"
ICONSET="$ICON_BUILD/HandMouse.iconset"
mkdir -p "$ICONSET"
for SIZE in 16 32 128 256 512; do
    sips -z "$SIZE" "$SIZE" assets/app-icon.png --out "$ICONSET/icon_${SIZE}x${SIZE}.png" >/dev/null
    DOUBLE=$((SIZE * 2))
    sips -z "$DOUBLE" "$DOUBLE" assets/app-icon.png --out "$ICONSET/icon_${SIZE}x${SIZE}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$ICON_BUILD/HandMouse.icns"
