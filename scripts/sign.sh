#!/bin/bash
# Source installs reuse one private, per-user signing identity across checkouts.
set +x
set -euo pipefail
umask 077
APP="${1:?Usage: sign.sh app-bundle}"
MODE="${HAND_MOUSE_SIGNING_MODE:-local}"
IDENTIFIER=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP/Contents/Info.plist")
if [ "$IDENTIFIER" != com.local.handmouse ]; then
    echo 'Refusing to sign a bundle that is not Hand Mouse.' >&2
    exit 1
fi

SIGNING_DIR=""
LOCK_DIR=""
BOOTSTRAP=""
CREATING=0
KEYCHAIN=""
cleanup() {
    if [ "$CREATING" -eq 1 ]; then
        /usr/bin/security delete-keychain "$KEYCHAIN" >/dev/null 2>&1 || true
        rm -f "$SIGNING_DIR/password" "$SIGNING_DIR/identity.sha1"
    fi
    if [ -n "$BOOTSTRAP" ]; then rm -rf "$BOOTSTRAP"; fi
    if [ -n "$KEYCHAIN" ]; then /usr/bin/security lock-keychain "$KEYCHAIN" >/dev/null 2>&1 || true; fi
    if [ -n "$LOCK_DIR" ]; then rmdir "$LOCK_DIR"; fi
}
trap cleanup EXIT

SIGN_ARGS=(--force --identifier "$IDENTIFIER")
case "$MODE" in
    local)
        SIGNING_DIR="${HAND_MOUSE_SIGNING_DIR:-$HOME/Library/Application Support/Hand Mouse/Signing}"
        if [ -L "$SIGNING_DIR" ]; then echo 'Signing state must not be a symbolic link.' >&2; exit 1; fi
        mkdir -p "$SIGNING_DIR"
        SIGNING_DIR=$(cd "$SIGNING_DIR" && pwd)
        if [ ! -O "$SIGNING_DIR" ]; then echo 'Signing state must belong to the current user.' >&2; exit 1; fi
        chmod 700 "$SIGNING_DIR"
        if ! mkdir "$SIGNING_DIR/.lock" 2>/dev/null; then
            echo "Another Hand Mouse signing operation is active. Retry after it finishes. Lock: $SIGNING_DIR/.lock" >&2
            exit 1
        fi
        LOCK_DIR="$SIGNING_DIR/.lock"
        KEYCHAIN="$SIGNING_DIR/identity.keychain-db"
        PASSWORD_FILE="$SIGNING_DIR/password"
        IDENTITY_FILE="$SIGNING_DIR/identity.sha1"
        for state_file in "$KEYCHAIN" "$PASSWORD_FILE" "$IDENTITY_FILE"; do
            if [ -L "$state_file" ]; then echo 'Signing state files must not be symbolic links.' >&2; exit 1; fi
        done

        if [ ! -e "$KEYCHAIN" ] && [ ! -e "$PASSWORD_FILE" ] && [ ! -e "$IDENTITY_FILE" ]; then
            echo 'Creating a local Hand Mouse signing identity (used again for future updates).'
            CREATING=1
            BOOTSTRAP=$(mktemp -d "$SIGNING_DIR/.bootstrap.XXXXXX")
            /usr/bin/openssl rand -hex 32 > "$PASSWORD_FILE"
            PASSWORD=$(cat "$PASSWORD_FILE")
            cat > "$BOOTSTRAP/certificate.cnf" <<'CONFIG'
