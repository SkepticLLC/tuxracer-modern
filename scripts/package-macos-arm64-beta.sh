#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="${BUILD_DIR:-$ROOT/build}"
DIST_DIR="${DIST_DIR:-$ROOT/dist}"
APP_NAME="Tux Racer Modern"
APP="$DIST_DIR/$APP_NAME.app"
DMG="$DIST_DIR/Tux-Racer-Modern-0.1.9-arm64-beta.dmg"
MACOS="$APP/Contents/MacOS"
RESOURCES="$APP/Contents/Resources"
FRAMEWORKS="$APP/Contents/Frameworks"
VERSION="$(sed -nE 's/^project\(tuxracer-modern VERSION ([0-9.]+).*/\1/p' "$ROOT/CMakeLists.txt")"
BUILD_NUMBER="${BUILD_NUMBER:-19}"
IDENTITY="${DEVELOPER_ID_APPLICATION:-}"
NOTARY_PROFILE="${APPLE_NOTARY_PROFILE:-}"

if [[ "$VERSION" != "0.1.9" ]]; then
  echo "Expected preservation version 0.1.9, found '$VERSION'." >&2
  exit 1
fi

if [[ ! -x "$BUILD_DIR/tuxracer" ]]; then
  echo "Missing $BUILD_DIR/tuxracer. Build the preservation branch first." >&2
  exit 1
fi

ARCHS="$(lipo -archs "$BUILD_DIR/tuxracer" 2>/dev/null || true)"
if [[ "$ARCHS" != *"arm64"* ]]; then
  echo "Release binary is not ARM64: ${ARCHS:-unknown architecture}" >&2
  exit 1
fi

echo "Packaging Tux Racer Modern $VERSION ARM64 beta"
echo "Binary architectures: $ARCHS"

rm -rf "$DIST_DIR"
mkdir -p "$MACOS" "$RESOURCES" "$FRAMEWORKS"

cp "$BUILD_DIR/tuxracer" "$MACOS/tuxracer"
cp -R "$ROOT/data" "$RESOURCES/data"
cp "$ROOT/COPYING" "$RESOURCES/COPYING"
cp "$ROOT/README.md" "$RESOURCES/README.md"
cp "$ROOT/UPSTREAM.md" "$RESOURCES/UPSTREAM.md"

sed \
  -e "s/@TUXRACER_VERSION@/$VERSION/g" \
  -e "s/@TUXRACER_BUILD@/$BUILD_NUMBER/g" \
  "$ROOT/packaging/macos/Info.plist.in" > "$APP/Contents/Info.plist"

xattr -cr "$APP"

SEARCH_DIRS=()
if command -v brew >/dev/null 2>&1; then
  for formula in sdl2 sdl2_mixer tcl-tk; do
    if prefix="$(brew --prefix "$formula" 2>/dev/null)"; then
      SEARCH_DIRS+=("$prefix/lib")
    fi
  done
  BREW_PREFIX="$(brew --prefix)"
  SEARCH_DIRS+=("$BREW_PREFIX/lib" "$BREW_PREFIX/opt")
fi

SEARCH_JOINED=""
for d in "${SEARCH_DIRS[@]}"; do
  [[ -d "$d" ]] || continue
  if [[ -z "$SEARCH_JOINED" ]]; then
    SEARCH_JOINED="$d"
  else
    SEARCH_JOINED="$SEARCH_JOINED;$d"
  fi
done

cmake \
  -DAPP="$APP" \
  -DSEARCH_DIRS="$SEARCH_JOINED" \
  -P "$ROOT/packaging/macos/fixup_bundle.cmake"

FINAL_ARCHS="$(lipo -archs "$MACOS/tuxracer" 2>/dev/null || true)"
if [[ "$FINAL_ARCHS" != *"arm64"* ]]; then
  echo "Packaged binary lost ARM64 architecture: $FINAL_ARCHS" >&2
  exit 1
fi

echo
echo "Packaged runtime dependencies:"
otool -L "$MACOS/tuxracer"

if [[ -n "$IDENTITY" ]]; then
  echo
  echo "Signing with Developer ID identity: $IDENTITY"

  if [[ -d "$FRAMEWORKS" ]]; then
    while IFS= read -r -d '' item; do
      if file "$item" | grep -q "Mach-O"; then
        codesign --force --timestamp --options runtime --sign "$IDENTITY" "$item"
      fi
    done < <(find "$FRAMEWORKS" -type f -print0)
  fi

  codesign --force --timestamp --options runtime --sign "$IDENTITY" "$MACOS/tuxracer"
  codesign --force --timestamp --options runtime --sign "$IDENTITY" "$APP"
else
  echo
  echo "DEVELOPER_ID_APPLICATION is not set; creating an ad-hoc QA build."
  codesign --force --deep --sign - "$APP"
fi

codesign --verify --deep --strict --verbose=2 "$APP"

rm -f "$DMG"
hdiutil create \
  -volname "$APP_NAME $VERSION Beta" \
  -srcfolder "$APP" \
  -ov -format UDZO \
  "$DMG"

if [[ -n "$IDENTITY" ]]; then
  codesign --force --timestamp --sign "$IDENTITY" "$DMG"
fi

if [[ -n "$NOTARY_PROFILE" ]]; then
  if [[ -z "$IDENTITY" ]]; then
    echo "APPLE_NOTARY_PROFILE requires DEVELOPER_ID_APPLICATION." >&2
    exit 1
  fi
  echo
  echo "Submitting DMG for notarization..."
  xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple "$DMG"
  xcrun stapler validate "$DMG"
fi

echo
echo "Validating distributable:"
spctl --assess --type execute --verbose=4 "$APP" || {
  if [[ -n "$IDENTITY" ]]; then
    exit 1
  fi
  echo "Gatekeeper assessment is expected to fail for an ad-hoc QA build."
}

echo
echo "Created:"
echo "  $APP"
echo "  $DMG"
echo
if [[ -z "$IDENTITY" ]]; then
  echo "QA only: set DEVELOPER_ID_APPLICATION for a public beta."
elif [[ -z "$NOTARY_PROFILE" ]]; then
  echo "Signed but not notarized: set APPLE_NOTARY_PROFILE for public distribution."
else
  echo "Developer ID signed and notarized ARM64 beta is ready for distribution."
fi
