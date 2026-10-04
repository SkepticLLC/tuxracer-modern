#include "terrain_batch.h"
#include <stdlib.h>
#include <string.h>

static tux_terrain_batch_consumer_t g_consumer = 0;
static void *g_context = 0;
static uint32_t *g_unified_indices = 0;
static size_t g_unified_capacity = 0;
static tux_terrain_batch_t g_unified_batch = {0};

void terrain_set_batch_consumer( tux_terrain_batch_consumer_t consumer,
                                 void *context )
{
    g_consumer = consumer;
    g_context = context;
}

void terrain_submit_batch( const tux_terrain_batch_t *batch )
{
    if ( batch == 0 ) return;

    if ( batch->terrain_index == -2 && batch->indices != 0 && batch->index_count > 0 ) {
        if ( batch->index_count > g_unified_capacity ) {
            uint32_t *new_indices = (uint32_t *)realloc(
                g_unified_indices, batch->index_count * sizeof(uint32_t) );
            if ( new_indices != 0 ) {
                g_unified_indices = new_indices;
                g_unified_capacity = batch->index_count;
            }
        }
        if ( g_unified_indices != 0 && g_unified_capacity >= batch->index_count ) {
            memcpy( g_unified_indices, batch->indices,
                    batch->index_count * sizeof(uint32_t) );
            g_unified_batch = *batch;
            g_unified_batch.indices = g_unified_indices;
        }
        return;
    }

    if ( g_consumer != 0 ) {
        g_consumer( batch, g_context );
    }
}

const tux_terrain_batch_t *terrain_get_latest_unified_batch( void )
{
    return g_unified_batch.indices != 0 && g_unified_batch.index_count > 0
        ? &g_unified_batch : 0;
}
