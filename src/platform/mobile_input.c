#include "mobile_input.h"
#include <string.h>
void tux_mobile_input_reset(tux_mobile_input *state) {
    if (state) memset(state, 0, sizeof(*state));
}
void tux_mobile_input_set_steering(tux_mobile_input *state, float value) {
    if (!state) return;
    if (value < -1.0f) value = -1.0f;
    if (value > 1.0f) value = 1.0f;
    state->steering = value;
}
void tux_mobile_input_set_buttons(tux_mobile_input *state, int accelerate, int brake, int jump, int trick, int pause) {
    if (!state) return;
    state->accelerate = accelerate != 0;
    state->brake = brake != 0;
    state->jump = jump != 0;
    state->trick = trick != 0;
    state->pause = pause != 0;
}
