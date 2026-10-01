#!/bin/bash
# Builds dist/Pluck.app. Pass --install to also copy it into /Applications.
set -euo pipefail
cd "$(dirname "$0")/.."

app="dist/Pluck.app"

swift build --configuration release
binary="$(swift build --configuration release --show-bin-path)/Pluck"

rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$binary" "$app/Contents/MacOS/Pluck"
cp Resources/Info.plist "$app/Contents/Info.plist"
cp Resources/AppIcon.icns "$app/Contents/Resources/AppIcon.icns"
codesign --force --sign - "$app"
echo "Built $app"

if [[ "${1:-}" == "--install" ]]; then
    rm -rf /Applications/Pluck.app
    cp -R "$app" /Applications/Pluck.app
    echo "Installed /Applications/Pluck.app"
fi
