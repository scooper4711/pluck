#!/bin/sh
# Signs a disk image with the Developer ID, has Apple notarize it, and staples the ticket to it, so Gatekeeper
# opens the app inside on any Mac without warning. The app must already be signed with the Developer ID.
#
# Usage: scripts/notarize.sh <disk image>
# NOTARY_PROFILE  the notarytool keychain profile to use (default tableside-notary), made once with
#                 xcrun notarytool store-credentials tableside-notary --apple-id <email> --team-id <team ID>
# NOTARY_APPLE_ID, NOTARY_TEAM_ID, NOTARY_PASSWORD  used instead when NOTARY_APPLE_ID is set, as on GitHub
set -eu

DMG="$1"
IDENTITY="${SIGNING_IDENTITY:-$(security find-identity -v -p codesigning \
    | awk '/"Developer ID Application:/ { print $2; exit }')}"

[ -f "$DMG" ] || { echo "Notarizing failed: $DMG does not exist." >&2; exit 1; }
[ -n "$IDENTITY" ] || {
    echo "Notarizing failed: there is no Developer ID Application certificate in the keychain." >&2
    exit 1
}

codesign --force --sign "$IDENTITY" --timestamp "$DMG"

if [ -n "${NOTARY_APPLE_ID:-}" ]; then
    set -- --apple-id "$NOTARY_APPLE_ID" --team-id "$NOTARY_TEAM_ID" --password "$NOTARY_PASSWORD"
else
    set -- --keychain-profile "${NOTARY_PROFILE:-tableside-notary}"
fi
RESULT="$(xcrun notarytool submit "$DMG" "$@" --wait --output-format json)"
STATUS="$(printf '%s' "$RESULT" | plutil -extract status raw -o - -)"
if [ "$STATUS" != "Accepted" ]; then
    xcrun notarytool log "$(printf '%s' "$RESULT" | plutil -extract id raw -o - -)" "$@" >&2 || true
    echo "Notarizing failed: Apple answered \"$STATUS\" for $DMG." >&2
    exit 1
fi
xcrun stapler staple "$DMG"
echo "Notarized $DMG"
