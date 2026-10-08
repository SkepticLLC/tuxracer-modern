#!/usr/bin/env bash
set -euo pipefail

# Never copy Finder metadata/resource forks into the distributable app.
export COPYFILE_DISABLE=1

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

cp -X "$BIN" "$MACOS/tuxracer"
cp -RX "$ROOT/data" "$RESOURCES/data"
cp -X "$ROOT/COPYING" "$RESOURCES/COPYING"
cp -X "$ROOT/README.md" "$RESOURCES/README.md"
cp -X "$ROOT/UPSTREAM.md" "$RESOURCES/UPSTREAM.md"

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
#
# First remove any prior bundle signature and the linker's automatic
# ad-hoc signature from the copied ARM64 executable.
rm -rf "$APP/Contents/_CodeSignature"
codesign --remove-signature "$MACOS/tuxracer" 2>/dev/null || true

# Historical assets and locally-created icon files can carry FinderInfo,
# resource forks, quarantine bits, AppleDouble files, or .DS_Store entries.
# Clean these only AFTER all other bundle mutations, immediately before signing.
find "$APP" -name '._*' -delete
find "$APP" -name '.DS_Store' -delete
dot_clean -m "$APP" >/dev/null 2>&1 || true

# xattr -cr is normally sufficient, but explicitly remove the two attributes
# codesign rejects on every bundle path as a defense against Finder metadata
# being attached to the outer .app directory itself.
while IFS= read -r -d '' item; do
  xattr -d com.apple.FinderInfo "$item" 2>/dev/null || true
  xattr -d com.apple.ResourceFork "$item" 2>/dev/null || true
  xattr -d com.apple.quarantine "$item" 2>/dev/null || true
done < <(find "$APP" -print0)

xattr -cr "$APP"

echo "Pre-sign executable state:"
codesign -dvv "$MACOS/tuxracer" 2>&1 || true

echo "Pre-sign extended attributes:"
if xattr -lr "$APP" 2>/dev/null | grep -q .; then
  xattr -lr "$APP" >&2 || true
  echo "Extended attributes remain in app bundle after cleanup." >&2
  exit 1
else
  echo "  none"
fi

if [[ -n "$IDENTITY" ]]; then
  echo "Signing app with Developer ID: $IDENTITY"
  codesign --force --timestamp --options runtime --sign "$IDENTITY" "$APP"
else
  echo "Creating sealed ad-hoc local QA app."
  codesign --force --deep --sign - "$APP"
fi

if [[ ! -f "$APP/Contents/_CodeSignature/CodeResources" ]]; then
  echo "Signing failed to create Contents/_CodeSignature/CodeResources." >&2
  exit 1
fi

codesign --verify --deep --strict --verbose=4 "$APP"

echo
echo "Final app signature:"
SIGNING_INFO="$(codesign -dvvv "$APP" 2>&1)"
echo "$SIGNING_INFO"

if ! grep -q "Sealed Resources" <<<"$SIGNING_INFO"; then
  echo "App signature does not report a sealed resource envelope." >&2
  exit 1
fi

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
