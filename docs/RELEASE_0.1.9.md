# Tux Racer Modern v0.1.9 — ARM64 Preservation Beta

This branch packages the preservation port from `develop` without pulling in the Modern renderer/UI work.

## Release architecture

The public macOS preservation build intentionally does **not** use Homebrew SDL runtime libraries.

The release build fetches and verifies these official upstream sources:

- SDL 2.32.10 — SHA-256 `5f5993c530f084535c65a6879e9b26ad441169b3e25d789d83287040a9ca5165`
- SDL2_mixer 2.8.2 — SHA-256 `938dff531d00ace2296557a6599abe6f34599e2f34f0a4a08a397e2ccac8b8f7`

Both are linked statically. SDL2_mixer is reduced to the formats used by the preserved Tux Racer data: WAV sound effects and IT/MOD-family tracker music through vendored libxmp.

This avoids sdl2-compat, SDL3, Homebrew runtime dylibs, and post-build Mach-O relocation.

## Build

```sh
git checkout release/0.1.9-arm64-beta
./scripts/build-macos-arm64-release.sh
```

The script creates a clean `build-release-arm64` directory and refuses to succeed if the final `tuxracer` executable has any non-system dynamic library dependency.

## Package — local QA

```sh
./scripts/package-macos-arm64-beta.sh
```

This creates:

```text
dist/Tux Racer Modern.app
```

No DMG is produced.

With no signing identity configured, the app receives an ad-hoc signature for local QA.

## Developer ID public beta

Find the signing identity:

```sh
security find-identity -v -p codesigning
```

Then:

```sh
export DEVELOPER_ID_APPLICATION='Developer ID Application: YOUR NAME (TEAMID)'
./scripts/package-macos-arm64-beta.sh
```

For notarization, create a keychain profile once:

```sh
xcrun notarytool store-credentials "tuxracer-modern-notary"
```

Then:

```sh
export DEVELOPER_ID_APPLICATION='Developer ID Application: YOUR NAME (TEAMID)'
export APPLE_NOTARY_PROFILE='tuxracer-modern-notary'
./scripts/package-macos-arm64-beta.sh
```

A temporary ZIP is used only to submit the app to Apple's notarization service and is removed afterward.

## Clean-machine beta checklist

1. Test the app on an Apple Silicon Mac without Homebrew SDL packages.
2. Launch through Finder with Gatekeeper enabled.
3. Verify menu navigation.
4. Verify WAV sound effects.
5. Verify IT tracker music.
6. Verify Practice and Event races.
7. Verify fullscreen and return to windowed mode.
8. Quit and relaunch; verify preferences/data paths.
9. Verify the final app with:
   `codesign --verify --deep --strict --verbose=4 "Tux Racer Modern.app"`

## GitHub prerelease

After validation:

- tag: `v0.1.9-beta.1`
- title: `Tux Racer Modern 0.1.9 — Apple Silicon Preservation Beta 1`
- mark as prerelease
- publish the signed/notarized app archive and SHA-256 checksum
- retain original authorship and GPLv2 notices
- publish source for the exact tagged revision

## Mac App Store / TestFlight follow-up

The App Store build is a separate distribution track with App Sandbox and App Store signing requirements.

Because the preservation code derives from GPLv2-licensed Tux Racer, complete a focused licensing review before Mac App Store submission.
