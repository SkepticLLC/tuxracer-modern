/* Deterministic character pose; no graphics or platform dependencies. */
#ifndef TUX_CHARACTER_ANIMATION_H
#define TUX_CHARACTER_ANIMATION_H
typedef struct {
 float lean,flap,bob,pitch,scarfWave,spin;
 int airborne;
} TuxPose;
TuxPose tux_pose(float time_seconds,float speed,float steer,float jump_height,
                 float vertical_velocity);
#endif
