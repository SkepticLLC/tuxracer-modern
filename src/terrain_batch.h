/*
 * Renderer-neutral terrain batches produced by the preserved adaptive
 * quadtree.  A batch describes exactly the indexed triangles selected by the
 * original LOD/culling algorithm for one terrain pass.
 */
#ifndef TUXRACER_TERRAIN_BATCH_H
#define TUXRACER_TERRAIN_BATCH_H

#include <stddef.h>
#include <stdint.h>
#include "renderer_resources.h"

#ifdef __cplusplus
extern "C" {
#endif

typedef struct {
    int terrain_index;
    const uint32_t *indices;
    size_t index_count;
    uint32_t min_vertex_index;
    uint32_t max_vertex_index;
    tux_texture_handle_t texture;
    int environment_pass;
} tux_terrain_batch_t;

typedef void (*tux_terrain_batch_consumer_t)( const tux_terrain_batch_t *batch,
                                              void *context );

void terrain_set_batch_consumer( tux_terrain_batch_consumer_t consumer,
                                 void *context );
void terrain_submit_batch( const tux_terrain_batch_t *batch );
const tux_terrain_batch_t *terrain_get_latest_unified_batch( void );

#ifdef __cplusplus
}
#endif

#endif
