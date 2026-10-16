#!/bin/sh
set -eu
repo_root="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
sdk="${1:-iphonesimulator}"
case "$sdk" in
  iphoneos|iphonesimulator) ;;
  *) echo "Usage: sh ios/build-xcode.sh [iphoneos|iphonesimulator]" >&2; exit 2 ;;
esac
cmake -S "$repo_root/ios" -B "$repo_root/build/ios-$sdk" -G Xcode \
  -DCMAKE_SYSTEM_NAME=iOS -DCMAKE_OSX_SYSROOT="$sdk" \
  -DCMAKE_OSX_DEPLOYMENT_TARGET=15.0
echo "Open $repo_root/build/ios-$sdk/TuxRacerModernIOS.xcodeproj"
