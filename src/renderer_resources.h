/*
 * Tux Racer Modern renderer resource handles.
 *
 * These handles deliberately contain no OpenGL or Metal types.  Game and
 * content systems can retain stable IDs while each backend owns native GPU
 * objects internally.
 */
#ifndef TUXRACER_RENDERER_RESOURCES_H
#define TUXRACER_RENDERER_RESOURCES_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef uint32_t tux_texture_handle_t;
typedef uint32_t tux_mesh_handle_t;
typedef uint32_t tux_material_handle_t;

#define TUX_INVALID_TEXTURE_HANDLE ((tux_texture_handle_t)0)
#define TUX_INVALID_MESH_HANDLE ((tux_mesh_handle_t)0)
#define TUX_INVALID_MATERIAL_HANDLE ((tux_material_handle_t)0)

typedef enum {
    TUX_TEXTURE_WRAP_CLAMP = 0,
    TUX_TEXTURE_WRAP_REPEAT = 1
} tux_texture_wrap_t;

typedef struct {
    int width;
    int height;
    int channels;
    tux_texture_wrap_t wrap;
} tux_texture_desc_t;

typedef struct {
    float position[3];
    float normal[3];
    float texcoord[2];
    float terrain_weights[4]; /* Snow, Rock, Ice, padding */
} tux_vertex_t;

typedef struct {
    const tux_vertex_t *vertices;
    size_t vertex_count;
    const uint32_t *indices;
    size_t index_count;
} tux_mesh_desc_t;

typedef struct {
    float diffuse[4];
    float specular[4];
    float roughness;
    tux_texture_handle_t base_texture;
} tux_material_desc_t;

#ifdef __cplusplus
}
#endif

#endif
