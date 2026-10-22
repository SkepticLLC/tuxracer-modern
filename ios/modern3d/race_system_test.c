/* Standalone gameplay regression checks — no Xcode or SDL required. */
#include "race_system.h"
#include <assert.h>
#include <math.h>
#include <stdio.h>
int main(void){
 RaceConfig cfg={600,62,11,30,20,38,150,8241};
 RaceState race={0};
 race_reset(&race,&cfg);
 assert(race.phase==RACE_RUNNING && race.speed==11);
 float x1,z1,x2,z2;
 race_object_at(&cfg,1,5,&x1,&z1);
 race_object_at(&cfg,1,5,&x2,&z2);
 assert(x1==x2 && z1==z2 && z1>0);
 assert(race_objects_count(&cfg,1)>0);
 for(int i=0;i<100;i++)race_step(&race,&cfg,(RaceInput){0},.016f);
 assert(race.distance>0 && race.speed>11 && race.phase==RACE_RUNNING);
 race_step(&race,&cfg,(RaceInput){.5f,1,0,0,0},.1f);
 assert(race.speed<=cfg.maximum_speed);
 race_reset(&race,&cfg);
 race_step(&race,&cfg,(RaceInput){0,0,1,0,0},.03f);
 assert(race.jump_height>0 && race.vertical_velocity>0);
 for(int i=0;i<200;i++)race_step(&race,&cfg,(RaceInput){0},.015f);
 assert(race.jump_height==0);
 /* Exact step crossing a fish in the seeded course. */
 race_reset(&race,&cfg);
 race_object_at(&cfg,1,0,&x1,&z1);
 race.lateral=x1;
 race.distance=z1-.2f;
 race.speed=25;
 race_step(&race,&cfg,(RaceInput){0},.05f);
 assert(race.fish==1);
 /* Pause stops the simulation; resume continues. */
 race_step(&race,&cfg,(RaceInput){0,0,0,0,1},.04f);
 assert(race.phase==RACE_PAUSED);
 float frozen=race.distance;
 race_step(&race,&cfg,(RaceInput){0,0,0,0,0},.04f);
 assert(race.distance==frozen);
 race_step(&race,&cfg,(RaceInput){0,0,0,0,1},.04f);
 assert(race.phase==RACE_RUNNING);
 /* Finish stays finished until explicitly restarted. */
 race.distance=cfg.length-.02f;
 race.speed=15;
 race_step(&race,&cfg,(RaceInput){0},.04f);
 assert(race.phase==RACE_FINISHED && race.distance==cfg.length);
 float time=race.time_seconds;
 race_step(&race,&cfg,(RaceInput){0},.04f);
 assert(race.time_seconds==time);
 race_step(&race,&cfg,(RaceInput){0,0,0,1,0},0);
 assert(race.phase==RACE_RUNNING && race.distance==0);
 puts("PASS: seeded fish, deterministic placement, jump/land, pause, finish and restart");
 return 0;
}
