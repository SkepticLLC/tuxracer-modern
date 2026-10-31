#include "input_mapping.h"
#include <assert.h>
#include <math.h>
#include <stdio.h>
int main(void){
 assert(tux_screen_steer_to_world(-1)==1);
 assert(tux_screen_steer_to_world(1)==-1);
 assert(tux_screen_steer_to_world(0)==0);
 assert(tux_tilt_to_screen(0,3.4f)==0);
 assert(tux_tilt_to_screen(.4f,3.4f)==1);
 assert(tux_tilt_to_screen(-.4f,3.4f)==-1);
 puts("PASS: correct on-screen left/right steering, tilt calibration and deadzone");
 return 0;
}
