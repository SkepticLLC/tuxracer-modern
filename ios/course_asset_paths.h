/* Resolve original Tux Racer course assets beside course.tcl.
 * Returned paths are heap-owned, free() by caller.
 * SPDX-License-Identifier: GPL-2.0-or-later */
#ifndef TUX_IOS_COURSE_ASSET_PATHS_H
#define TUX_IOS_COURSE_ASSET_PATHS_H
int tux_course_asset_paths(const char *course_tcl, const char *elev_name,
                           const char *terrain_name, char **elev_path,
                           char **terrain_path);
#endif
