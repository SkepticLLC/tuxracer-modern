# Tux Racer Modern v0.1.9 — ARM64 Preservation Beta

This branch packages the preservation port from `develop` without pulling in the Modern renderer/UI work.

## Release intent

v0.1.9 is the public preservation beta: original Tux Racer gameplay, physics, courses, data, and credits retained; native modern macOS build; Apple Silicon ARM64; Retina / HiDPI; fullscreen and windowed play; SDL2 input/audio modernization; self-contained macOS application bundle.

## Build

```sh
git checkout release/0.1.9-arm64-beta
./scripts/bootstrap-macos.sh
lipo -archs build/tuxracer
```

The public ARM64 beta must include `arm64`.

## Package — local QA

```sh
chmod +x scripts/package-macos-arm64-beta.sh
./scripts/package-macos-arm64-beta.sh
```

This creates `dist/Tux Racer Modern.app` and `dist/Tux-Racer-Modern-0.1.9-arm64-beta.dmg`.

## Package — Developer ID public beta

Find the exact identity with:

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

Then package with:

```sh
export DEVELOPER_ID_APPLICATION='Developer ID Application: YOUR NAME (TEAMID)'
export APPLE_NOTARY_PROFILE='tuxracer-modern-notary'
./scripts/package-macos-arm64-beta.sh
```

## Clean-machine beta checklist

1. Test the packaged app on a Mac without the development Homebrew packages installed.
2. Copy the app to Applications and launch through Finder with Gatekeeper enabled.
3. Verify menu navigation, audio, Practice and Event races.
4. Verify fullscreen and return to windowed mode.
5. Quit and relaunch; verify preferences/data paths remain valid.
6. Verify signatures with `codesign --verify --deep --strict --verbose=2`.
7. Verify Gatekeeper with `spctl --assess --type execute --verbose=4`.

## GitHub prerelease

After validation:

- tag: `v0.1.9-beta.1`
- title: `Tux Racer Modern 0.1.9 — Apple Silicon Preservation Beta 1`
- mark as prerelease
- publish the signed/notarized app archive used for distribution and its SHA-256 checksum
- retain original authorship and GPLv2 notices
- publish source for the exact tagged revision

## Mac App Store / TestFlight follow-up

Do not reuse the Developer ID package as an App Store package. The App Store track requires a separate distribution configuration including App Sandbox and App Store signing. TestFlight should be the first validation path for that build.

Because the preservation code derives from GPLv2-licensed Tux Racer, complete a focused licensing review before Mac App Store submission.
