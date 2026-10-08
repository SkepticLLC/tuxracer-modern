#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="${BUILD_DIR:-$ROOT/build}"
DIST_DIR="${DIST_DIR:-$ROOT/dist}"
APP_NAME="Tux Racer Modern"
APP="$DIST_DIR/$APP_NAME.app"
MACOS="$APP/Contents/MacOS"
RESOURCES="$APP/Contents/Resources"
FRAMEWORKS="$APP/Contents/Frameworks"
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

if [[ ! -f "$ICON_SOURCE" ]]; then
  echo "Missing macOS icon source: $ICON_SOURCE" >&2
  exit 1
fi

echo "Generating macOS application icon..."
rm -rf "$ICONSET"
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

xattr -cr "$APP"

SEARCH_DIRS=()
SDL3_DYLIB=""

if command -v brew >/dev/null 2>&1; then
  for formula in sdl2 sdl2_mixer sdl3 tcl-tk; do
    if prefix="$(brew --prefix "$formula" 2>/dev/null)"; then
      SEARCH_DIRS+=("$prefix/lib")

      if [[ "$formula" == "sdl3" && -f "$prefix/lib/libSDL3.dylib" ]]; then
        SDL3_DYLIB="$(python3 -c 'import os,sys; print(os.path.realpath(sys.argv[1]))' "$prefix/lib/libSDL3.dylib")"
      fi
    fi
  done
  BREW_PREFIX="$(brew --prefix)"
  SEARCH_DIRS+=("$BREW_PREFIX/lib" "$BREW_PREFIX/opt")
fi

if [[ -z "$SDL3_DYLIB" || ! -f "$SDL3_DYLIB" ]]; then
  echo "Could not locate Homebrew SDL3 runtime (libSDL3.dylib)." >&2
  echo "The current Homebrew SDL2 package is sdl2-compat and requires SDL3 at runtime." >&2
  echo "Install it with: brew install sdl3" >&2
  exit 1
fi

echo "SDL3 runtime: $SDL3_DYLIB"

# BundleUtilities only fixes explicit libraries that already live inside the
# application bundle. Copy SDL3 into Contents/Frameworks first, then hand
# that bundled path to fixup_bundle so its install name/dependencies are
# rewritten consistently with the rest of the app.
SDL3_BASENAME="$(basename "$SDL3_DYLIB")"
SDL3_BUNDLED_PATH="$FRAMEWORKS/$SDL3_BASENAME"
cp "$SDL3_DYLIB" "$SDL3_BUNDLED_PATH"

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
  -DEXTRA_LIBS="$SDL3_BUNDLED_PATH" \
  -P "$ROOT/packaging/macos/fixup_bundle.cmake"

# sdl2-compat intentionally dlopen()s "libSDL3.dylib" at runtime. BundleUtilities
# may preserve SDL3's versioned filename, so provide the exact unversioned name
# beside SDL2 in Contents/Frameworks where @loader_path resolves it.
if [[ ! -e "$FRAMEWORKS/libSDL3.dylib" ]]; then
  if [[ ! -f "$SDL3_BUNDLED_PATH" ]]; then
    echo "SDL3 is missing from Contents/Frameworks after bundle fixup." >&2
    exit 1
  fi
  ln -s "$SDL3_BASENAME" "$FRAMEWORKS/libSDL3.dylib"
fi

echo
echo "Bundled SDL3 runtime:"
ls -l "$FRAMEWORKS"/libSDL3*.dylib
otool -L "$FRAMEWORKS/libSDL3.dylib"

echo
echo "Auditing packaged Mach-O files for Homebrew paths..."
HOMEBREW_PATH_FOUND=0
while IFS= read -r -d '' item; do
  if file "$item" | grep -q "Mach-O"; then
    if otool -L "$item" | grep -q "/opt/homebrew"; then
      echo "Homebrew dependency remains in: $item" >&2
      otool -L "$item" | grep "/opt/homebrew" >&2 || true
      HOMEBREW_PATH_FOUND=1
    fi
  fi
done < <(find "$MACOS" "$FRAMEWORKS" -type f -print0)

if [[ "$HOMEBREW_PATH_FOUND" -ne 0 ]]; then
  echo "Packaging aborted: one or more Homebrew runtime paths remain." >&2
  exit 1
fi

FINAL_ARCHS="$(lipo -archs "$MACOS/tuxracer" 2>/dev/null || true)"
if [[ "$FINAL_ARCHS" != *"arm64"* ]]; then
  echo "Packaged binary lost ARM64 architecture: $FINAL_ARCHS" >&2
  exit 1
fi

echo
echo "Packaged runtime dependencies:"
otool -L "$MACOS/tuxracer"

# BundleUtilities copies Homebrew dylibs after the initial xattr scrub.
# Some formulae carry Finder/resource-fork metadata that codesign rejects.
# Scrub the completed bundle immediately before signing.
xattr -cr "$APP"

# Sanity check: no extended attributes should remain anywhere in the bundle.
if xattr -lr "$APP" 2>/dev/null | grep -q .; then
  echo "Extended attributes remain in the completed app bundle:" >&2
  xattr -lr "$APP" >&2 || true
  exit 1
fi

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

if [[ -n "$NOTARY_PROFILE" ]]; then
  if [[ -z "$IDENTITY" ]]; then
    echo "APPLE_NOTARY_PROFILE requires DEVELOPER_ID_APPLICATION." >&2
    exit 1
  fi

  NOTARY_ZIP="$DIST_DIR/.tux-racer-modern-notarization.zip"
  rm -f "$NOTARY_ZIP"

  echo
  echo "Preparing temporary notarization archive..."
  ditto -c -k --keepParent "$APP" "$NOTARY_ZIP"

  echo "Submitting app for notarization..."
  xcrun notarytool submit "$NOTARY_ZIP" --keychain-profile "$NOTARY_PROFILE" --wait
  rm -f "$NOTARY_ZIP"

  xcrun stapler staple "$APP"
  xcrun stapler validate "$APP"
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
echo
if [[ -z "$IDENTITY" ]]; then
  echo "QA only: set DEVELOPER_ID_APPLICATION for a public beta."
elif [[ -z "$NOTARY_PROFILE" ]]; then
  echo "Signed but not notarized: set APPLE_NOTARY_PROFILE for public distribution."
else
  echo "Developer ID signed and notarized ARM64 app is ready for distribution."
fi
