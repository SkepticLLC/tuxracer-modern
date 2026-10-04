# Metal Backend

Metal is the flagship modern renderer for macOS.

## Current state
The first v0.2 Metal milestone is intentionally non-presenting:

1. create the system default `MTLDevice`;
2. identify the Apple GPU;
3. expose renderer-neutral course vertices and quadtree terrain batches;
4. compile the first terrain shader source as part of development;
5. keep Legacy OpenGL visible until Metal resource submission is verified.

This parallel approach avoids turning the renderer migration into an all-or-nothing rewrite.

## First shader
`shaders/terrain.metal` defines the initial position/normal/UV terrain pipeline. Its output is intentionally simple. Visual modernization begins only after geometry/camera/material parity with the preservation renderer.

## Next
- create Metal vertex buffers from canonical course vertices;
- create/reuse index buffers from quadtree terrain batches;
- decode/upload textures to `MTLTexture`;
- create a Metal render pipeline and depth state;
- attach a Metal drawable to the SDL/macOS window;
- render terrain in diagnostic/parallel mode;
- switch terrain presentation from OpenGL to Metal after parity.
