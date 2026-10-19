#!/bin/sh
# Signs an app bundle with the Developer ID and the hardened runtime when the keychain holds a Developer ID
# Application certificate, as notarizing requires. Without one it signs ad hoc, which runs on this Mac only.
#
# Usage: scripts/sign-app.sh <app> [<entitlements>]
# SIGNING_IDENTITY  the identity to sign with instead of the first Developer ID found; "-" signs ad hoc
set -eu

APP="$1"
ENTITLEMENTS="${2:-}"
IDENTITY="${SIGNING_IDENTITY:-$(security find-identity -v -p codesigning \
    | awk '/"Developer ID Application:/ { print $2; exit }')}"
IDENTITY="${IDENTITY:--}"

set -- --force --sign "$IDENTITY"
if [ -n "$ENTITLEMENTS" ]; then
    set -- "$@" --entitlements "$ENTITLEMENTS"
fi
if [ "$IDENTITY" = "-" ]; then
    echo "Signing ad hoc: no Developer ID Application certificate was found or chosen."
else
    set -- "$@" --options runtime --timestamp
fi
codesign "$@" "$APP"
