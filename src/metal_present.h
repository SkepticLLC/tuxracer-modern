#ifndef TUXRACER_METAL_PRESENT_H
#define TUXRACER_METAL_PRESENT_H

#ifdef __cplusplus
extern "C" {
#endif

int metal_present_attach_to_sdl_window( void *sdl_window, void *metal_device );
void metal_present_resize( int drawable_width, int drawable_height );
void *metal_present_next_drawable( void );
void *metal_present_layer( void );
void metal_present_set_visible( int visible );
void metal_present_shutdown( void );

#ifdef __cplusplus
}
#endif
#endif
