#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."

TEST_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/hand-mouse-install-tests.XXXXXX")
RUNNING_PID=""
cleanup() {
    if [ -n "$RUNNING_PID" ]; then
        kill "$RUNNING_PID" 2>/dev/null || true
        wait "$RUNNING_PID" 2>/dev/null || true
    fi
    rm -rf "$TEST_ROOT"
}
trap cleanup EXIT

FIXTURE_REPO="$TEST_ROOT/repo"
INSTALL_DIR="$TEST_ROOT/Applications"
mkdir -p "$FIXTURE_REPO/scripts"
cp "Install Hand Mouse.command" "$FIXTURE_REPO/Install Hand Mouse.command"
cp scripts/verify-update-identity.sh "$FIXTURE_REPO/scripts/verify-update-identity.sh"

cat > "$FIXTURE_REPO/scripts/build.sh" <<'SCRIPT'
#!/bin/bash
set -euo pipefail
if [ "${FIXTURE_FAIL_BUILD:-0}" = 1 ]; then exit 23; fi
APP="$HAND_MOUSE_BUILD_DIR/Hand Mouse.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp /usr/bin/true "$APP/Contents/MacOS/HandMouse"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>com.test.handmouse</string>
<key>CFBundleExecutable</key><string>HandMouse</string>
<key>CFBundlePackageType</key><string>APPL</string>
</dict></plist>
PLIST
printf '%s\n' "${FIXTURE_MARKER:-current}" > "$APP/Contents/Resources/build-marker"
codesign --force --sign - --identifier com.test.handmouse "$APP" >/dev/null
SCRIPT
chmod +x "$FIXTURE_REPO/scripts/build.sh"

run_installer() {
    HAND_MOUSE_INSTALL_DIR="$INSTALL_DIR" HAND_MOUSE_NO_OPEN=1 \
        FIXTURE_MARKER="$1" bash "$FIXTURE_REPO/Install Hand Mouse.command"
}

run_installer first >/dev/null
TARGET_APP="$INSTALL_DIR/Hand Mouse.app"
test "$(cat "$TARGET_APP/Contents/Resources/build-marker")" = first
codesign --verify --deep --strict "$TARGET_APP"

touch "$TARGET_APP/Contents/Resources/stale-from-old-version"
run_installer second >/dev/null
test "$(cat "$TARGET_APP/Contents/Resources/build-marker")" = second
test ! -e "$TARGET_APP/Contents/Resources/stale-from-old-version"
codesign --verify --deep --strict "$TARGET_APP"
test -z "$(find "$INSTALL_DIR" -maxdepth 1 -name '.hand-mouse-install.*' -print -quit)"

mkdir -p "$TEST_ROOT/bin"
cat > "$TEST_ROOT/bin/codesign" <<'SCRIPT'
#!/bin/bash
set -euo pipefail
count=0
if [ -f "$CODESIGN_COUNT_FILE" ]; then count=$(cat "$CODESIGN_COUNT_FILE"); fi
count=$((count + 1))
printf '%s\n' "$count" > "$CODESIGN_COUNT_FILE"
if [ "$count" -eq 4 ]; then exit 24; fi
exec /usr/bin/codesign "$@"
SCRIPT
chmod +x "$TEST_ROOT/bin/codesign"
if PATH="$TEST_ROOT/bin:$PATH" CODESIGN_COUNT_FILE="$TEST_ROOT/codesign-count" \
    HAND_MOUSE_INSTALL_DIR="$INSTALL_DIR" HAND_MOUSE_NO_OPEN=1 FIXTURE_MARKER=bad \
    bash "$FIXTURE_REPO/Install Hand Mouse.command" >/dev/null 2>&1; then
    echo "Installer unexpectedly kept an unverified published replacement" >&2
    exit 1
fi
test "$(cat "$TARGET_APP/Contents/Resources/build-marker")" = second
codesign --verify --deep --strict "$TARGET_APP"
test -z "$(find "$INSTALL_DIR" -maxdepth 1 -name '.hand-mouse-install.*' -print -quit)"

if HAND_MOUSE_INSTALL_DIR="$INSTALL_DIR" HAND_MOUSE_NO_OPEN=1 FIXTURE_FAIL_BUILD=1 \
    bash "$FIXTURE_REPO/Install Hand Mouse.command" >/dev/null 2>&1; then
    echo "Installer unexpectedly succeeded after a build failure" >&2
    exit 1
fi
test "$(cat "$TARGET_APP/Contents/Resources/build-marker")" = second

printf '%s\n' '#include <unistd.h>' 'int main(void) { sleep(30); return 0; }' \
    | xcrun clang -x c - -o "$TARGET_APP/Contents/MacOS/HandMouse"
codesign --force --sign - --identifier com.test.handmouse "$TARGET_APP" >/dev/null
"$TARGET_APP/Contents/MacOS/HandMouse" 30 &
RUNNING_PID=$!
for _ in 1 2 3 4 5; do
    if /usr/sbin/lsof -t -- "$TARGET_APP/Contents/MacOS/HandMouse" >/dev/null 2>&1; then break; fi
    sleep 0.1
done
if ! /usr/sbin/lsof -t -- "$TARGET_APP/Contents/MacOS/HandMouse" >/dev/null 2>&1; then
    echo "Test fixture did not keep the destination executable open" >&2
    exit 1
fi
if HAND_MOUSE_INSTALL_DIR="$INSTALL_DIR" HAND_MOUSE_NO_OPEN=1 FIXTURE_MARKER=third \
    bash "$FIXTURE_REPO/Install Hand Mouse.command" >"$TEST_ROOT/running.log" 2>&1; then
    echo "Installer replaced a running destination" >&2
    exit 1
fi
grep -q "Hand Mouse is running from:" "$TEST_ROOT/running.log"
kill "$RUNNING_PID"
wait "$RUNNING_PID" 2>/dev/null || true
RUNNING_PID=""

echo "Passed isolated installer replacement, stale-file, rollback, build-failure, and running-app checks."
