#ifndef TUXRACER_RENDERER_METAL_H
#define TUXRACER_RENDERER_METAL_H

#include <stddef.h>
#include "renderer_resources.h"
#include "terrain_batch.h"
#include "renderer.h"

#ifdef __cplusplus
extern "C" {
#endif

int renderer_metal_probe( void );
const char *renderer_metal_device_name( void );
int renderer_metal_initialize_resources( void );
void renderer_metal_shutdown_resources( void );
void renderer_metal_register_named_texture( const char *name,
                                            tux_texture_handle_t handle );
int renderer_metal_upload_texture( tux_texture_handle_t handle,
                                   int width, int height, int channels,
                                   const unsigned char *pixels,
                                   int repeatable );
int renderer_metal_upload_course_vertices( const tux_vertex_t *vertices,
                                           size_t vertex_count );
void renderer_metal_consume_terrain_batch( const tux_terrain_batch_t *batch,
                                           void *context );
size_t renderer_metal_vertex_bytes( void );
size_t renderer_metal_last_index_bytes( void );
void renderer_metal_begin_offscreen_frame( const tux_renderer_camera_state_t *camera,
                                           int width, int height );
void renderer_metal_end_offscreen_frame( void );
int renderer_metal_attach_native_window( void *sdl_window );
void renderer_metal_set_native_visible( int visible );
int renderer_metal_begin_native_frame( const tux_renderer_camera_state_t *camera,
                                       int width, int height );
void renderer_metal_end_native_frame( void );

int renderer_metal_read_present_frame( unsigned char *rgba,
                                       size_t rgba_bytes,
                                       int *width, int *height );

#ifdef __cplusplus
}
#endif
#endif
