# Terrain Migration

The original adaptive terrain system is retained.

Tux Racer's quadtree already performs the difficult gameplay-preserving work: adaptive LOD, frustum culling, terrain-boundary handling and generation of indexed triangle lists. v0.2 does **not** replace those decisions.

Instead, the modernization boundary is inserted after the quadtree chooses triangles:

```text
height/terrain data
      |
original adaptive quadtree
      |
original LOD + culling decisions
      |
renderer-neutral terrain batches
      |
   +--+--+
   |     |
OpenGL  Metal
```

This gives the Metal backend the same terrain geometry selected by the preservation renderer.

## Initial batch contract

Each batch identifies:
- terrain/material index;
- selected index list;
- index count;
- minimum/maximum referenced vertex index;
- backend-neutral texture handle;
- whether the pass is an environment-map pass.

The existing packed course vertex data remains in place during this first extraction. A later step will expose/copy it into the canonical `tux_vertex_t` layout and upload it to backend-owned vertex buffers.

## Preservation rule

Do not replace the original quadtree or change its LOD thresholds during Metal parity work. Modern terrain tessellation/LOD experiments belong after full renderer parity and must be evaluated against the preservation backend.
