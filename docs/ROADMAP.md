# Tux Racer Modern Roadmap

## v0.1 — Preservation
Goal: run the original Tux Racer faithfully on current hardware before changing its character.

Completed through v0.1.8: modern CMake baseline, SDL modernization, Apple Silicon ARM64 compilation, 64-bit safety fixes, Retina/HiDPI rendering, fullscreen, keyboard/mouse UI input, original data discovery, original audio, courses and gameplay.

Remaining v0.1.x work: remove legacy crosshair behavior, package a self-contained macOS `.app`, bundle resources, add application metadata/icon support, reduce portability warnings, and validate CI on macOS/Linux/Windows.

## v0.2 — Renderer abstraction
Create a renderer boundary between the original game/physics/course systems and graphics implementation. Keep the legacy OpenGL path as a preservation/reference backend. Define scene, terrain, character, particle, UI and resource interfaces suitable for modern GPU APIs.

## v0.3 — Modern GPU
### macOS / Metal
Metal is the flagship renderer. Targets include native Apple GPU buffers, shader-based rendering, modern texture formats/filtering, MSAA, anisotropic filtering, correct frame pacing, high-refresh displays, Retina-native output and GPU profiling.

### Linux / Windows
Vulkan is the planned modern portable backend. Platform architecture should avoid embedding Metal-specific assumptions in game logic.

## v0.4 — Visual overhaul
Prioritize the environment while keeping Tux recognizable and stylized. Areas of investment: snow materials and spray, tracks/deformation, terrain normal/roughness detail, dynamic lighting/shadows, atmospheric fog/sky, reflective ice, improved vegetation, particles, weather and time-of-day experimentation.

## v1.0 — Modern Tux Racer
A polished open-source Tux Racer experience with preserved gameplay identity, modern rendering, contemporary packaging/input/display support, and a stable cross-platform architecture.
