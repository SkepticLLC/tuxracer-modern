/*
 * Tux Racer Modern renderer abstraction
 *
 * Modern port maintained by Brian Clark (Skeptic) <jbrianclark@icloud.com>
 * Based on the original Tux Racer by Jasmin F. Patry and contributors.
 *
 * This interface is intentionally small in v0.2.0.  It creates a stable
 * boundary around frame lifecycle operations before individual legacy
 * OpenGL drawing systems are migrated.
 */
#ifndef TUXRACER_RENDERER_H
#define TUXRACER_RENDERER_H

#ifdef __cplusplus
extern "C" {
#endif

typedef enum {
    TUX_RENDERER_LEGACY_OPENGL = 0,
    TUX_RENDERER_METAL
} tux_renderer_backend_t;

typedef struct {
    tux_renderer_backend_t backend;
    const char *name;
    int initialized;
} tux_renderer_info_t;

int renderer_initialize( tux_renderer_backend_t backend );
void renderer_shutdown( void );
typedef struct {
    int logical_width;
    int logical_height;
    int drawable_width;
    int drawable_height;
    double aspect_ratio;
} tux_renderer_frame_state_t;

void renderer_resize( int logical_width, int logical_height );
void renderer_begin_frame( void );
void renderer_end_frame( void );
void renderer_present_metal_terrain( void );
void renderer_begin_world_frame( void );
void renderer_toggle_metal_compare( void );
int renderer_metal_compare_enabled( void );
const tux_renderer_info_t *renderer_get_info( void );
typedef struct {
    double view_matrix[16];
    double projection_matrix[16];
    double view_projection_matrix[16];
    double projection_fov_degrees;
    double near_clip;
    double far_clip;
    double aspect_ratio;
    double position[3];
    double direction[3];
    double up[3];
    int valid;
} tux_renderer_camera_state_t;

void renderer_set_camera( const double view_matrix[16],
                          double px, double py, double pz,
                          double dx, double dy, double dz,
                          double ux, double uy, double uz );
const tux_renderer_frame_state_t *renderer_get_frame_state( void );
const tux_renderer_camera_state_t *renderer_get_camera_state( void );

#ifdef __cplusplus
}
#endif

#endif
