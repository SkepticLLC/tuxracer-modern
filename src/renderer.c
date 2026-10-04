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

static tux_renderer_info_t g_renderer = {
    TUX_RENDERER_LEGACY_OPENGL,
    "Legacy OpenGL",
    0
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
    return 1;
}

void renderer_shutdown( void )
{
    g_renderer.initialized = 0;
}

void renderer_resize( int logical_width, int logical_height )
{
    /*
     * The legacy implementation still owns projection setup.  This wrapper is
     * the migration seam for Metal drawable and camera projection handling.
     */
    reshape( logical_width, logical_height );
}

void renderer_begin_frame( void )
{
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
