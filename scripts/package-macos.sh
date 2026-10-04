#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="${BUILD_DIR:-$ROOT/build}"
APP_NAME="Tux Racer Modern"
APP="$BUILD_DIR/$APP_NAME.app"
MACOS="$APP/Contents/MacOS"
RESOURCES="$APP/Contents/Resources"
VERSION="$(sed -nE 's/^project\(tuxracer-modern VERSION ([0-9.]+).*/\1/p' "$ROOT/CMakeLists.txt")"

if [[ ! -x "$BUILD_DIR/tuxracer" ]]; then
  echo "Missing $BUILD_DIR/tuxracer. Build the project first." >&2
  exit 1
fi

rm -rf "$APP"
mkdir -p "$MACOS" "$RESOURCES"

cp "$BUILD_DIR/tuxracer" "$MACOS/tuxracer"
cp -R "$ROOT/data" "$RESOURCES/data"
cp "$ROOT/COPYING" "$RESOURCES/COPYING"
cp "$ROOT/README.md" "$RESOURCES/README.md"

sed "s/@TUXRACER_VERSION@/$VERSION/g"   "$ROOT/packaging/macos/Info.plist.in" > "$APP/Contents/Info.plist"

# Finder/resource-fork extended attributes can be inherited while copying
# historical assets. They are not valid inside a signed application bundle.
xattr -cr "$APP"

# Ad-hoc signing makes the local development bundle internally consistent.
codesign --force --deep --sign - "$APP"
codesign --verify --deep --strict --verbose=2 "$APP"

echo "Created: $APP"
echo "Launch with: open \"$APP\""
