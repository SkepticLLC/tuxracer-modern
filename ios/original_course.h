/* Original Tux Racer course metadata loader for iOS.
 * Reads selected declarations from the original course.tcl, without
 * evaluating Tcl. Not a replacement for the full original Tcl engine.
 * SPDX-License-Identifier: GPL-2.0-or-later */
#ifndef TUX_IOS_ORIGINAL_COURSE_H
#define TUX_IOS_ORIGINAL_COURSE_H
#include <stddef.h>
typedef struct {
    char name[96];
    char elevation_file[96];
    char terrain_file[96];
    float width_m, length_m;
    float play_width_m, play_length_m;
    float start_x_m, start_z_m;
    float angle_deg, elevation_scale;
} tux_original_course;
int tux_original_course_load(const char *course_tcl_path, tux_original_course *out);
#endif
