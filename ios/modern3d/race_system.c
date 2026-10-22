#include "race_system.h"
#include <math.h>
#include <string.h>
static float clampf(float x,float a,float b){return x<a?a:x>b?b:x;}
static unsigned hash32(unsigned x){
 x^=x>>16;x*=0x7feb352dU;x^=x>>15;x*=0x846ca68bU;x^=x>>16;return x;
}
void race_reset(RaceState *race,const RaceConfig *cfg){
 if(!race||!cfg)return;
 memset(race,0,sizeof(*race));
 race->phase=RACE_RUNNING;
 race->speed=cfg->starting_speed;
}
int race_objects_count(const RaceConfig *cfg,int fish){
 if(!cfg)return 0;
 float spacing=fish?cfg->fish_spacing:cfg->tree_spacing;
 if(spacing<=0)return 0;
 int n=(int)(cfg->length/spacing)-2;
 return n>0?n:0;
}
void race_object_at(const RaceConfig *cfg,int fish,int index,float *x,float *z){
 if(!cfg||!x||!z){return;}
 float spacing=fish?cfg->fish_spacing:cfg->tree_spacing;
 unsigned h=hash32((unsigned)index*747796405U+cfg->seed+(fish?354u:1297u));
 float t=(h&0xFFFF)/65535.0f;
 *z=(index+1)*spacing+6.0f;
 *x=(t*2.0f-1.0f)*cfg->width*(fish?.24f:.40f);
}
void race_step(RaceState *race,const RaceConfig *cfg,RaceInput input,float seconds){
 if(!race||!cfg)return;
 if(input.restart){race_reset(race,cfg);return;}
 if(input.pause&&!race->previous_pause){
   if(race->phase==RACE_RUNNING)race->phase=RACE_PAUSED;
   else if(race->phase==RACE_PAUSED)race->phase=RACE_RUNNING;
 }
 race->previous_pause=input.pause;
 if(race->phase!=RACE_RUNNING)return;
 float dt=clampf(seconds,0,.05f);
 if(dt<=0)return;
 float before=race->distance;
 float acceleration=input.brake?-22.0f:6.0f;
 race->speed=clampf(race->speed+acceleration*dt,4.0f,cfg->maximum_speed);
 float steer=clampf(input.steer,-1.0f,1.0f);
 race->lateral=clampf(race->lateral+steer*dt*(5.0f+race->speed*.4f),
                      -cfg->width*.43f,cfg->width*.43f);
 race->steer_visual+=(steer-race->steer_visual)*clampf(dt*7.0f,0,1);
 if(input.jump&&!race->previous_jump&&race->jump_height<=0.001f){
    race->vertical_velocity=6.0f;
 }
 race->previous_jump=(unsigned)(input.jump!=0);
 if(race->jump_height>0||race->vertical_velocity>0){
    race->jump_height+=race->vertical_velocity*dt;
    race->vertical_velocity-=17.0f*dt;
    if(race->jump_height<=0){race->jump_height=0;race->vertical_velocity=0;}
 }
 race->distance=fminf(cfg->length,race->distance+race->speed*dt);
 race->time_seconds+=dt;
 for(int fish=0;fish<=1;fish++){
    int count=race_objects_count(cfg,fish);
    for(int i=0;i<count;i++){
       float x,z;race_object_at(cfg,fish,i,&x,&z);
       if(z<=before||z>race->distance)continue;
       if(fabsf(x-race->lateral)> (fish?2.7f:2.0f))continue;
       if(fish)race->fish++;
       else if(race->jump_height<1.0f){
          race->hits++;
          race->speed=fmaxf(4.0f,race->speed*.68f);
       }
    }
 }
 if(cfg->checkpoint_spacing>0)
    race->checkpoints=(int)(race->distance/cfg->checkpoint_spacing);
 if(race->distance>=cfg->length)race->phase=RACE_FINISHED;
}
