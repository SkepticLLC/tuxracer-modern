/* Test original course loader on typical Tux Racer Tcl metadata.
 * Compile/run with: sh ios/test-original-course.sh
 */
#include "original_course.h"
#include <stdio.h>
#include <string.h>
#include <math.h>
int main(int argc,char **argv) {
    if(argc!=2) return 2;
    tux_original_course course;
    if(!tux_original_course_load(argv[1],&course)){
        fprintf(stderr,"Could not load original Bunny Hill course metadata\n");
        return 1;
    }
    if(strcmp(course.name,"Bunny Hill")!=0 ||
       fabsf(course.width_m-90.0f)>0.01f ||
       fabsf(course.length_m-480.0f)>0.01f ||
       fabsf(course.play_length_m-470.0f)>0.01f ||
       fabsf(course.angle_deg-25.0f)>0.01f ||
       strcmp(course.elevation_file,"elev.rgb")!=0 ||
       strcmp(course.terrain_file,"terrain.rgb")!=0) {
        fprintf(stderr,"Unexpected parsed original course: %s (%.1fx%.1f)\n",
                course.name,course.width_m,course.length_m);
        return 1;
    }
    printf("PASS: unmodified original Bunny Hill Tcl data: %s %.0fx%.0fm, %.0fm playable, %.0f degrees\n",
           course.name,course.width_m,course.length_m,
           course.play_length_m,course.angle_deg);
    return 0;
}
