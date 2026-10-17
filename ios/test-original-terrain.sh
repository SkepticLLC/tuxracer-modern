#!/bin/sh
# Fast desktop compiler gate for SGI pixel decoding; no Xcode project required.
set -eu
root="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
binary="${TMPDIR:-/tmp}/tux-original-terrain-test-$$"
trap 'rm -f "$binary"' EXIT HUP INT TERM
"${CC:-cc}" -std=c99 -Wall -Wextra -Werror \
  "$root/ios/original_terrain.c" "$root/ios/original_terrain_test.c" \
  -o "$binary" "$root/data/courses/bunny_hill/elev.rgb" "$root/data/courses/bunny_hill/terrain.rgb"
"$binary"
