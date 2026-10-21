# Modern iOS 3D vertical slice

This directory is a clean-slate iOS gameplay experiment, **not** the original Tux Racer engine or preservation project.

Run with the CMake option `-DTUX_IOS_MODERN3D=ON` (enabled by default on `feature/ios-modern-3d`). The last working 2.5D SDL renderer remains selectable via `-DTUX_IOS_MODERN3D=OFF`.

## First milestone
- Use the proven SDL2 / UIKit UIScene bootstrap to create an actual CAMetalLayer
- Render a 3D downhill course with a depth buffer, real perspective projection, shading, and a mobile-friendly render loop
- Parse `course.json` as the first data-driven course definition; **this initial slice uses only course length, width, slope and speeds**
- Provide steering and braking using touch zones and keyboard, with a simple course-following placeholder player
- Keep course assets and rendering source entirely outside the macOS preservation release

## Planned game content
The next gates are a rigged/high-resolution Tux mesh, a genuine glTF / asset conversion pipeline, materials and lighting, fish and collision, 3D trees, course authoring, clothing/hat attachment points, animations and saved race results.

Avoid confusing a 3D rendering slice with a finished game. It does not yet include the original code-driven physics or modern authored models.
