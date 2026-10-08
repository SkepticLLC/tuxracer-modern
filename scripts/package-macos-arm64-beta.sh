#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="${BUILD_DIR:-$ROOT/build-release-arm64}"
DIST_DIR="${DIST_DIR:-$ROOT/dist}"
APP_NAME="Tux Racer Modern"
BUNDLE_ID="com.skeptic.tuxracer-modern"
APP="$DIST_DIR/$APP_NAME.app"
MACOS="$APP/Contents/MacOS"
RESOURCES="$APP/Contents/Resources"
ICON_SOURCE="$ROOT/packaging/macos/AppIcon.png"
ICONSET="$DIST_DIR/AppIcon.iconset"
ICON_ICNS="$RESOURCES/AppIcon.icns"
VERSION="$(sed -nE 's/^project\(tuxracer-modern VERSION ([0-9.]+).*/\1/p' "$ROOT/CMakeLists.txt")"
BUILD_NUMBER="${BUILD_NUMBER:-19}"
IDENTITY="${DEVELOPER_ID_APPLICATION:-}"
NOTARY_PROFILE="${APPLE_NOTARY_PROFILE:-}"

if [[ "$VERSION" != "0.1.9" ]]; then
  echo "Expected preservation version 0.1.9, found '$VERSION'." >&2
  exit 1
fi

BIN="$BUILD_DIR/tuxracer"
if [[ ! -x "$BIN" ]]; then
  echo "Missing $BIN." >&2
  echo "Run: ./scripts/build-macos-arm64-release.sh" >&2
  exit 1
fi

ARCHS="$(lipo -archs "$BIN" 2>/dev/null || true)"
if [[ "$ARCHS" != "arm64" ]]; then
  echo "Release binary must be thin ARM64; got: ${ARCHS:-unknown}" >&2
  exit 1
fi

echo "Validating static release binary before packaging..."
DEPS="$(otool -L "$BIN")"
echo "$DEPS"

BAD_DEPS="$(printf '%s\n' "$DEPS" | tail -n +2 | awk '{print $1}' | \
  grep -Ev '^(/System/Library/Frameworks/|/usr/lib/)' || true)"
if [[ -n "$BAD_DEPS" ]]; then
  echo "Refusing to package a binary with non-system dynamic dependencies:" >&2
  echo "$BAD_DEPS" >&2
  echo "Rebuild with ./scripts/build-macos-arm64-release.sh" >&2
  exit 1
fi

if [[ ! -f "$ICON_SOURCE" ]]; then
  echo "Missing macOS icon source: $ICON_SOURCE" >&2
  exit 1
fi

echo "Packaging Tux Racer Modern $VERSION ARM64 preservation beta"

rm -rf "$DIST_DIR"
mkdir -p "$MACOS" "$RESOURCES"

cp "$BIN" "$MACOS/tuxracer"
cp -R "$ROOT/data" "$RESOURCES/data"
cp "$ROOT/COPYING" "$RESOURCES/COPYING"
cp "$ROOT/README.md" "$RESOURCES/README.md"
cp "$ROOT/UPSTREAM.md" "$RESOURCES/UPSTREAM.md"

sed \
  -e "s/@TUXRACER_VERSION@/$VERSION/g" \
  -e "s/@TUXRACER_BUILD@/$BUILD_NUMBER/g" \
  "$ROOT/packaging/macos/Info.plist.in" > "$APP/Contents/Info.plist"

echo "Generating macOS application icon..."
mkdir -p "$ICONSET"
sips -z 16 16     "$ICON_SOURCE" --out "$ICONSET/icon_16x16.png" >/dev/null
sips -z 32 32     "$ICON_SOURCE" --out "$ICONSET/icon_16x16@2x.png" >/dev/null
sips -z 32 32     "$ICON_SOURCE" --out "$ICONSET/icon_32x32.png" >/dev/null
sips -z 64 64     "$ICON_SOURCE" --out "$ICONSET/icon_32x32@2x.png" >/dev/null
sips -z 128 128   "$ICON_SOURCE" --out "$ICONSET/icon_128x128.png" >/dev/null
sips -z 256 256   "$ICON_SOURCE" --out "$ICONSET/icon_128x128@2x.png" >/dev/null
sips -z 256 256   "$ICON_SOURCE" --out "$ICONSET/icon_256x256.png" >/dev/null
sips -z 512 512   "$ICON_SOURCE" --out "$ICONSET/icon_256x256@2x.png" >/dev/null
sips -z 512 512   "$ICON_SOURCE" --out "$ICONSET/icon_512x512.png" >/dev/null
sips -z 1024 1024 "$ICON_SOURCE" --out "$ICONSET/icon_512x512@2x.png" >/dev/null
iconutil -c icns "$ICONSET" -o "$ICON_ICNS"
rm -rf "$ICONSET"

# Signing must be the final mutation of the app.
xattr -cr "$APP"

if [[ -n "$IDENTITY" ]]; then
  echo "Signing app with Developer ID: $IDENTITY"
  codesign --force --timestamp --options runtime --sign "$IDENTITY" "$APP"
else
  echo "Creating ad-hoc signed local QA app."
  codesign --force --sign - "$APP"
fi

codesign --verify --deep --strict --verbose=4 "$APP"

echo
echo "Final app signature:"
codesign -dvvv "$APP" 2>&1

if [[ -n "$NOTARY_PROFILE" ]]; then
  if [[ -z "$IDENTITY" ]]; then
    echo "APPLE_NOTARY_PROFILE requires DEVELOPER_ID_APPLICATION." >&2
    exit 1
  fi

  NOTARY_ZIP="$DIST_DIR/.tux-racer-modern-notarization.zip"
  ditto -c -k --keepParent "$APP" "$NOTARY_ZIP"
  xcrun notarytool submit "$NOTARY_ZIP" --keychain-profile "$NOTARY_PROFILE" --wait
  rm -f "$NOTARY_ZIP"
  xcrun stapler staple "$APP"
  xcrun stapler validate "$APP"
fi

echo
echo "Packaged executable dependencies:"
otool -L "$MACOS/tuxracer"

echo
echo "Created:"
echo "  $APP"
echo
if [[ -z "$IDENTITY" ]]; then
  echo "Local QA build: ad-hoc signed."
elif [[ -z "$NOTARY_PROFILE" ]]; then
  echo "Developer ID signed; notarization still required for public distribution."
else
  echo "Developer ID signed and notarized; ready for public distribution."
fi
