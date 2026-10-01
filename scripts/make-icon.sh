#!/bin/bash
# Regenerates Resources/AppIcon.icns from scripts/make-icon.swift.
set -euo pipefail
cd "$(dirname "$0")/.."

work="tmp/icon"
iconset="$work/AppIcon.iconset"
rm -rf "$work"
mkdir -p "$iconset"

swift scripts/make-icon.swift "$work/icon-1024.png"

for size in 16 32 128 256 512; do
    sips -z "$size" "$size" "$work/icon-1024.png" --out "$iconset/icon_${size}x${size}.png" >/dev/null
    double=$((size * 2))
    sips -z "$double" "$double" "$work/icon-1024.png" --out "$iconset/icon_${size}x${size}@2x.png" >/dev/null
done

iconutil --convert icns --output Resources/AppIcon.icns "$iconset"
cp "$work/icon-1024.png" Resources/AppIcon.png
rm -rf "$work"
echo "Wrote Resources/AppIcon.icns"
