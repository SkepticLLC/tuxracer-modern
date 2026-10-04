/* 
 * Tux Racer 
 * Copyright (C) 1999-2001 Jasmin F. Patry
 * 
 * This program is free software; you can redistribute it and/or
 * modify it under the terms of the GNU General Public License
 * as published by the Free Software Foundation; either version 2
 * of the License, or (at your option) any later version.
 * 
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 * 
 * You should have received a copy of the GNU General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA  02111-1307, USA.
 */

#include "tuxracer.h"
#include "joystick.h"

#if defined( HAVE_SDL ) && defined( HAVE_SDL_JOYSTICKOPEN )

#include <SDL2/SDL.h>
#include <SDL2/SDL_joystick.h>

static SDL_Joystick *joystick = NULL;
static int num_buttons = 0;
static int num_axes = 0;
static SDL_JoystickID joystick_instance_id = -1;

void init_joystick()
{
    int num_joysticks = 0;
    const char *js_name;

    /* SDL video may already be initialized. Initialize only the joystick
       subsystem here so subsystem lifetime remains independent. */
    if ( !( SDL_WasInit( SDL_INIT_JOYSTICK ) & SDL_INIT_JOYSTICK ) &&
         SDL_InitSubSystem( SDL_INIT_JOYSTICK ) < 0 ) {
        handle_error( 1, "Couldn't initialize SDL joystick subsystem: %s", SDL_GetError() );
    }

    SDL_JoystickEventState( SDL_ENABLE );

    num_joysticks = SDL_NumJoysticks();

    print_debug( DEBUG_JOYSTICK, "Found %d joysticks", num_joysticks );

    if ( num_joysticks == 0 ) {
	joystick = NULL;
	return;
    }

    js_name = SDL_JoystickNameForIndex( 0 );

    print_debug( DEBUG_JOYSTICK, "Using joystick `%s'", js_name );

    joystick = SDL_JoystickOpen( 0 );

    if ( joystick == NULL ) {
	print_debug( DEBUG_JOYSTICK, "Cannot open joystick" );
	return;
    }

    joystick_instance_id = SDL_JoystickInstanceID( joystick );

    /* Get number of buttons */
    num_buttons = SDL_JoystickNumButtons( joystick );
    print_debug( DEBUG_JOYSTICK, "Joystick has %d button%s", 
		 num_buttons, num_buttons == 1 ? "" : "s" );

    /* Get number of axes */
    num_axes = SDL_JoystickNumAxes( joystick );
    print_debug( DEBUG_JOYSTICK, "Joystick has %d ax%ss", 
		 num_axes, num_axes == 1 ? "i" : "e" );

}

void shutdown_joystick()
{
    if ( joystick != NULL ) {
        SDL_JoystickClose( joystick );
        joystick = NULL;
    }
    joystick_instance_id = -1;
    num_buttons = 0;
    num_axes = 0;
    if ( SDL_WasInit( SDL_INIT_JOYSTICK ) ) {
        SDL_QuitSubSystem( SDL_INIT_JOYSTICK );
    }
}

void handle_joystick_device_event( int added, int which )
{
    if ( added ) {
        if ( joystick == NULL ) {
            init_joystick();
        }
    } else if ( joystick != NULL && joystick_instance_id == (SDL_JoystickID)which ) {
        SDL_JoystickClose( joystick );
        joystick = NULL;
        joystick_instance_id = -1;
        num_buttons = 0;
        num_axes = 0;
        if ( SDL_NumJoysticks() > 0 ) {
            init_joystick();
        }
    }
}

bool_t is_joystick_active()
{
    return (bool_t) ( joystick != NULL );
}

void update_joystick()
{
    SDL_JoystickUpdate();
}

scalar_t get_joystick_x_axis()
{
    static bool_t warning_given = False;
    int axis;

    check_assertion( joystick != NULL,
		     "joystick is null" );

    axis = getparam_joystick_x_axis();

    /* Make sure axis is valid */
    if ( axis >= num_axes || axis < 0 ) {

	if ( !warning_given ) {
	    print_warning( IMPORTANT_WARNING, 
			   "joystick x axis mapped to axis %d "
			   "but joystick only has %d axes", axis, num_axes );
	    warning_given = True;
	}

	return 0.0;
    }

    return SDL_JoystickGetAxis( joystick, axis )/32768.0;
}

scalar_t get_joystick_y_axis()
{
    static bool_t warning_given = False;
    int axis;

    check_assertion( joystick != NULL,
		     "joystick is null" );

    axis = getparam_joystick_y_axis();

    /* Make sure axis is valid */
    if ( axis >= num_axes || axis < 0 ) {

	if ( !warning_given ) {
	    print_warning( IMPORTANT_WARNING, 
			   "joystick y axis mapped to axis %d "
			   "but joystick only has %d axes", axis, num_axes );
	    warning_given = True;
	}

	return 0.0;
    }

    return SDL_JoystickGetAxis( joystick, getparam_joystick_y_axis() )/32768.0;
}

bool_t is_joystick_button_down( int button ) 
{
    static bool_t warning_given = False;

    check_assertion( joystick != NULL,
		     "joystick is null" );

    check_assertion( button >= 0, "button is negative" );

    if ( button >= num_buttons ) {
	if ( !warning_given ) {
	    print_warning( IMPORTANT_WARNING,
			   "state of button %d requested, but "
			   "joystick only has %d buttons.  Further warnings "
			   "of this type will be suppressed", 
			   button, num_buttons );
	    warning_given = True;
	}
	return False;
    }

    return (bool_t) SDL_JoystickGetButton( joystick, button );
}

bool_t is_joystick_continue_button_down()
{
    if ( joystick == NULL ) {
	return False;
    }

    if ( getparam_joystick_continue_button() < 0 ) {
	return False;
    }

    return is_joystick_button_down( getparam_joystick_continue_button() );
}

#else

/* Stub functions */

void init_joystick()
{
}

void shutdown_joystick()
{
}

void handle_joystick_device_event( int added, int which )
{
}

bool_t is_joystick_active()
{
    return False;
}

void update_joystick()
{
}

scalar_t get_joystick_x_axis()
{
    return 0.0;
}

scalar_t get_joystick_y_axis()
{
    return 0.0;
}

bool_t is_joystick_button_down( int button ) 
{
    return False;
}

bool_t is_joystick_continue_button_down()
{
    return False;
}

#endif

/* EOF */
