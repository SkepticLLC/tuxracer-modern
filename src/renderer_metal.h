#ifndef TUXRACER_RENDERER_METAL_H
#define TUXRACER_RENDERER_METAL_H

#include <stddef.h>
#include "renderer_resources.h"
#include "terrain_batch.h"

#ifdef __cplusplus
extern "C" {
#endif

int renderer_metal_probe( void );
const char *renderer_metal_device_name( void );
int renderer_metal_initialize_resources( void );
void renderer_metal_shutdown_resources( void );
int renderer_metal_upload_course_vertices( const tux_vertex_t *vertices,
                                           size_t vertex_count );
void renderer_metal_consume_terrain_batch( const tux_terrain_batch_t *batch,
                                           void *context );
size_t renderer_metal_vertex_bytes( void );
size_t renderer_metal_last_index_bytes( void );

#ifdef __cplusplus
}
#endif
#endif
