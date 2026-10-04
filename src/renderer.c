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

#ifdef __APPLE__
static int g_metal_native_enabled = 0;
static int g_metal_compare_enabled = 0;
static unsigned char *g_metal_present_pixels = NULL;
static size_t g_metal_present_capacity = 0;
#endif

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
        if ( !renderer_metal_attach_native_window( winsys_get_native_window() ) ) {
            fprintf( stderr, "Tux Racer Modern: native Metal layer unavailable\n" );
        }
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
    free( g_metal_present_pixels );
    g_metal_present_pixels = NULL;
    g_metal_present_capacity = 0;
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
    {
        int logical_w = g_frame.logical_width;
        int logical_h = g_frame.logical_height;
        int drawable_w = g_frame.drawable_width;
        int drawable_h = g_frame.drawable_height;
        winsys_get_window_size( &logical_w, &logical_h );
        winsys_get_drawable_size( &drawable_w, &drawable_h );
        g_frame.logical_width = logical_w;
        g_frame.logical_height = logical_h;
        g_frame.drawable_width = drawable_w;
        g_frame.drawable_height = drawable_h;
        g_frame.aspect_ratio = logical_h > 0 ? (double)logical_w / (double)logical_h : 1.0;
    }
    clear_rendering_context();
}

void renderer_begin_world_frame( void )
{
#ifdef __APPLE__
    if ( g_game.mode != RACING ) return;

    if ( renderer_metal_vertex_bytes() == 0 ) {
        size_t vertex_count = 0;
        const tux_vertex_t *vertices = get_renderer_course_vertices( &vertex_count );
        if ( vertices != NULL && vertex_count > 0 ) {
            renderer_metal_upload_course_vertices( vertices, vertex_count );
        }
    }

    {
        const tux_renderer_camera_state_t *camera = renderer_get_camera_state();
        if ( camera != NULL && camera->valid ) {
            size_t index_count = 0;
            const uint32_t *indices = get_renderer_course_grid_indices( &index_count );
            if ( g_metal_native_enabled ) {
                renderer_metal_begin_native_frame(
                    camera, g_frame.drawable_width, g_frame.drawable_height );
            } else {
                renderer_metal_begin_offscreen_frame(
                    camera, g_frame.drawable_width, g_frame.drawable_height );
            }
            if ( indices != NULL && index_count > 0 ) {
                tux_terrain_batch_t full_grid;
                full_grid.terrain_index = -3;
                full_grid.indices = indices;
                full_grid.index_count = index_count;
                full_grid.min_vertex_index = 0;
                {
                    size_t vertex_count = 0;
                    get_renderer_course_vertices( &vertex_count );
                    full_grid.max_vertex_index =
                        vertex_count > 0 ? (uint32_t)(vertex_count - 1) : 0;
                }
                full_grid.texture = TUX_INVALID_TEXTURE_HANDLE;
                full_grid.environment_pass = 0;
                renderer_metal_consume_terrain_batch( &full_grid, NULL );
            }
        }
    }
#endif
}

void renderer_toggle_metal_compare( void )
{
#ifdef __APPLE__
    g_metal_compare_enabled = !g_metal_compare_enabled;
    fprintf( stderr, "Tux Racer Modern: Metal compare %s\n",
             g_metal_compare_enabled ? "ON" : "OFF" );
#endif
}

void renderer_toggle_metal_native( void )
{
#ifdef __APPLE__
    if ( !g_metal_native_enabled ) {
        /*
         * F10 may be pressed after this frame already opened the offscreen
         * encoder. Close that frame before changing targets; native rendering
         * begins cleanly on the following world frame.
         */
        renderer_metal_end_offscreen_frame();
    }
    g_metal_native_enabled = !g_metal_native_enabled;
    renderer_metal_set_native_visible( g_metal_native_enabled );
    fprintf( stderr, "Tux Racer Modern: native Metal %s\n",
             g_metal_native_enabled ? "ON" : "OFF" );
#endif
}

int renderer_metal_native_enabled( void )
{
#ifdef __APPLE__
    return g_metal_native_enabled;
#else
    return 0;
#endif
}

int renderer_metal_compare_enabled( void )
{
#ifdef __APPLE__
    return g_metal_compare_enabled;
#else
    return 0;
#endif
}

void renderer_present_native_metal_frame( void )
{
#ifdef __APPLE__
    if ( g_metal_native_enabled ) {
        renderer_metal_end_native_frame();
    }
#endif
}

