#!/bin/sh
set -eu
root="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
binary="${TMPDIR:-/tmp}/tux-course-paths-test-$$"
trap 'rm -f "$binary"' EXIT HUP INT TERM
"${CC:-cc}" -std=c99 -Wall -Wextra -Werror \
    "$root/ios/course_asset_paths.c" "$root/ios/course_asset_paths_test.c" \
    -o "$binary"
"$binary"
