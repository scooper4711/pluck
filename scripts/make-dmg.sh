#!/bin/sh
# Packages the built app into dist/Pluck-<VERSION>.dmg.
set -eu

cd "$(dirname "$0")/.."

VERSION="${VERSION:-0.0.0}"
APP="dist/Pluck.app"
STAGING="dist/dmg"
DMG="dist/Pluck-$VERSION.dmg"

[ -d "$APP" ] || { echo "Making the disk image failed: $APP has not been built." >&2; exit 1; }

rm -rf "$STAGING" "$DMG"
mkdir -p "$STAGING"
cp -R "$APP" "$STAGING/"
ln -s /Applications "$STAGING/Applications"
hdiutil create -volname "Pluck" -srcfolder "$STAGING" -ov -format UDZO "$DMG" >/dev/null
rm -rf "$STAGING"
echo "Built $DMG"
