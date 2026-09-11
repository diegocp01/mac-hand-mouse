#!/bin/bash
set -euo pipefail
umask 077

SOURCE="${1:?source checkout required}"
TARGET_APP="${2:?target app required}"
RUNNING_PID="${3:?running pid required}"
EXPECTED_COMMIT="${4:?expected commit required}"
STATE_DIR="${5:?state directory required}"
LOG="$STATE_DIR/update.log"
RESULT="$STATE_DIR/update-result"
export GIT_TERMINAL_PROMPT=0
export GIT_SSH_COMMAND='/usr/bin/ssh -oBatchMode=yes -oStrictHostKeyChecking=yes -oConnectTimeout=15'
mkdir -p "$STATE_DIR"
chmod 700 "$STATE_DIR"

write_result() {
    printf '%s\n%s\n' "$1" "$2" > "$RESULT"
}

reopen() {
    if [ "${HAND_MOUSE_NO_OPEN:-0}" != 1 ] && [ -d "$TARGET_APP" ]; then
        /usr/bin/open "$TARGET_APP" >/dev/null 2>&1 || true
    fi
}

fail() {
    write_result failure "$1"
    reopen
    exit 1
}

case "$SOURCE" in ""|/) fail "The saved source checkout is unsafe." ;; esac
case "$TARGET_APP" in *.app) ;; *) fail "The installed app path is invalid." ;; esac
[ -e "$SOURCE/.git" ] || fail "The saved source checkout is unavailable."
ORIGIN=$(/usr/bin/git -C "$SOURCE" config --get remote.origin.url 2>/dev/null || true)
case "$ORIGIN" in
    https://github.com/diegocp01/mac-hand-mouse.git|https://github.com/diegocp01/mac-hand-mouse|git@github.com:diegocp01/mac-hand-mouse.git|git@github.com:diegocp01/mac-hand-mouse|ssh://git@github.com/diegocp01/mac-hand-mouse.git|ssh://git@github.com/diegocp01/mac-hand-mouse) ;;
    *) fail "The source checkout does not use the official Hand Mouse repository." ;;
esac

for _ in {1..150}; do
    if ! /bin/kill -0 "$RUNNING_PID" 2>/dev/null; then break; fi
    /bin/sleep 0.1
done
if /bin/kill -0 "$RUNNING_PID" 2>/dev/null; then fail "Hand Mouse did not quit in time."; fi

run_fetch() {
    /usr/bin/git -C "$SOURCE" fetch --quiet origin main >"$LOG" 2>&1 &
    fetch_pid=$!
    for _ in {1..300}; do
        if ! /bin/kill -0 "$fetch_pid" 2>/dev/null; then wait "$fetch_pid"; return $?; fi
        /bin/sleep 0.1
    done
    /bin/kill "$fetch_pid" 2>/dev/null || true
    wait "$fetch_pid" 2>/dev/null || true
    return 124
}

if ! run_fetch; then
    fail "Git could not fetch the latest version. See $LOG"
fi
REMOTE_COMMIT=$(/usr/bin/git -C "$SOURCE" rev-parse origin/main 2>/dev/null || true)
if [ -z "$REMOTE_COMMIT" ] || ! /usr/bin/git -C "$SOURCE" merge-base --is-ancestor "$EXPECTED_COMMIT" "$REMOTE_COMMIT" >/dev/null 2>&1; then
    fail "GitHub changed unexpectedly during the update. No app was replaced."
fi

UPDATE_WORKTREE=""
cleanup_worktree() {
    result=$?
    if [ -n "$UPDATE_WORKTREE" ]; then
        /usr/bin/git -C "$SOURCE" worktree remove --force "$UPDATE_WORKTREE" >>"$LOG" 2>&1 || true
    fi
    trap - EXIT
    exit "$result"
}
trap cleanup_worktree EXIT
WORKTREE_PATH=$(mktemp -d "$STATE_DIR/update-source.XXXXXX")
rmdir "$WORKTREE_PATH"
if ! /usr/bin/git -C "$SOURCE" worktree add --quiet --detach "$WORKTREE_PATH" "$REMOTE_COMMIT" >>"$LOG" 2>&1; then
    fail "The latest GitHub version could not be prepared. See $LOG"
fi
UPDATE_WORKTREE="$WORKTREE_PATH"
[ -f "$UPDATE_WORKTREE/Install Hand Mouse.command" ] || fail "The installer is missing from the latest GitHub version."

TARGET_PARENT=$(/usr/bin/dirname "$TARGET_APP")
if ! HAND_MOUSE_INSTALL_DIR="$TARGET_PARENT" HAND_MOUSE_NO_OPEN=1 HAND_MOUSE_SOURCE_CHECKOUT="$SOURCE" \
    /bin/bash "$UPDATE_WORKTREE/Install Hand Mouse.command" >>"$LOG" 2>&1; then
    fail "The update could not be installed. The previous app was kept. See $LOG"
fi

VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$TARGET_APP/Contents/Info.plist" 2>/dev/null || true)
write_result success "Hand Mouse ${VERSION:-was updated} is ready."
reopen
