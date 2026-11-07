#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."
TEST_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/hand-mouse-update-tests.XXXXXX")
cleanup() {
    result=$?
    if [ "$result" -ne 0 ] && [ -f "$STATE/update-result" ]; then cat "$STATE/update-result" >&2; fi
    if [ "$result" -ne 0 ] && [ -f "$STATE/update.log" ]; then cat "$STATE/update.log" >&2; fi
    rm -rf "$TEST_ROOT"
    exit "$result"
}
trap cleanup EXIT
PUBLISHER="$TEST_ROOT/publisher"
REMOTE="$TEST_ROOT/remote.git"
SOURCE="$TEST_ROOT/source"
TARGET="$TEST_ROOT/Applications/Hand Mouse.app"
STATE="$TEST_ROOT/state"
GLOBAL_CONFIG="$TEST_ROOT/gitconfig"

/usr/bin/git init --quiet --initial-branch=main "$PUBLISHER"
/usr/bin/git -C "$PUBLISHER" config user.name "Hand Mouse Tests"
/usr/bin/git -C "$PUBLISHER" config user.email "tests@example.invalid"
mkdir -p "$PUBLISHER/scripts"
printf '%s\n' old > "$PUBLISHER/VERSION"
cp scripts/update-and-relaunch.sh "$PUBLISHER/scripts/update-and-relaunch.sh"
cat > "$PUBLISHER/Install Hand Mouse.command" <<'INSTALLER'
#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
APP="$HAND_MOUSE_INSTALL_DIR/Hand Mouse.app"
mkdir -p "$APP/Contents/Resources"
cp VERSION "$APP/Contents/Resources/version"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict><key>CFBundleShortVersionString</key><string>test</string></dict></plist>
PLIST
INSTALLER
chmod +x "$PUBLISHER/Install Hand Mouse.command"
/usr/bin/git -C "$PUBLISHER" add .
/usr/bin/git -C "$PUBLISHER" commit --quiet -m initial
/usr/bin/git init --quiet --bare "$REMOTE"
/usr/bin/git -C "$PUBLISHER" remote add origin "$REMOTE"
/usr/bin/git -C "$PUBLISHER" push --quiet -u origin main
/usr/bin/git clone --quiet "$REMOTE" "$SOURCE"
/usr/bin/git -C "$SOURCE" remote set-url origin https://github.com/diegocp01/mac-hand-mouse.git
/usr/bin/git config --file "$GLOBAL_CONFIG" url."file://$REMOTE".insteadOf https://github.com/diegocp01/mac-hand-mouse.git
SOURCE_HEAD=$(/usr/bin/git -C "$SOURCE" rev-parse HEAD)

mkdir -p "$TARGET/Contents/Resources"
printf '%s\n' old > "$TARGET/Contents/Resources/version"
printf '%s\n' new > "$PUBLISHER/VERSION"
/usr/bin/git -C "$PUBLISHER" add VERSION
/usr/bin/git -C "$PUBLISHER" commit --quiet -m update
/usr/bin/git -C "$PUBLISHER" push --quiet
EXPECTED=$(/usr/bin/git -C "$PUBLISHER" rev-parse HEAD)

GIT_CONFIG_GLOBAL="$GLOBAL_CONFIG" HAND_MOUSE_NO_OPEN=1 \
    bash scripts/update-and-relaunch.sh "$SOURCE" "$TARGET" 999999 "$EXPECTED" "$STATE"
test "$(/usr/bin/git -C "$SOURCE" rev-parse HEAD)" = "$SOURCE_HEAD"
test "$(cat "$TARGET/Contents/Resources/version")" = new
grep -q '^success$' "$STATE/update-result"
test "$(/usr/bin/git -C "$SOURCE" worktree list --porcelain | grep -c '^worktree ')" = 1

printf '%s\n' newest > "$PUBLISHER/VERSION"
/usr/bin/git -C "$PUBLISHER" add VERSION
/usr/bin/git -C "$PUBLISHER" commit --quiet -m second-update
/usr/bin/git -C "$PUBLISHER" push --quiet
NEXT=$(/usr/bin/git -C "$PUBLISHER" rev-parse HEAD)
/usr/bin/git -C "$SOURCE" switch --quiet -c feature/local-work
printf '%s\n' local-change >> "$SOURCE/VERSION"
SOURCE_STATUS=$(/usr/bin/git -C "$SOURCE" status --porcelain --untracked-files=normal)
GIT_CONFIG_GLOBAL="$GLOBAL_CONFIG" HAND_MOUSE_NO_OPEN=1 \
    bash scripts/update-and-relaunch.sh "$SOURCE" "$TARGET" 999999 "$NEXT" "$STATE"
test "$(/usr/bin/git -C "$SOURCE" symbolic-ref --short HEAD)" = feature/local-work
test "$(/usr/bin/git -C "$SOURCE" rev-parse HEAD)" = "$SOURCE_HEAD"
test "$(/usr/bin/git -C "$SOURCE" status --porcelain --untracked-files=normal)" = "$SOURCE_STATUS"
test "$(tail -n 1 "$SOURCE/VERSION")" = local-change
test "$(cat "$TARGET/Contents/Resources/version")" = newest
grep -q '^success$' "$STATE/update-result"
test "$(/usr/bin/git -C "$SOURCE" worktree list --porcelain | grep -c '^worktree ')" = 1

/usr/bin/git -C "$SOURCE" remote set-url origin "$REMOTE"
if GIT_CONFIG_GLOBAL="$GLOBAL_CONFIG" HAND_MOUSE_NO_OPEN=1 \
    bash scripts/update-and-relaunch.sh "$SOURCE" "$TARGET" 999999 "$NEXT" "$STATE" >/dev/null 2>&1; then
    echo "Updater accepted a non-official remote" >&2
    exit 1
fi
grep -q 'official Hand Mouse repository' "$STATE/update-result"

echo "Passed latest-main install, untouched feature checkout, reinstall, and official-origin update checks."
