#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="${BUILD_DIR:-$ROOT/build-release-arm64}"

if [[ "$(uname -m)" != "arm64" ]]; then
  echo "This release build must run on Apple Silicon (arm64)." >&2
  exit 1
fi

if ! command -v cmake >/dev/null 2>&1; then
  if command -v brew >/dev/null 2>&1; then
    brew install cmake
  else
    echo "CMake is required." >&2
    exit 1
  fi
fi

rm -rf "$BUILD_DIR"

cmake -S "$ROOT" -B "$BUILD_DIR" \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_OSX_ARCHITECTURES=arm64 \
  -DTUXRACER_BUNDLED_SDL2=ON \
  -DTUXRACER_WARNINGS=ON

cmake --build "$BUILD_DIR" --parallel

BIN="$BUILD_DIR/tuxracer"
if [[ ! -x "$BIN" ]]; then
  echo "Release build did not produce $BIN" >&2
  exit 1
fi

ARCHS="$(lipo -archs "$BIN" 2>/dev/null || true)"
if [[ "$ARCHS" != "arm64" ]]; then
  echo "Expected a thin arm64 release binary; got: ${ARCHS:-unknown}" >&2
  exit 1
fi

echo
echo "Release binary dependencies:"
otool -L "$BIN"

BAD_DEPS="$(otool -L "$BIN" | tail -n +2 | awk '{print $1}' | \
  grep -Ev '^(/System/Library/Frameworks/|/usr/lib/)' || true)"

if [[ -n "$BAD_DEPS" ]]; then
  echo >&2
  echo "Release binary has non-system dynamic dependencies:" >&2
  echo "$BAD_DEPS" >&2
  echo "The preservation release must be self-contained." >&2
  exit 1
fi

echo
echo "Classic SDL2/SDL2_mixer static ARM64 release build is ready:"
echo "  $BIN"
