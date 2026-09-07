#!/bin/bash
# Refuse an update that would silently discard a certificate-backed approval.
set -euo pipefail
PREVIOUS="${1:?Usage: verify-update-identity.sh previous-app new-app}"
REPLACEMENT="${2:?Usage: verify-update-identity.sh previous-app new-app}"
if [ ! -e "$PREVIOUS" ]; then exit 0; fi
DETAILS=$(/usr/bin/codesign --display --verbose=2 "$PREVIOUS" 2>&1) || {
    echo 'Cannot read the installed signing identity; the existing app has not been replaced.' >&2
    exit 1
}
if [[ "$DETAILS" == *'Signature=adhoc'* ]]; then
    NEW_DETAILS=$(/usr/bin/codesign --display --verbose=2 "$REPLACEMENT" 2>&1)
    if [[ "$NEW_DETAILS" == *'Signature=adhoc'* ]]; then
        echo 'Ad-hoc test build: approvals cannot be preserved across code changes.'
    else
        echo 'Migrating a legacy ad-hoc build: reconnect Accessibility once after this update.'
    fi
    exit 0
fi
REQUIREMENT=$(/usr/bin/codesign --display -r- "$PREVIOUS" 2>/dev/null | sed -n 's/^#\{0,1\} *designated => //p')
if [ -z "$REQUIREMENT" ]; then echo 'Cannot read the previous app requirement; refusing replacement.' >&2; exit 1; fi
if ! /usr/bin/codesign --verify --deep --strict -R="${REQUIREMENT}" "$REPLACEMENT"; then
    echo 'Update stopped: its signer does not match the installed app.' >&2
    echo 'Restore the original Hand Mouse signing state or select the same signing certificate.' >&2
    echo 'The existing app has not been replaced. No privacy approvals were reset.' >&2
    exit 1
fi
