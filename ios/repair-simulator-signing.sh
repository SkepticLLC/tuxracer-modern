#!/bin/sh
# Repair/verify the ALREADY COMPILED iOS simulator app without recompiling.
# This intentionally never touches the source checkout.
set -eu
repo_root="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
current="${HOME:?}/Library/Caches/tuxracer-modern-ios/iphonesimulator/Debug-iphonesimulator/TuxRacerModernIOS.app"
previous="$repo_root/build/ios-iphonesimulator/Debug-iphonesimulator/TuxRacerModernIOS.app"
if [ "$#" -gt 0 ]; then
  app="$1"
elif [ -d "$current" ]; then
  app="$current"
else
  app="$previous"
fi
if [ ! -d "$app" ]; then
  echo "No compiled simulator app at: $app" >&2
  echo "Supply the .app path as an argument, or build the iOS simulator target." >&2
  exit 2
fi
if [ "$(uname -s)" != "Darwin" ]; then
  echo "This tool must run on macOS." >&2
  exit 2
fi
printf 'Inspecting existing application: %s\n' "$app"
printf '\nExtended attributes before cleanup:\n'
/usr/bin/xattr -lr "$app" || true
printf '\nClearing app-bundle extended attributes (not source files)...\n'
/usr/bin/xattr -cr "$app"
printf '\nAttempting ad-hoc simulator signing...\n'
/usr/bin/codesign --force --sign - --timestamp=none --generate-entitlement-der "$app"
printf '\nVerifying signature...\n'
/usr/bin/codesign --verify --strict --verbose=2 "$app"
printf '\nExisting simulator app is now signed successfully; no rebuild was needed.\n'
