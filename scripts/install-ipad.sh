#!/bin/sh
# Builds the iPad app, installs it on a connected iPad and starts it.
#
# The iPad must be connected by cable or on the same network, unlocked, with Developer Mode on.
# Your Apple developer team goes in ios/Local.xcconfig (see ios/Signing.xcconfig).
#
# IPAD         name of the iPad to install on (default: the first connected iPad)
# IPAD_LAUNCH  "no" to leave the app closed after installing, as a scheduled reinstall does
set -eu

cd "$(dirname "$0")/.."

DEVICES="$(mktemp)"
BUILD_LOG="$(mktemp)"
trap 'rm -f "$DEVICES" "$BUILD_LOG"' EXIT
xcrun devicectl list devices --json-output "$DEVICES" >/dev/null

IPAD="${IPAD:-$(/usr/bin/python3 - "$DEVICES" <<'PYTHON'
import json
import sys

devices = json.load(open(sys.argv[1]))["result"]["devices"]
ipads = [
    device["deviceProperties"]["name"] for device in devices
    if device.get("hardwareProperties", {}).get("deviceType") == "iPad"
    and device.get("connectionProperties", {}).get("tunnelState") != "unavailable"
]
print(ipads[0] if ipads else "")
PYTHON
)}"
[ -n "$IPAD" ] || { echo "Installing failed: no iPad is connected." >&2; exit 1; }

BUNDLE_ID="$(xcodebuild -project ios/Pluck.xcodeproj -scheme Pluck-iPad \
    -showBuildSettings 2>/dev/null | sed -n 's/^ *PRODUCT_BUNDLE_IDENTIFIER = //p' | head -n 1)"

echo "Building for ${IPAD}..."
# A failed build must stop here: the app left by an earlier build would install with its old signature.
if ! xcodebuild -project ios/Pluck.xcodeproj -scheme Pluck-iPad \
    -destination 'generic/platform=iOS' -derivedDataPath ios/build -allowProvisioningUpdates build \
    >"$BUILD_LOG" 2>&1; then
    grep -E 'error:' "$BUILD_LOG" >&2 || tail -n 20 "$BUILD_LOG" >&2
    echo "Installing failed: the build failed." >&2
    exit 1
fi
grep -E 'warning: .*[Pp]rovision|BUILD' "$BUILD_LOG" || true

APP="ios/build/Build/Products/Debug-iphoneos/Pluck.app"
[ -d "$APP" ] || { echo "Installing failed: the build did not produce the app." >&2; exit 1; }

xcrun devicectl device install app --device "$IPAD" "$APP" >/dev/null
echo "Installed on $IPAD."
[ "${IPAD_LAUNCH:-yes}" = no ] && exit 0

if LAUNCH="$(xcrun devicectl device process launch --device "$IPAD" "$BUNDLE_ID" 2>&1)"; then
    echo "Started the app."
elif echo "$LAUNCH" | grep -q "not been explicitly trusted"; then
    cat >&2 <<'MESSAGE'
Starting the app failed: the iPad does not trust your developer profile yet.
On the iPad open Settings > General > VPN & Device Management, tap your Apple ID
under Developer App and tap Trust. Then open the app from the Home Screen.
MESSAGE
    exit 1
else
    echo "Starting the app failed:" >&2
    echo "$LAUNCH" | tail -n 5 >&2
    exit 1
fi
