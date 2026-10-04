# GPU Resource Model

v0.2 introduces backend-neutral handles before migrating individual drawing systems.

## Why handles
The original renderer exposes OpenGL object names such as `GLuint` directly to game code. Metal and Vulkan use different resource objects and lifetime models. Tux Racer Modern therefore uses small opaque IDs at the game/renderer boundary.

## Initial resource types
- `tux_texture_handle_t`
- `tux_mesh_handle_t`
- `tux_material_handle_t`

A handle identifies a renderer-owned resource. It is not a native OpenGL, Metal or Vulkan object.

## Texture migration
The original Tcl names and bindings remain unchanged. During migration, the legacy texture system may continue owning OpenGL textures while the renderer resource table associates stable Tux handles with them. Later, the Metal backend can create `MTLTexture` resources from the same decoded image data without changing Tcl/course definitions.

## Mesh migration
The canonical modern vertex layout begins with position, normal and UV. Terrain will be the first large system converted from immediate-mode submission into indexed mesh data.

## Material migration
Materials start deliberately small: diffuse/specular values, roughness and a base texture handle. Modern snow/ice/terrain materials will extend this model only after Metal parity is achieved.
