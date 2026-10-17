/* Modern iOS course rendering: continuous projected mesh from original
 * Tux Racer elevation/surface data, rendered by SDL2's Metal backend.
 * This is a visual bridge, not original gameplay/physics.
 * SPDX-License-Identifier: GPL-2.0-or-later */
#ifndef TUX_IOS_MODERN_TERRAIN_H
#define TUX_IOS_MODERN_TERRAIN_H
#include <SDL.h>
#include "original_course.h"
#include "original_terrain.h"

typedef struct tux_modern_terrain tux_modern_terrain;
tux_modern_terrain *tux_modern_terrain_create(void);
void tux_modern_terrain_destroy(tux_modern_terrain *renderer);
void tux_modern_terrain_reset(tux_modern_terrain *renderer, float player_distance, float player_x);
void tux_modern_terrain_update(tux_modern_terrain *renderer, float dt,
                               float player_distance, float player_x,
                               const tux_original_course *course);
int tux_modern_terrain_draw(tux_modern_terrain *renderer, SDL_Renderer *render,
                            int width, int height,
                            const tux_original_terrain *map,
                            const tux_original_course *course);
#endif
