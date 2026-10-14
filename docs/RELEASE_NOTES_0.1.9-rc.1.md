# Tux Racer Modern 0.1.9 — Apple Silicon RC1

This is **Release Candidate 1** for the Tux Racer Modern 0.1.9 Apple Silicon preservation release.

RC1 is intentionally narrow. It contains the published Beta 1 preservation port plus one confirmed visual compatibility fix.

## Fixed in RC1

### Main-screen crosshair / seam artifact

The original splash/main artwork is assembled from four separate textures. On modern OpenGL/Retina displays, the legacy combination of linear filtering with `GL_CLAMP` could sample the texture border at UV edges.

Where the four image quadrants meet, that produced a visible vertical and horizontal seam through the center of the screen — appearing like a crosshair.

RC1 changes non-repeatable texture wrapping from:

```text
GL_CLAMP
```

to:

```text
GL_CLAMP_TO_EDGE
```

This keeps filtering on the outermost image texel and removes the center seams without changing the artwork, layout, gameplay, or physics.

## Based on Beta 1

RC1 retains everything from **v0.1.9-beta.1**:

- native Apple Silicon ARM64 build
- original Tux Racer gameplay, physics, courses, music, sounds, and credits
- classic SDL2 + SDL2_mixer statically linked
- no Homebrew/SDL3 runtime dependency
- Retina / HiDPI support
- fullscreen and windowed play
- proper macOS app icon
- Developer ID signing
- hardened runtime
- notarization and stapling for public distribution

## System requirements

- macOS 13 or later
- Apple Silicon Mac (ARM64)

## Scope

No gameplay, physics, content, control, or menu-flow changes are intended in RC1.

This release candidate exists specifically to validate the preservation build with the splash-screen seam fix before the final 0.1.9 release.

## Source and licensing

Tux Racer Modern is based on the original Tux Racer 0.61 source and data.

Original Tux Racer was created by **Jasmin F. Patry** with its original contributors. Original copyright and contributor notices are retained.

The imported original Tux Racer source is distributed under the **GNU General Public License version 2** terms included with the project.

Modern port stewardship and modernization work are maintained by **Brian Clark / Skeptic**.

See `COPYING`, `UPSTREAM.md`, and `docs/PRESERVATION.md` for details.
