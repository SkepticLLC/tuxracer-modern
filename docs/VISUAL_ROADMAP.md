# Tux Racer Modern — Visual Roadmap

The classic experience is preserved. The modern renderer may now intentionally exceed the visual quality of the legacy OpenGL renderer while preserving Tux Racer identity.

## Phase A — Modern mountain
- Unified Metal terrain submission.
- Smooth snow / rock / ice transitions.
- Directional sunlight plus cool ambient sky contribution.
- Atmospheric distance fog.
- Improved terrain texture filtering and material response.
- Modern sky foundation.

## Phase B — Snow and ice
- Snow micro-normal/detail layer.
- Slope- and distance-aware texture detail.
- Ice roughness/reflection response.
- Sparkle/highlight effects used sparingly.
- Track marks and eventual deformation behind Tux.

## Phase C — Tux Racer world
- Trees and course objects moved to modern renderer.
- Fish/items with modern lighting and effects.
- Weather and snow particles.
- Shadows and contact grounding.
- Tux moved to the modern renderer while preserving his recognizable design and animation character.

## Phase D — Presentation
- Tux-centric animated modern menus.
- Penguin personality throughout UI scenes.
- Modern typography/layout without becoming a generic winter-sports game.
- Classic rendering/presentation option retained where practical.

## North star

**Preserve the game. Modernize the world. Keep Tux unmistakably Tux.**


## Metal integration checkpoint

The hybrid Metal-to-OpenGL CPU readback path successfully demonstrated a combined
playable scene with Metal terrain and preserved OpenGL foreground objects. It is
a diagnostic bridge only and must not become a production rendering path.

Observed cost:
- Retina BGRA frame: 3456 x 2168 x 4 bytes (~30 MB).
- Synchronous Metal completion before each readback.
- CPU texture copy followed by OpenGL pixel upload every frame.
- Result: unacceptable latency/judder despite correct visual integration.

Production direction:
- Metal presents directly to a CAMetalLayer drawable.
- No per-frame GPU -> CPU -> GPU image transfer.
- Scene systems migrate to Metal behind the renderer abstraction.
- Classic OpenGL remains a separately selectable preservation backend.
