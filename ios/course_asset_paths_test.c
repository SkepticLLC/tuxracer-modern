#include "course_asset_paths.h"
#include <stdlib.h>
#include <stdio.h>
#include <string.h>
int main(void){
    const char *course="/Users/Someone/Library/Developer/CoreSimulator/Devices/0A6C676A/data/Containers/Bundle/Application/522241E4/TuxRacerModernIOS.app/data/courses/bunny_hill/course.tcl";
    const char *dir="/Users/Someone/Library/Developer/CoreSimulator/Devices/0A6C676A/data/Containers/Bundle/Application/522241E4/TuxRacerModernIOS.app/data/courses/bunny_hill/";
    char *e=NULL,*t=NULL;
    if(!tux_course_asset_paths(course,"elev.rgb","terrain.rgb",&e,&t)){
        fputs("FAIL: valid course path rejected\n",stderr);return 1;
    }
    size_t n=strlen(dir);
    if(strncmp(e,dir,n)!=0||strcmp(e+n,"elev.rgb")!=0||
       strncmp(t,dir,n)!=0||strcmp(t+n,"terrain.rgb")!=0||
       strlen(e)<100||strlen(t)<100){
        fprintf(stderr,"FAIL: truncated/corrupt paths elevation=%s terrain=%s\n",e,t);
        free(e);free(t);return 1;
    }
    free(e);free(t);
    if(tux_course_asset_paths(course,"../elev.rgb","terrain.rgb",&e,&t)||
       tux_course_asset_paths(course,"elev.rgb","/terrain.rgb",&e,&t)||
       tux_course_asset_paths("/tmp/other.tcl","elev.rgb","terrain.rgb",&e,&t)){
        fputs("FAIL: unsafe/invalid path accepted\n",stderr);return 1;
    }
    puts("PASS: long simulator bundle paths preserved; elevation and terrain sibling resolution; unsafe filenames rejected");
    return 0;
}
