# Tux Racer Modern 0.1.9 — Apple Silicon Preservation Beta 1

Tux Racer is back on modern macOS.

This is the first public **Tux Racer Modern preservation beta**: a preservation-first port of the original Tux Racer 0.61 experience to current Apple Silicon Macs.

The goal of the 0.1.x line is deliberately conservative: preserve the original gameplay, physics, courses, data, music, sounds, authorship, and character of Tux Racer while making the game practical to run on modern systems.

## Download

**macOS Apple Silicon (ARM64)**

Download:

`Tux-Racer-Modern-0.1.9-beta.1-arm64.zip`

Extract the ZIP and launch **Tux Racer Modern.app**.

The public build is Developer ID signed, uses Apple's hardened runtime, and is notarized for distribution outside the Mac App Store.

## What's in Beta 1

- Native **Apple Silicon ARM64** build.
- Modern macOS application bundle.
- Retina / HiDPI support.
- Windowed and fullscreen play.
- SDL2-based modern platform/input/audio layer.
- Original Tux Racer courses and gameplay preserved.
- Original music and sound effects preserved.
- Self-contained release build with classic SDL2 and SDL2_mixer linked statically.
- No Homebrew, SDL3, or other third-party runtime installation required.
- Dedicated macOS application icon.
- Developer ID signing, hardened runtime, notarization, and stapling for public distribution.

## Preservation

Tux Racer Modern is based on the original **Tux Racer 0.61** source and data.

The preservation release intentionally retains the original game's:

- physics and gameplay behavior
- courses
- race structure
- graphics and visual style
- music and sound
- original credits and authorship

The larger Tux Racer Modern project will continue beyond preservation with modern rendering and presentation work, but this release exists as a stable, faithful modern baseline.

## System requirements

- macOS 13 or later
- Apple Silicon Mac (ARM64)

This Beta 1 build is **not** a Universal Binary and does not include Intel x86_64.

## Known limitations

- This beta is currently macOS Apple Silicon only.
- Linux and Windows validation are planned separately.
- This is the preservation renderer and UI, not the in-development modern visual overhaul.
- As a beta release, additional clean-machine testing and compatibility feedback are welcome.

## Source and licensing

Tux Racer Modern remains open source.

Original Tux Racer was created by **Jasmin F. Patry** with its original contributors. Original copyright and contributor notices are retained.

The imported original Tux Racer source is distributed under the **GNU General Public License version 2** terms included with the project.

Modern port stewardship and modernization work are maintained by **Brian Clark / Skeptic**.

See `COPYING`, `UPSTREAM.md`, and `docs/PRESERVATION.md` in the repository for details.

## Upstream preservation baseline

The project records the original upstream archives used for preservation:

- `tuxracer-0.61.tar.gz`
  - SHA-256: `a311d09080598fe556134d4b9faed7dc0c2ed956ebb10d062e5d4df022f91eff`
- `tuxracer-data-0.61.tar.gz`
  - SHA-256: `3783d204b7bb1ed16aa5e5a1d5944de10fbee05bc7cebb8f616fce84301f3651`

## Feedback

If you run into a problem, please open a GitHub issue and include:

- Mac model
- macOS version
- what you were doing when the issue occurred
- crash report or terminal output when available

Have fun on the mountain. 🐧
