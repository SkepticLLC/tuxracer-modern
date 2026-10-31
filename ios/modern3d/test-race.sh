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
animation="${TMPDIR:-/tmp}/tux-modern3d-animation-test-$$"
trap 'rm -f "$binary" "$animation"' EXIT HUP INT TERM
"${CC:-cc}" -std=c99 -Wall -Wextra -Werror \
  "$root/ios/modern3d/character_animation.c" \
  "$root/ios/modern3d/character_animation_test.c" \
  -lm -o "$animation"
"$animation"
inputtest="${TMPDIR:-/tmp}/tux-modern3d-input-test-$$"
trap 'rm -f "$binary" "$animation" "$inputtest"' EXIT HUP INT TERM
"${CC:-cc}" -std=c99 -Wall -Wextra -Werror \
  "$root/ios/modern3d/input_mapping.c" \
  "$root/ios/modern3d/input_mapping_test.c" \
  -lm -o "$inputtest"
"$inputtest"
python3 -m json.tool "$root/ios/modern3d/course.json" >/dev/null
python3 - "$root/ios/modern3d/course.json" <<'PY'
import json,sys
c=json.load(open(sys.argv[1]))
assert c["lengthMeters"]>=1500
assert int(c["lengthMeters"]/c["collectibles"]["spacingMeters"])-2<=64, "fish bitset capacity exceeded"
assert 0<c["slopeDegrees"]<40
print("PASS: long original alpine course and collectible capacity")
PY
echo "PASS: new course JSON syntax"
