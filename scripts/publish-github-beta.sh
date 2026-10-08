#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
REPO="SkepticLLC/tuxracer-modern"
TARGET_BRANCH="release/0.1.9-arm64-beta"
TAG="v0.1.9-beta.1"
TITLE="Tux Racer Modern 0.1.9 — Apple Silicon Preservation Beta 1"
NOTES="$ROOT/docs/RELEASE_NOTES_0.1.9-beta.1.md"
ZIP="$ROOT/dist/Tux-Racer-Modern-0.1.9-beta.1-arm64.zip"
CHECKSUM="$ROOT/dist/Tux-Racer-Modern-0.1.9-beta.1-arm64.sha256"

if ! command -v gh >/dev/null 2>&1; then
    echo "GitHub CLI (gh) is required." >&2
    echo "Install it with: brew install gh" >&2
    exit 1
fi

if [[ ! -f "$ZIP" ]]; then
    echo "Missing notarized release ZIP:" >&2
    echo "  $ZIP" >&2
    echo "Run ./scripts/package-macos-arm64-beta.sh first." >&2
    exit 1
fi

if [[ ! -f "$NOTES" ]]; then
    echo "Missing release notes: $NOTES" >&2
    exit 1
fi

if ! gh auth status --hostname github.com >/dev/null 2>&1; then
    echo "GitHub CLI is not authenticated." >&2
    echo "Run: gh auth login --hostname github.com --git-protocol ssh --web" >&2
    exit 1
fi

echo "Generating SHA-256 checksum..."
shasum -a 256 "$ZIP" > "$CHECKSUM"
cat "$CHECKSUM"

if gh release view "$TAG" --repo "$REPO" >/dev/null 2>&1; then
    echo "Release $TAG already exists; refusing to publish a duplicate." >&2
    gh release view "$TAG" --repo "$REPO" --web
    exit 1
fi

echo
echo "Publishing GitHub prerelease:"
echo "  Repository: $REPO"
echo "  Target:     $TARGET_BRANCH"
echo "  Tag:        $TAG"
echo "  ZIP:        $(basename "$ZIP")"
echo

gh release create "$TAG"     --repo "$REPO"     --target "$TARGET_BRANCH"     --title "$TITLE"     --notes-file "$NOTES"     --prerelease     "$ZIP#Tux Racer Modern 0.1.9 Beta 1 — macOS Apple Silicon ARM64"     "$CHECKSUM#SHA-256 checksum"

echo
echo "Published successfully:"
gh release view "$TAG" --repo "$REPO" --json url --jq '.url'
