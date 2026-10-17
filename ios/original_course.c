/*
 * Minimal read-only parser of original Tux Racer course.tcl declarations.
 * Preserves the original data files; does not interpret arbitrary Tcl.
 * SPDX-License-Identifier: GPL-2.0-or-later
 */
#include "original_course.h"
#include <stdio.h>
#include <string.h>
#include <ctype.h>

static void clean_value(char *value) {
    size_t n;
    char *comment = strchr(value, ';');
    if (comment) *comment = 0;
    n = strlen(value);
    while (n && isspace((unsigned char)value[n-1])) value[--n] = 0;
    while (*value && isspace((unsigned char)*value))
        memmove(value, value+1, strlen(value));
    n = strlen(value);
    if (n >= 2 && ((value[0] == '"' && value[n-1] == '"') ||
                   (value[0] == '{' && value[n-1] == '}'))) {
        memmove(value, value+1, n-2);
        value[n-2] = 0;
    }
}
int tux_original_course_load(const char *path, tux_original_course *out) {
    if (!path || !out) return 0;
    FILE *file = fopen(path, "rb");
    if (!file) return 0;
    tux_original_course result = {0};
    int got_dim=0, got_name=0, got_elev=0, got_terrain=0;
    char line[512], key[80], value[400];
    while (fgets(line, sizeof(line), file)) {
        char *p=line;
        while (*p && isspace((unsigned char)*p)) ++p;
        if (*p=='#' || !*p) continue;
        if (sscanf(p, "%79s", key) != 1) continue;
        p+=strlen(key);
        while (*p && isspace((unsigned char)*p)) ++p;
        if (strcmp(key,"tux_course_name")==0) {
            snprintf(value,sizeof(value),"%s",p);clean_value(value);
            if (strlen(value)<sizeof(result.name)) {
                strcpy(result.name,value);got_name=1;
            }
        } else if (strcmp(key,"tux_course_dim")==0) {
            got_dim=sscanf(p,"%f %f %f %f",
                &result.width_m,&result.length_m,
                &result.play_width_m,&result.play_length_m)==4;
        } else if (strcmp(key,"tux_start_pt")==0) {
            sscanf(p,"%f %f",&result.start_x_m,&result.start_z_m);
        } else if (strcmp(key,"tux_angle")==0) {
            sscanf(p,"%f",&result.angle_deg);
        } else if (strcmp(key,"tux_elev_scale")==0) {
            sscanf(p,"%f",&result.elevation_scale);
        } else if (strcmp(key,"tux_elev")==0 || strcmp(key,"tux_terrain")==0) {
            snprintf(value,sizeof(value),"%s",p);clean_value(value);
            if (strlen(value)>0 && strlen(value)<sizeof(result.elevation_file)) {
                if(strcmp(key,"tux_elev")==0){
                    strcpy(result.elevation_file,value);got_elev=1;
                } else {
                    strcpy(result.terrain_file,value);got_terrain=1;
                }
            }
        }
    }
    fclose(file);
    if(!got_dim||!got_name||!got_elev||!got_terrain||
        result.width_m<=0||result.length_m<=0||
        result.play_length_m<=0) return 0;
    *out=result;
    return 1;
}
