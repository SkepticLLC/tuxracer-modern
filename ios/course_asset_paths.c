/* Course data path resolution shared by simulator and host tests. */
#include "course_asset_paths.h"
#include <stdlib.h>
#include <string.h>
#include <stdint.h>
#include <stddef.h>
#include <stdio.h>

static int valid_filename(const char *name){
    if(!name||!*name||strstr(name,".."))return 0;
    for(const char *p=name;*p;p++)
        if(*p=='/'||*p=='\\'||*p==':'||*p=='\n'||*p=='\r')return 0;
    return 1;
}
static char *sibling(const char *course_tcl,size_t directory_size,const char *filename){
    size_t n=strlen(filename);
    if(directory_size>SIZE_MAX-n-2)return NULL;
    char *out=(char *)malloc(directory_size+n+2);
    if(!out)return NULL;
    memcpy(out,course_tcl,directory_size);
    out[directory_size]='/';
    memcpy(out+directory_size+1,filename,n+1);
    return out;
}
int tux_course_asset_paths(const char *course_tcl,const char *elev_name,
                           const char *terrain_name,char **elev_path,
                           char **terrain_path){
    if(!elev_path||!terrain_path)return 0;
    *elev_path=NULL;*terrain_path=NULL;
    if(!course_tcl||!valid_filename(elev_name)||!valid_filename(terrain_name))
        return 0;
    const char *slash=strrchr(course_tcl,'/');
    if(!slash||slash==course_tcl||strcmp(slash+1,"course.tcl")!=0)return 0;
    size_t directory_size=(size_t)(slash-course_tcl);
    char *e=sibling(course_tcl,directory_size,elev_name);
    char *t=sibling(course_tcl,directory_size,terrain_name);
    if(!e||!t){free(e);free(t);return 0;}
    *elev_path=e;*terrain_path=t;
    return 1;
}
