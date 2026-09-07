#!/bin/bash
set -euo pipefail
umask 077
cd "$(dirname "$0")/.."
TEST_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/hand-mouse-signing-tests.XXXXXX")
TEST_ROOT=$(cd "$TEST_ROOT" && pwd -P)
cleanup() {
    for state in "$TEST_ROOT/state-a" "$TEST_ROOT/state-b"; do
        /usr/bin/security delete-keychain "$state/identity.keychain-db" >/dev/null 2>&1 || true
    done
    rm -rf "$TEST_ROOT"
}
trap cleanup EXIT
ORIGINAL_KEYCHAINS=$(/usr/bin/security list-keychains -d user)
ORIGINAL_DEFAULT=$(/usr/bin/security default-keychain -d user)

fixture() {
    local app="$1" result="$2"
    mkdir -p "$app/Contents/MacOS"
    printf 'int main(void) { return %s; }\n' "$result" | xcrun clang -x c - -o "$app/Contents/MacOS/HandMouse"
    cat > "$app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>com.local.handmouse</string>
<key>CFBundleExecutable</key><string>HandMouse</string>
<key>CFBundlePackageType</key><string>APPL</string>
</dict></plist>
PLIST
}
sign_local() {
    HAND_MOUSE_SIGNING_MODE=local HAND_MOUSE_SIGNING_DIR="$2" bash scripts/sign.sh "$1" >/dev/null
}
requirement() { /usr/bin/codesign --display -r- "$1" 2>/dev/null; }
ONE="$TEST_ROOT/checkout-one/Hand Mouse.app"
TWO="$TEST_ROOT/checkout-two/Hand Mouse.app"
OTHER="$TEST_ROOT/another-user/Hand Mouse.app"
ADHOC="$TEST_ROOT/adhoc/Hand Mouse.app"
fixture "$ONE" 1
fixture "$TWO" 2
fixture "$OTHER" 3
fixture "$ADHOC" 4
sign_local "$ONE" "$TEST_ROOT/state-a"
CURRENT_KEYCHAINS=$(/usr/bin/security list-keychains -d user)
while IFS= read -r keychain_line; do
    [[ "$CURRENT_KEYCHAINS" == *"$keychain_line"* ]]
done <<< "$ORIGINAL_KEYCHAINS"
test "$ORIGINAL_DEFAULT" = "$(/usr/bin/security default-keychain -d user)"
FIRST_ID=$(cat "$TEST_ROOT/state-a/identity.sha1")
sign_local "$TWO" "$TEST_ROOT/state-a"
test "$FIRST_ID" = "$(cat "$TEST_ROOT/state-a/identity.sha1")"
test "$(requirement "$ONE")" = "$(requirement "$TWO")"
if cmp -s "$ONE/Contents/MacOS/HandMouse" "$TWO/Contents/MacOS/HandMouse"; then
    echo 'Fixtures must contain different binaries.' >&2; exit 1
fi
bash scripts/verify-update-identity.sh "$ONE" "$TWO"
test "$(stat -f %Lp "$TEST_ROOT/state-a")" = 700
test "$(stat -f %Lp "$TEST_ROOT/state-a/password")" = 600
test "$(stat -f %Lp "$TEST_ROOT/state-a/identity.keychain-db")" = 600
test ! -d "$TEST_ROOT/state-a/.lock"
test -z "$(find "$TEST_ROOT/state-a" -name '*.pem' -o -name '*.p12')"

sign_local "$OTHER" "$TEST_ROOT/state-b"
test "$FIRST_ID" != "$(cat "$TEST_ROOT/state-b/identity.sha1")"
if bash scripts/verify-update-identity.sh "$ONE" "$OTHER" >/dev/null 2>&1; then
    echo 'A different local signer was incorrectly accepted as an update.' >&2; exit 1
fi
HAND_MOUSE_SIGNING_MODE=adhoc bash scripts/sign.sh "$ADHOC" >/dev/null
bash scripts/verify-update-identity.sh "$ADHOC" "$ONE"
if bash scripts/verify-update-identity.sh "$ONE" "$ADHOC" >/dev/null 2>&1; then
    echo 'A stable installation was incorrectly downgraded to ad-hoc signing.' >&2; exit 1
fi

mv "$TEST_ROOT/state-a/identity.sha1" "$TEST_ROOT/saved-fingerprint"
if sign_local "$TWO" "$TEST_ROOT/state-a" >/dev/null 2>&1; then
    echo 'An incomplete identity was silently regenerated.' >&2; exit 1
fi
test ! -e "$TEST_ROOT/state-a/identity.sha1"
mv "$TEST_ROOT/saved-fingerprint" "$TEST_ROOT/state-a/identity.sha1"
sign_local "$TWO" "$TEST_ROOT/state-a"
bash scripts/verify-update-identity.sh "$ONE" "$TWO"

mkdir "$TEST_ROOT/state-a/.lock"
if sign_local "$TWO" "$TEST_ROOT/state-a" >/dev/null 2>&1; then
    echo 'Concurrent signing ignored the identity lock.' >&2; exit 1
fi
test -d "$TEST_ROOT/state-a/.lock"
rmdir "$TEST_ROOT/state-a/.lock"
cleanup
trap - EXIT
test "$ORIGINAL_KEYCHAINS" = "$(/usr/bin/security list-keychains -d user)"
echo 'Passed signing persistence, keychain preservation, cross-checkout update, signer isolation, legacy migration, downgrade refusal, private state, incomplete-state, and locking checks.'
