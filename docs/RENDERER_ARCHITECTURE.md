# Renderer Architecture — v0.2

## Objective
Decouple Tux Racer gameplay, physics, course/Tcl systems and platform input from the 2000-era immediate-mode OpenGL renderer without changing preserved game behavior.

## Migration rule
v0.2 starts by wrapping existing behavior. A renderer abstraction is considered successful only when the legacy backend remains visually and behaviorally equivalent to the v0.1.9 preservation release.

## Backends
### Legacy OpenGL
The reference implementation. It remains available during modernization for A/B comparison and regression diagnosis.

### Metal
The flagship macOS backend. It will be implemented incrementally behind the renderer interface. Metal-specific objects must not leak into gameplay, physics, course or Tcl code.

### Vulkan
Planned portable modern backend for Linux and Windows after the renderer contract stabilizes.

## Phases
1. **Lifecycle seam** — initialization, shutdown, resize, begin/end frame.
2. **Camera/frame state** — projection/view data represented independently of OpenGL matrix stacks.
3. **Resource layer** — textures, samplers, meshes and GPU lifetime.
4. **Terrain submission** — first substantial scene system moved behind the renderer.
5. **World systems** — trees/items, sky/atmosphere, Tux, particles, track marks and UI.
6. **Metal parity** — Metal can render a complete original scene.
7. **Modern materials** — visual work begins after parity: snow/ice/terrain materials, lighting, shadows, atmosphere and effects.

## Non-goals for the first v0.2 milestone
- No physics changes.
- No course format changes.
- No new art requirement.
- No visual redesign.
- No removal of the legacy OpenGL backend.
