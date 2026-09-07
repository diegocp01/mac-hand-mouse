#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Info.plist)
case "$VERSION" in ''|*[!0-9.]*) echo "Invalid app version" >&2; exit 1 ;; esac
PACKAGE_NAME="Hand-Mouse-$VERSION-macos-universal"
STAGING=$(mktemp -d "${TMPDIR:-/tmp}/hand-mouse-package.XXXXXX")
trap 'rm -rf "$STAGING"' EXIT
RELEASE_BUILD="$STAGING/build"
HAND_MOUSE_BUILD_DIR="$RELEASE_BUILD" HAND_MOUSE_ARCHS="arm64 x86_64" \
    HAND_MOUSE_SIGNING_MODE="${HAND_MOUSE_SIGNING_MODE:-adhoc}" bash scripts/build.sh
APP="$RELEASE_BUILD/Hand Mouse.app"
for ARCH in arm64 x86_64; do
    xcrun lipo "$APP/Contents/MacOS/HandMouse" -verify_arch "$ARCH"
done
mkdir -p "$STAGING/$PACKAGE_NAME" dist
ditto --norsrc --noextattr "$APP" "$STAGING/$PACKAGE_NAME/Hand Mouse.app"
cp LICENSE README.md THIRD_PARTY_NOTICES.md CONTRIBUTING.md "$STAGING/$PACKAGE_NAME/"
ditto --norsrc --noextattr assets "$STAGING/$PACKAGE_NAME/assets"
ditto --norsrc --noextattr docs "$STAGING/$PACKAGE_NAME/docs"
codesign --verify --deep --strict "$STAGING/$PACKAGE_NAME/Hand Mouse.app"
ditto -c -k --norsrc --noextattr --keepParent "$STAGING/$PACKAGE_NAME" "dist/$PACKAGE_NAME.zip"
(
    cd dist
    shasum -a 256 "$PACKAGE_NAME.zip" > "$PACKAGE_NAME.zip.sha256"
    shasum -a 256 -c "$PACKAGE_NAME.zip.sha256"
)
echo "Packaged: $PWD/dist/$PACKAGE_NAME.zip"
echo "Signing mode: ${HAND_MOUSE_SIGNING_MODE:-adhoc}. This archive is not notarized."
