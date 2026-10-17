/* Original Tux Racer SGI RGB elevation / terrain map decoding.
 * SPDX-License-Identifier: GPL-2.0-or-later */
#ifndef TUX_IOS_ORIGINAL_TERRAIN_H
#define TUX_IOS_ORIGINAL_TERRAIN_H
#include <stdint.h>
typedef struct {
    int width, height;
    uint8_t *elevation;
    uint8_t *surface;
} tux_original_terrain;
int tux_original_terrain_load(tux_original_terrain *map,
                             const char *elevation_path,
                             const char *terrain_path);
void tux_original_terrain_free(tux_original_terrain *map);
/* x in 0..1 left->right, z in 0..1 start->finish.
 * The original course loader flips both axes of the source SGI images.
 * Elevation values are raw pixels; convert using course.elevation_scale.
 */
float tux_original_elevation(const tux_original_terrain *map,float x,float z);
int tux_original_surface(const tux_original_terrain *map,float x,float z);
#endif
