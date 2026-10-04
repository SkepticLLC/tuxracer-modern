/*
 * Tux Racer Modern renderer abstraction
 *
 * Phase 1 deliberately delegates to the preserved OpenGL renderer.  The
 * purpose is to establish the lifecycle/API seam without changing pixels or
 * gameplay.  Metal will be introduced behind this interface incrementally.
 */
#include "tuxracer.h"
#include "renderer.h"
#include "render_util.h"
#include "winsys.h"
#ifdef __APPLE__
#include "renderer_metal.h"
#include "course_load.h"
#include "terrain_batch.h"
#endif

static tux_renderer_info_t g_renderer = {
    TUX_RENDERER_LEGACY_OPENGL,
    "Legacy OpenGL",
    0
};

static tux_renderer_frame_state_t g_frame = {
    640, 480, 640, 480, 4.0 / 3.0
};

static tux_renderer_camera_state_t g_camera = {
    { 1, 0, 0, 0,
      0, 1, 0, 0,
      0, 0, 1, 0,
      0, 0, 0, 1 },
    60.0, 0.1, 100.0, 4.0 / 3.0,
    { 0, 0, 0 }, { 0, 0, -1 }, { 0, 1, 0 }, 0
};

int renderer_initialize( tux_renderer_backend_t backend )
{
    /*
     * v0.2.0 phase 1 supports only the preservation renderer.  Keep Metal in
     * the public backend enum so callers do not need to change when the native
     * backend arrives, but fail cleanly until it is implemented.
     */
    if ( backend != TUX_RENDERER_LEGACY_OPENGL ) {
        return 0;
    }

    g_renderer.backend = backend;
    g_renderer.name = "Legacy OpenGL";
    g_renderer.initialized = 1;

#ifdef __APPLE__
    /*
     * Probe Metal in parallel while OpenGL remains the presenting backend.
     * This is intentionally diagnostic during the first v0.2 milestone.
     */
    if ( renderer_metal_probe() && renderer_metal_initialize_resources() ) {
        fprintf( stderr, "Tux Racer Modern: Metal device available: %s\n",
                 renderer_metal_device_name() );
        terrain_set_batch_consumer( renderer_metal_consume_terrain_batch, NULL );
    } else {
        fprintf( stderr, "Tux Racer Modern: Metal device unavailable\n" );
    }
#endif
    return 1;
}

void renderer_shutdown( void )
{
#ifdef __APPLE__
    terrain_set_batch_consumer( NULL, NULL );
    renderer_metal_shutdown_resources();
#endif
    g_renderer.initialized = 0;
}

void renderer_resize( int logical_width, int logical_height )
{
    int drawable_width = logical_width;
    int drawable_height = logical_height;

    winsys_get_drawable_size( &drawable_width, &drawable_height );

    g_frame.logical_width = logical_width;
    g_frame.logical_height = logical_height;
    g_frame.drawable_width = drawable_width;
    g_frame.drawable_height = drawable_height;
    g_frame.aspect_ratio = logical_height > 0
        ? (double)logical_width / (double)logical_height
        : 1.0;

    /*
     * Phase 2 still delegates projection/viewport setup to the preservation
     * renderer.  Metal will consume g_frame without depending on OpenGL.
     */
    reshape( logical_width, logical_height );
}

void renderer_begin_frame( void )
{
#ifdef __APPLE__
    if ( renderer_metal_vertex_bytes() == 0 ) {
        size_t vertex_count = 0;
        const tux_vertex_t *vertices = get_renderer_course_vertices( &vertex_count );
        if ( vertices != NULL && vertex_count > 0 ) {
            renderer_metal_upload_course_vertices( vertices, vertex_count );
        }
    }
#endif
    clear_rendering_context();
}

void renderer_end_frame( void )
{
    winsys_swap_buffers();
}

const tux_renderer_info_t *renderer_get_info( void )
{
    return &g_renderer;
}

void renderer_set_camera( const double view_matrix[16],
                          double px, double py, double pz,
                          double dx, double dy, double dz,
                          double ux, double uy, double uz )
{
    int i;
    for ( i = 0; i < 16; ++i ) {
        g_camera.view_matrix[i] = view_matrix[i];
    }

    g_camera.projection_fov_degrees = getparam_fov();
    g_camera.near_clip = NEAR_CLIP_DIST;
    g_camera.far_clip = getparam_forward_clip_distance() + 5.0;
    g_camera.aspect_ratio = g_frame.aspect_ratio;
    g_camera.position[0] = px; g_camera.position[1] = py; g_camera.position[2] = pz;
    g_camera.direction[0] = dx; g_camera.direction[1] = dy; g_camera.direction[2] = dz;
    g_camera.up[0] = ux; g_camera.up[1] = uy; g_camera.up[2] = uz;
    g_camera.valid = 1;
}

const tux_renderer_frame_state_t *renderer_get_frame_state( void )
{
    return &g_frame;
}

const tux_renderer_camera_state_t *renderer_get_camera_state( void )
{
    return &g_camera;
}
