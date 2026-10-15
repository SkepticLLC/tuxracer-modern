#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
output="${TMPDIR:-/tmp}/tux-mobile-input-test-$$"
trap 'rm -f "$output"' EXIT HUP INT TERM
"${CC:-cc}" -std=c99 -Wall -Wextra -Werror -pedantic src/platform/mobile_input.c tests/mobile_input_test.c -o "$output"
"$output"
printf 'mobile input tests passed\n'
