#include "../src/platform/mobile_input.h"
#include <assert.h>
int main(void) {
    tux_mobile_input state;
    tux_mobile_input_reset(&state);
    assert(state.steering == 0.0f && !state.jump);
    tux_mobile_input_set_steering(&state, 2.0f);
    assert(state.steering == 1.0f);
    tux_mobile_input_set_steering(&state, -2.0f);
    assert(state.steering == -1.0f);
    tux_mobile_input_set_buttons(&state, 1, 0, 1, 0, 1);
    assert(state.accelerate && state.jump && state.pause && !state.brake);
    tux_mobile_input_reset(&state);
    assert(state.steering == 0.0f && !state.jump);
    return 0;
}
