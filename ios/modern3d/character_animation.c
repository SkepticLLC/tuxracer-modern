#include "character_animation.h"
#include <math.h>
static float bound(float a,float lo,float hi){return a<lo?lo:a>hi?hi:a;}
TuxPose tux_pose(float t,float speed,float steer,float height,float velocity){
 TuxPose p={0};
 float s=bound(steer,-1.0f,1.0f);
 p.airborne=height>.04f;
 p.lean=-s*.30f;
 p.bob=p.airborne?0:.025f*sinf(t*(6.0f+speed*.20f));
 p.flap=p.airborne?(.65f+.14f*sinf(t*11.0f)):(.06f*sinf(t*7.0f));
 p.pitch=p.airborne?bound(velocity*.055f,-.25f,.28f):-.07f;
 p.scarfWave=.18f*sinf(t*9.0f)+s*.16f;
 p.spin=0;
 return p;
}
