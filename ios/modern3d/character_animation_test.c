#include "character_animation.h"
#include <assert.h>
#include <math.h>
#include <stdio.h>
int main(void){
 TuxPose idle=tux_pose(0,12,0,0,0);
 assert(!idle.airborne && fabsf(idle.lean)<.001f);
 TuxPose left=tux_pose(.2f,22,-1,0,0);
 TuxPose right=tux_pose(.2f,22,1,0,0);
 assert(left.lean>0 && right.lean<0);
 TuxPose airborne=tux_pose(.4f,22,1,1.2f,5);
 assert(airborne.airborne && airborne.flap>.5f && airborne.pitch>0);
 TuxPose fall=tux_pose(.4f,22,0,1.2f,-5);
 assert(fall.pitch<0);
 puts("PASS: carving lean, flipper animation, airborne pitch and grounded pose");
 return 0;
}
