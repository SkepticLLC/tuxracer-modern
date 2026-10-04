#!/usr/bin/env bash
set -euo pipefail
if ! command -v brew >/dev/null 2>&1; then
  echo "Homebrew is required. Install it from https://brew.sh and rerun." >&2
  exit 1
fi
brew install cmake sdl2 sdl2_mixer tcl-tk
TCL_PREFIX="$(brew --prefix tcl-tk)"
SDL2_PREFIX="$(brew --prefix sdl2)"
SDL2_MIXER_PREFIX="$(brew --prefix sdl2_mixer)"
cmake -S . -B build -DCMAKE_BUILD_TYPE=RelWithDebInfo \
  -DCMAKE_PREFIX_PATH="${SDL2_PREFIX};${SDL2_MIXER_PREFIX};${TCL_PREFIX}"
cmake --build build --parallel
printf '\nBuild complete. Run: ./build/tuxracer\n'
