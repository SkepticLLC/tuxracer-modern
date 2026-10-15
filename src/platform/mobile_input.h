/* SPDX-License-Identifier: GPL-2.0-or-later */
#ifndef TUX_MOBILE_INPUT_H
#define TUX_MOBILE_INPUT_H
#ifdef __cplusplus
extern "C" {
#endif
typedef struct tux_mobile_input {
    float steering; /* -1 left, +1 right */
    unsigned char accelerate;
    unsigned char brake;
    unsigned char jump;
    unsigned char trick;
    unsigned char pause;
} tux_mobile_input;
void tux_mobile_input_reset(tux_mobile_input *state);
void tux_mobile_input_set_steering(tux_mobile_input *state, float steering);
void tux_mobile_input_set_buttons(tux_mobile_input *state, int accelerate, int brake, int jump, int trick, int pause);
#ifdef __cplusplus
}
#endif
#endif
