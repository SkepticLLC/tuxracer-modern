#!/bin/sh
set -eu
repo_root="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
sdk="${1:-iphonesimulator}"
case "$sdk" in
  iphoneos|iphonesimulator) ;;
  *) echo "Usage: sh ios/build-xcode.sh [iphoneos|iphonesimulator]" >&2; exit 2 ;;
esac

# Keep compiled app bundles outside Finder/iCloud-managed Desktop checkouts.
# macOS metadata carried into .app bundles will prevent code signing.
build_root="${TUXRACER_IOS_BUILD_ROOT:-${HOME:?}/Library/Caches/tuxracer-modern-ios}"
build_dir="$build_root/$sdk"
cmake -S "$repo_root/ios" -B "$build_dir" -G Xcode \
  -DCMAKE_SYSTEM_NAME=iOS -DCMAKE_OSX_SYSROOT="$sdk" \
  -DCMAKE_OSX_DEPLOYMENT_TARGET=26.0
printf '\nXcode project: %s/TuxRacerModernIOS.xcodeproj\n' "$build_dir"
printf 'Open with:\n  open "%s/TuxRacerModernIOS.xcodeproj"\n' "$build_dir"
