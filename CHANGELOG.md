# Changelog

## 0.1.9 — Apple Silicon Preservation Release

First polished native macOS preservation release.

### Highlights
- Self-contained **Tux Racer Modern.app** packaging with bundled original game data.
- Validated on Apple Silicon **M5 Max**.
- Retina/HiDPI fullscreen rendering.
- Modern SDL2 keyboard and mouse input.
- Native system pointer replaces the legacy software crosshair cursor.
- 64-bit-safe UI callback keys and Apple Silicon compatibility fixes.
- Automatic development and application-bundle data discovery.
- Original courses, audio, Tcl data system, gameplay and physics retained.
- Original Jasmin F. Patry authorship, copyright and contributor attribution retained.
- Modern port maintained by **Brian Clark (Skeptic) <jbrianclark@icloud.com>**.
- Repository license presentation aligned with retained upstream GPLv2-or-later source notices.
- macOS CI build is green.

### Packaging
Build the project and run:

```sh
bash ./scripts/package-macos.sh
open "build/Tux Racer Modern.app"
```

Development bundles are ad-hoc signed. Public Developer ID signing/notarization is future release engineering work.

## 0.1.8 — Preservation milestone
First known-playable native Apple Silicon milestone. Frozen as `v0.1.8-preservation`.