void renderer_present_metal_world_layer( void )
{
#ifdef __APPLE__
    /*
     * Transitional hybrid world layer.  Reuse the proven Metal color
     * readback, then restore the classic 3D matrices so OpenGL can draw
     * trees/items/Tux/HUD above it.  Depth bridging follows next.
     */
    /*
     * Finish GPU work before CPU readback/compositing.  This may be called
     * earlier than renderer_end_frame() in hybrid mode; the Metal end routine
     * is deliberately idempotent when no encoder remains active.
     */
    renderer_metal_end_offscreen_frame();
    renderer_present_metal_terrain();

    glClear( GL_DEPTH_BUFFER_BIT | GL_STENCIL_BUFFER_BIT );
#endif
}

void renderer_present_metal_terrain( void )
{
#ifdef __APPLE__
    int w = 0, h = 0;
    size_t needed;
    int old_matrix_mode = GL_MODELVIEW;

    if ( g_game.mode != RACING || g_frame.drawable_width <= 0 ||
         g_frame.drawable_height <= 0 ) return;

    needed = (size_t)g_frame.drawable_width *
             (size_t)g_frame.drawable_height * 4u;
    if ( needed > g_metal_present_capacity ) {
        unsigned char *pixels = (unsigned char *)realloc(
            g_metal_present_pixels, needed );
        if ( pixels == NULL ) return;
        g_metal_present_pixels = pixels;
        g_metal_present_capacity = needed;
    }

    if ( !renderer_metal_read_present_frame( g_metal_present_pixels,
                                             g_metal_present_capacity,
                                             &w, &h ) ) return;

    glGetIntegerv( GL_MATRIX_MODE, &old_matrix_mode );
    glPushAttrib( GL_ENABLE_BIT | GL_COLOR_BUFFER_BIT |
                  GL_DEPTH_BUFFER_BIT | GL_PIXEL_MODE_BIT );
    glDisable( GL_DEPTH_TEST );
    glDisable( GL_LIGHTING );
    glDisable( GL_TEXTURE_2D );
    glDisable( GL_BLEND );
    glPixelStorei( GL_UNPACK_ALIGNMENT, 1 );

    glMatrixMode( GL_PROJECTION );
    glPushMatrix();
    glLoadIdentity();
    glOrtho( 0.0, (double)w, 0.0, (double)h, -1.0, 1.0 );
    glMatrixMode( GL_MODELVIEW );
    glPushMatrix();
    glLoadIdentity();

    glRasterPos2i( 0, 0 );
    glDrawPixels( w, h, GL_RGBA, GL_UNSIGNED_BYTE, g_metal_present_pixels );

    glPopMatrix();
    glMatrixMode( GL_PROJECTION );
    glPopMatrix();
    glMatrixMode( old_matrix_mode );
    glPopAttrib();
#endif
}

void renderer_end_frame( void )
{
#ifdef __APPLE__
    renderer_metal_end_offscreen_frame();
    /*
     * Live hybrid presentation is intentionally disabled until Metal camera
     * parity is exact.  Keep the bridge available for controlled testing.
     */
#endif
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

    {
        const double fov = g_camera.projection_fov_degrees * M_PI / 180.0;
        const double f = 1.0 / tan( fov * 0.5 );
        const double a = g_camera.aspect_ratio > 0.0 ? g_camera.aspect_ratio : 1.0;
        const double n = g_camera.near_clip;
        const double zf = g_camera.far_clip;
        double p[16] = {
            f/a, 0, 0, 0,
            0, f, 0, 0,
            0, 0, (zf+n)/(n-zf), -1,
            0, 0, (2*zf*n)/(n-zf), 0
        };
        int row, col, k;
        for ( k = 0; k < 16; ++k ) {
            g_camera.projection_matrix[k] = p[k];
            g_camera.view_projection_matrix[k] = 0.0;
        }
        /* Column-major P * V, matching the preserved OpenGL matrices. */
        for ( col = 0; col < 4; ++col ) {
            for ( row = 0; row < 4; ++row ) {
                double sum = 0.0;
                for ( k = 0; k < 4; ++k ) {
                    sum += p[k*4 + row] * view_matrix[col*4 + k];
                }
                g_camera.view_projection_matrix[col*4 + row] = sum;
            }
        }
    }
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
