#!/bin/sh
# Invoked by CMake's PRE_LINK phase, before Xcode signs the app.
set -eu
bundle="${1:-}"
if [ -z "$bundle" ]; then
  echo "prepare-signing: expected .app bundle path" >&2
  exit 2
fi
if [ ! -d "$bundle" ]; then
  echo "prepare-signing: bundle not present yet ($bundle)" >&2
  exit 0
fi
if [ "$(uname -s)" != "Darwin" ]; then
  echo "prepare-signing: macOS-only step" >&2
  exit 0
fi
# Apple QA1940: clear FinderInfo, ResourceFork and related metadata from
# the *build product*, never from the user's source checkout.
/usr/bin/xattr -cr "$bundle"
printf 'prepare-signing: cleared bundle extended attributes from %s\n' "$bundle"
