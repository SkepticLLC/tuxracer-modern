#!/bin/sh
# Verify original Tux Racer assets really ended up in the signed simulator app.
# No build or modification is performed.
set -eu
app="${1:-${HOME:?}/Library/Caches/tuxracer-modern-ios/iphonesimulator/Debug-iphonesimulator/TuxRacerModernIOS.app}"
if [ ! -d "$app" ]; then
  echo "FAIL: compiled app not found: $app" >&2
  exit 2
fi
echo "Inspecting app bundle: $app"
if [ -f "$app/data/courses/bunny_hill/course.tcl" ]; then
  root="$app/data"
elif [ -f "$app/Contents/Resources/data/courses/bunny_hill/course.tcl" ]; then
  root="$app/Contents/Resources/data"
else
  echo "FAIL: original Bunny Hill course.tcl absent from application resources." >&2
  echo "Available top-level bundle entries:" >&2
  ls -la "$app" >&2
  exit 1
fi
for rel in \
  courses/bunny_hill/course.tcl \
  courses/bunny_hill/elev.rgb \
  courses/bunny_hill/terrain.rgb \
  courses/course_idx.tcl \
  tuxracer_init.tcl; do
  if [ ! -s "$root/$rel" ]; then
    echo "FAIL: missing or empty resource: $root/$rel" >&2
    exit 1
  fi
  echo "PASS: $rel"
done
repo_root="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
for name in elev.rgb terrain.rgb; do
  source_file="$repo_root/data/courses/bunny_hill/$name"
  bundle_file="$root/courses/bunny_hill/$name"
  echo "Comparing $name (repository vs signed bundle):"
  /usr/bin/shasum -a 256 "$source_file" "$bundle_file"
  if ! /usr/bin/cmp -s "$source_file" "$bundle_file"; then
    echo "FAIL: $name has different bytes inside app than in repository" >&2
    exit 1
  fi
  echo "PASS: original $name byte-for-byte identical in app"
done
echo "Original course resources are present in: $root"