[req]
prompt = no
distinguished_name = subject
x509_extensions = signing
[subject]
CN = Hand Mouse Local Signing
[signing]
basicConstraints = critical,CA:false
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
subjectKeyIdentifier = hash
CONFIG
            /usr/bin/openssl req -new -newkey rsa:3072 -nodes -x509 -sha256 -days 3650 \
                -config "$BOOTSTRAP/certificate.cnf" -keyout "$BOOTSTRAP/key.pem" \
                -out "$BOOTSTRAP/certificate.pem" >/dev/null 2>&1
            /usr/bin/openssl pkcs12 -export -inkey "$BOOTSTRAP/key.pem" -in "$BOOTSTRAP/certificate.pem" \
                -name 'Hand Mouse Local Signing' -out "$BOOTSTRAP/identity.p12" -passout "file:$PASSWORD_FILE"
            /usr/bin/security create-keychain -p "$PASSWORD" "$KEYCHAIN"
            /usr/bin/security set-keychain-settings -lut 600 "$KEYCHAIN"
            /usr/bin/security unlock-keychain -p "$PASSWORD" "$KEYCHAIN"
            # Only codesign is pre-authorized; the imported private key is non-extractable.
            /usr/bin/security import "$BOOTSTRAP/identity.p12" -k "$KEYCHAIN" -P "$PASSWORD" \
                -x -T /usr/bin/codesign >/dev/null
            /usr/bin/openssl x509 -in "$BOOTSTRAP/certificate.pem" -noout -fingerprint -sha1 \
                | cut -d= -f2 | tr -d ':' > "$IDENTITY_FILE"
            chmod 600 "$KEYCHAIN" "$PASSWORD_FILE" "$IDENTITY_FILE"
            CREATING=0
            rm -rf "$BOOTSTRAP"; BOOTSTRAP=""
        elif [ ! -f "$KEYCHAIN" ] || [ ! -f "$PASSWORD_FILE" ] || [ ! -f "$IDENTITY_FILE" ]; then
            echo "The saved signing identity is incomplete. Restore its files from backup: $SIGNING_DIR" >&2
            echo 'No new identity was generated and the existing app has not been replaced.' >&2
            exit 1
        fi

        IDENTITY=$(cat "$IDENTITY_FILE")
        if [[ ! "$IDENTITY" =~ ^[[:xdigit:]]{40}$ ]]; then echo 'Invalid saved signing certificate fingerprint.' >&2; exit 1; fi
        PASSWORD=$(cat "$PASSWORD_FILE")
        /usr/bin/security unlock-keychain -p "$PASSWORD" "$KEYCHAIN"
        # Older macOS versions also consult the search list when resolving a signer.
        # Preserve the user's other keychains; adding a lookup path does not trust a certificate.
        SEARCH_KEYCHAINS=()
        KEYCHAIN_LISTED=0
        while IFS= read -r keychain_line; do
            search_keychain="${keychain_line#*\"}"
            search_keychain="${search_keychain%\"*}"
            [ -n "$search_keychain" ] || continue
            SEARCH_KEYCHAINS+=("$search_keychain")
            if [ "$search_keychain" = "$KEYCHAIN" ]; then KEYCHAIN_LISTED=1; fi
        done < <(/usr/bin/security list-keychains -d user)
        if [ "$KEYCHAIN_LISTED" -ne 1 ]; then
            /usr/bin/security list-keychains -d user -s "${SEARCH_KEYCHAINS[@]}" "$KEYCHAIN"
        fi
        SIGN_ARGS+=(--sign "$IDENTITY" --keychain "$KEYCHAIN" --timestamp=none)
        ;;
    identity)
        IDENTITY="${HAND_MOUSE_SIGNING_IDENTITY:?Set HAND_MOUSE_SIGNING_IDENTITY to your signing certificate}"
        if [ "$IDENTITY" = - ]; then echo 'Use adhoc mode explicitly for unsigned test artifacts.' >&2; exit 1; fi
        SIGN_ARGS+=(--sign "$IDENTITY")
        if [ -n "${HAND_MOUSE_SIGNING_KEYCHAIN:-}" ]; then SIGN_ARGS+=(--keychain "$HAND_MOUSE_SIGNING_KEYCHAIN"); fi
        ;;
    adhoc)
        SIGN_ARGS+=(--sign -)
        ;;
    *) echo "Unknown signing mode: $MODE (local, identity, or adhoc)." >&2; exit 1 ;;
esac

/usr/libexec/PlistBuddy -c 'Delete :HandMouseSigningMode' "$APP/Contents/Info.plist" 2>/dev/null || true
/usr/libexec/PlistBuddy -c "Add :HandMouseSigningMode string $MODE" "$APP/Contents/Info.plist"
if ! /usr/bin/codesign "${SIGN_ARGS[@]}" "$APP"; then
    echo 'Signing failed. The existing app and saved identity have not been replaced.' >&2
    if [ "$MODE" = local ]; then
        # Public certificate status helps diagnose OS/keychain failures; never trace secrets.
        /usr/bin/security find-identity -p codesigning "$KEYCHAIN" >&2 || true
    fi
    exit 1
fi
/usr/bin/codesign --verify --deep --strict "$APP"
echo "Signed Hand Mouse ($MODE)."
