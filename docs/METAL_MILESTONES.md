# Metal Milestones

## 2026-10-04 — First visible Metal-rendered Tux Racer terrain

Tux Racer Modern successfully rendered original adaptive course terrain through Apple's Metal API on an **Apple M5 Max**.

Validated path:

- Metal device: Apple M5 Max
- Native Metal terrain pipeline compiled successfully
- 21,600 canonical terrain vertices uploaded
- 691,200 bytes of terrain vertex data resident in Metal
- Original quadtree produced snow/ice/rock indexed batches
- Three indexed Metal terrain draws completed
- Original camera/projection translated to Metal clip space
- Depth testing operational
- Offscreen Retina render target: 3456 × 2168
- Diagnostic frame successfully read back as a valid Netpbm image
- Visible terrain geometry was coherent and recognizable

The preservation OpenGL renderer remained active and playable throughout the test.

This milestone proves the modernization architecture can feed original Tux Racer world geometry through a native Apple GPU renderer without replacing gameplay, physics, course data, or the original adaptive terrain system.

### Next parity target

Original snow, ice, and rock texture/material rendering in Metal.

Visual modernization begins only after renderer parity is sufficiently established. The project design principle remains:

> Modernize the world around Tux without modernizing Tux out of the game.
