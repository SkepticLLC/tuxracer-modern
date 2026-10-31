/* Clean-slate downhill gameplay, deterministic fixed-step simulation.
 * No SDL, UIKit or Metal dependency; desktop-testable.
 * SPDX-License-Identifier: GPL-2.0-or-later */
#ifndef TUX_IOS_RACE_SYSTEM_H
#define TUX_IOS_RACE_SYSTEM_H
#include <stdint.h>
typedef enum {RACE_READY=0,RACE_RUNNING=1,RACE_FINISHED=2,RACE_PAUSED=3} RacePhase;
typedef struct {
 float length, width, starting_speed, maximum_speed;
 float fish_spacing, tree_spacing, checkpoint_spacing;
 unsigned seed;
} RaceConfig;
typedef struct {
 float steer;
 int brake,jump,restart,pause;
} RaceInput;
typedef struct {
 RacePhase phase;
 float distance,lateral,speed,time_seconds;
 float vertical_velocity,jump_height,steer_visual,lateral_velocity;
 float fish_flash,hit_flash,landing_flash;
 int fish,hits,checkpoints;
 uint64_t collected_fish_mask;
 int previous_pause;
 unsigned previous_jump;
} RaceState;
void race_reset(RaceState *race,const RaceConfig *cfg);
void race_step(RaceState *race,const RaceConfig *cfg,RaceInput input,float seconds);
/* The first 64 placed fish retain their collected state throughout a race. */
int race_fish_collected(const RaceState *race,int index);
/* Deterministic original course object positions from seed, not legacy art. */
int race_objects_count(const RaceConfig *cfg,int fish);
void race_object_at(const RaceConfig *cfg,int fish,int index,float *x,float *z);
#endif
