/* Screen-oriented racing controls. Pure C for host regression tests.
 * The chase camera's X axis is reversed relative to projected screen X.
 */
#ifndef TUX_INPUT_MAPPING_H
#define TUX_INPUT_MAPPING_H
float tux_screen_steer_to_world(float screen_direction);
float tux_tilt_to_screen(float relative_gravity, float sensitivity);
#endif
