#include "input_mapping.h"
#include <math.h>
static float clampf(float a,float lo,float hi){return a<lo?lo:a>hi?hi:a;}
float tux_screen_steer_to_world(float screen_direction){
    /* Camera basis: +worldX appears on left of the screen. */
    return -clampf(screen_direction,-1.0f,1.0f);
}
float tux_tilt_to_screen(float relative_gravity,float sensitivity){
    /* Calibrated gravity difference, rather than absolute phone angle. */
    float t=relative_gravity*sensitivity;
    if(fabsf(t)<.085f)return 0.0f;
    return clampf(t,-1.0f,1.0f);
}
