#!/bin/sh
set -eu
root="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
binary="${TMPDIR:-/tmp}/tux-original-course-test-$$"
trap 'rm -f "$binary"' EXIT HUP INT TERM
"${CC:-cc}" -std=c99 -Wall -Wextra -Werror \
  "$root/ios/original_course.c" "$root/ios/original_course_test.c" \
  -o "$binary"
"$binary" "$root/data/courses/bunny_hill/course.tcl"
