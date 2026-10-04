#include "terrain_batch.h"

static tux_terrain_batch_consumer_t g_consumer = 0;
static void *g_context = 0;

void terrain_set_batch_consumer( tux_terrain_batch_consumer_t consumer,
                                 void *context )
{
    g_consumer = consumer;
    g_context = context;
}

void terrain_submit_batch( const tux_terrain_batch_t *batch )
{
    if ( g_consumer != 0 && batch != 0 ) {
        g_consumer( batch, g_context );
    }
}
