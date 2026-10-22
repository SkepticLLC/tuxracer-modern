#!/bin/sh
# Verify the three binary images from the downloadable branding asset pack
# are present before running CMake / Xcode.
set -eu
root="$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)"
catalog="$root/ios/modern3d/Assets.xcassets"
icon="$catalog/AppIcon.appiconset/AppIcon.png"
landscape="$catalog/SplashLandscape.imageset/SplashLandscape.png"
portrait="$catalog/SplashPortrait.imageset/SplashPortrait.png"
for file in "$icon" "$landscape" "$portrait"; do
  if [ ! -s "$file" ]; then
    echo "MISSING image: $file" >&2
    echo "Extract the Tux Racer branding asset ZIP at the repository root." >&2
    exit 1
  fi
  /usr/bin/sips -g pixelWidth -g pixelHeight "$file"
done
for file in \
  "$catalog/Contents.json" \
  "$catalog/AppIcon.appiconset/Contents.json" \
  "$catalog/SplashLandscape.imageset/Contents.json" \
  "$catalog/SplashPortrait.imageset/Contents.json"; do
    python3 -m json.tool "$file" >/dev/null
done
icon_width=$(/usr/bin/sips -g pixelWidth "$icon" | awk '/pixelWidth:/{print $2}')
icon_height=$(/usr/bin/sips -g pixelHeight "$icon" | awk '/pixelHeight:/{print $2}')
if [ "$icon_width" != "1024" ] || [ "$icon_height" != "1024" ]; then
  echo "INVALID app icon size: expected 1024x1024" >&2
  exit 1
fi
/usr/bin/plutil -lint "$root/ios/Info.plist"
echo "PASS: Tux Racer app icon + landscape/portrait art + catalog definitions"
