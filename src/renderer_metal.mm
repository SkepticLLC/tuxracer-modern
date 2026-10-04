/*
 * Tux Racer Modern Metal backend foundation.
 *
 * OpenGL still presents pixels in this milestone. Metal owns real GPU
 * resources in parallel so terrain data can be validated before presentation
 * switches backends.
 */
#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
#include <stdio.h>
#include "renderer_metal.h"

static id<MTLDevice> g_device = nil;
static id<MTLCommandQueue> g_command_queue = nil;
static id<MTLBuffer> g_course_vertex_buffer = nil;
static id<MTLBuffer> g_last_index_buffer = nil;
static char g_device_name[256] = {0};
static size_t g_vertex_bytes = 0;
static size_t g_last_index_bytes = 0;
static unsigned long long g_batch_count = 0;

int renderer_metal_probe( void )
{
    @autoreleasepool {
        if ( g_device == nil ) {
            g_device = MTLCreateSystemDefaultDevice();
            if ( g_device == nil ) {
                return 0;
            }

            const char *name = [[g_device name] UTF8String];
            if ( name != NULL ) {
                snprintf( g_device_name, sizeof(g_device_name), "%s", name );
            }
        }
        return 1;
    }
}

const char *renderer_metal_device_name( void )
{
    return g_device_name[0] != '\0' ? g_device_name : "Unavailable";
}

int renderer_metal_initialize_resources( void )
{
    @autoreleasepool {
        if ( !renderer_metal_probe() ) {
            return 0;
        }
        if ( g_command_queue == nil ) {
            g_command_queue = [g_device newCommandQueue];
        }
        return g_command_queue != nil;
    }
}

void renderer_metal_shutdown_resources( void )
{
    @autoreleasepool {
        g_last_index_buffer = nil;
        g_course_vertex_buffer = nil;
        g_command_queue = nil;
        g_vertex_bytes = 0;
        g_last_index_bytes = 0;
        g_batch_count = 0;
    }
}

int renderer_metal_upload_course_vertices( const tux_vertex_t *vertices,
                                           size_t vertex_count )
{
    @autoreleasepool {
        if ( vertices == NULL || vertex_count == 0 ||
             !renderer_metal_initialize_resources() ) {
            return 0;
        }

        g_vertex_bytes = sizeof(tux_vertex_t) * vertex_count;
        g_course_vertex_buffer =
            [g_device newBufferWithBytes:vertices
                                  length:g_vertex_bytes
                                 options:MTLResourceStorageModeShared];

        if ( g_course_vertex_buffer == nil ) {
            g_vertex_bytes = 0;
            return 0;
        }

        fprintf( stderr,
                 "Tux Racer Modern: Metal uploaded %zu terrain vertices (%zu bytes)\n",
                 vertex_count, g_vertex_bytes );
        return 1;
    }
}

void renderer_metal_consume_terrain_batch( const tux_terrain_batch_t *batch,
                                           void *context )
{
    (void)context;
    @autoreleasepool {
        if ( batch == NULL || batch->indices == NULL ||
             batch->index_count == 0 || g_device == nil ) {
            return;
        }

        g_last_index_bytes = batch->index_count * sizeof(uint32_t);
        g_last_index_buffer =
            [g_device newBufferWithBytes:batch->indices
                                  length:g_last_index_bytes
                                 options:MTLResourceStorageModeShared];
        if ( g_last_index_buffer != nil ) {
            ++g_batch_count;
            if ( g_batch_count <= 3 ) {
                fprintf( stderr,
                         "Tux Racer Modern: Metal terrain batch %llu: terrain=%d, indices=%zu, bytes=%zu\n",
                         g_batch_count, batch->terrain_index,
                         batch->index_count, g_last_index_bytes );
            }
        }
    }
}

size_t renderer_metal_vertex_bytes( void ) { return g_vertex_bytes; }
size_t renderer_metal_last_index_bytes( void ) { return g_last_index_bytes; }
