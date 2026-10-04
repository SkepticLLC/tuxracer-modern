# Tux Racer Modern

**A preservation-first modernization and continuation of the original Tux Racer.**

**Modern Port Maintainer:** Brian Clark (Skeptic) `<jbrianclark@icloud.com>`  
**Original Tux Racer Author:** Jasmin F. Patry `<jfpatry@sunspirestudios.com>`

Tux Racer Modern brings the original Tux Racer 0.61 codebase to current macOS, Linux, and Windows systems while preserving the gameplay, physics, courses, data, authorship, and open-source heritage of the original project.

The project begins with preservation: make the original game work correctly on modern hardware. From that stable baseline, the roadmap moves toward modern GPU rendering, higher-fidelity environments, improved snow and lighting, contemporary controllers/displays, and new experiences—without losing what makes Tux Racer feel like Tux Racer.

## Status

| Capability | Status |
|---|---|
| macOS Apple Silicon | ✅ Playable |
| M5 Max reference platform | ✅ Validated |
| Retina / HiDPI | ✅ |
| Fullscreen | ✅ |
| Keyboard + mouse menus | ✅ |
| Audio | ✅ |
| Original courses/data | ✅ |
| Original physics/gameplay | ✅ Preserved |
| Linux | 🚧 Planned validation |
| Windows | 🚧 Planned validation |
| Modern renderer abstraction | 🗺 v0.2 |
| Metal renderer | 🗺 v0.3 |
| Vulkan renderer | 🗺 Planned |
| Visual overhaul | 🗺 v0.4+ |

The first known-playable modern Apple Silicon milestone is **v0.1.8**.

## Project principles

1. **Preserve before replacing.** A known-good preservation build remains available for behavioral comparison.
2. **Original credit stays original.** Modernization does not replace or diminish the original authors or contributors.
3. **Gameplay first.** Rendering can change dramatically; physics/gameplay changes require deliberate evaluation.
4. **Open source stays open source.** Tux Racer Modern is intended to remain an open-source project.
5. **Cross-platform by design.** macOS/Metal is the flagship modern renderer, with Linux and Windows supported through portable architecture and a planned Vulkan backend.

## Roadmap

- **0.1.x — Preservation:** native modern builds, SDL modernization, ARM64/64-bit safety, Retina/fullscreen/input, app packaging.
- **0.2.x — Renderer architecture:** separate game/physics from rendering and retain a legacy OpenGL preservation backend.
- **0.3.x — Modern GPU:** Metal on macOS; modern buffers, shaders, frame pacing, MSAA, anisotropic filtering and native high-resolution rendering.
- **0.4.x — Visual overhaul:** modern snow, terrain materials, lighting, shadows, atmosphere, particles, vegetation, ice and environmental effects.
- **1.0 — Modern Tux Racer:** preservation-compatible gameplay with a fully modern presentation and platform experience.

See [`docs/ROADMAP.md`](docs/ROADMAP.md) for detail.

## Building on macOS

Prerequisites: Apple Command Line Tools and Homebrew.

```sh
xcode-select --install   # only if needed
brew install cmake sdl2 sdl2_mixer tcl-tk
./scripts/bootstrap-macos.sh
./build/tuxracer
```

The primary reference machine is currently Apple Silicon ARM64 (M5 Max). See [`docs/BUILDING.md`](docs/BUILDING.md).

## Upstream baseline

Tux Racer Modern is based on Tux Racer 0.61.

- `tuxracer-0.61.tar.gz` SHA-256: `a311d09080598fe556134d4b9faed7dc0c2ed956ebb10d062e5d4df022f91eff`
- `tuxracer-data-0.61.tar.gz` SHA-256: `3783d204b7bb1ed16aa5e5a1d5944de10fbee05bc7cebb8f616fce84301f3651`

The repository retains pristine upstream material for source and behavioral comparison. See `UPSTREAM.md` and `docs/PRESERVATION.md`.

## Licensing and attribution

The imported original Tux Racer source is distributed under the GNU General Public License version 2 terms included with upstream. Original copyright, trademark, authorship, and contributor notices are retained.

**Tux Racer Modern does not claim authorship of the original game.**

Modern port stewardship and modernization work are maintained by **Brian Clark (Skeptic)**. Original Tux Racer was created by **Jasmin F. Patry** with its original contributors.

See `COPYING` and the retained upstream notices for authoritative licensing details.

## Contributing

Contributions are welcome. Please read [`CONTRIBUTING.md`](CONTRIBUTING.md) first, especially the preservation rules around physics/gameplay changes.
