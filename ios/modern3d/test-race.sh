#!/bin/sh
# Host-only clean-slate game regression gate; no iOS rebuild required.
set -eu
root="$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)"
binary="${TMPDIR:-/tmp}/tux-modern3d-race-test-$$"
trap 'rm -f "$binary"' EXIT HUP INT TERM
"${CC:-cc}" -std=c99 -Wall -Wextra -Werror \
  "$root/ios/modern3d/race_system.c" \
  "$root/ios/modern3d/race_system_test.c" \
  -lm -o "$binary"
"$binary"
python3 -m json.tool "$root/ios/modern3d/course.json" >/dev/null
echo "PASS: new course JSON syntax"
