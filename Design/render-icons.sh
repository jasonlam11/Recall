#!/bin/bash
# Renders the icon SVGs into Assets.xcassets/AppIcon.appiconset.
#
# Uses qlmanage for rasterisation, which is already on every Mac — not worth a
# Homebrew dependency for three files.
set -euo pipefail
cd "$(dirname "$0")"
OUT=../Recall/Assets.xcassets/AppIcon.appiconset
WORK=$(mktemp -d)

for f in icon-mac icon-ios icon-ios-dark; do
  qlmanage -t -s 1024 -o "$WORK" "$f.svg" >/dev/null 2>&1
  mv "$WORK/$f.svg.png" "$WORK/$f-1024.png"
done

# macOS needs every size present; Xcode does not upscale.
for spec in "16:icon_16" "32:icon_16@2x" "32:icon_32" "64:icon_32@2x" \
            "128:icon_128" "256:icon_128@2x" "256:icon_256" "512:icon_256@2x" \
            "512:icon_512" "1024:icon_512@2x"; do
  sips -s format png -z "${spec%%:*}" "${spec%%:*}" \
       "$WORK/icon-mac-1024.png" --out "$OUT/${spec##*:}.png" >/dev/null
done

cp "$WORK/icon-ios-1024.png"      "$OUT/icon_ios_1024.png"
cp "$WORK/icon-ios-dark-1024.png" "$OUT/icon_ios_1024_dark.png"
rm -rf "$WORK"
echo "rendered $(ls "$OUT"/*.png | wc -l | tr -d ' ') PNGs"
