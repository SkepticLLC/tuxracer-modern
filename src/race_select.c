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
#include "race_select.h"
#include "ui_mgr.h"
#include "ui_theme.h"
#include "button.h"
#include "ssbutton.h"
#include "listbox.h"
#include "loop.h"
#include "render_util.h"
#include "audio.h"
#include "gl_util.h"
#include "keyboard.h"
#include "multiplayer.h"
#include "course_load.h"
#include "fonts.h"
#include "textures.h"
#include "course_mgr.h"
#include "textarea.h"
#include "save.h"
#include "game_logic_util.h"
#include "ui_snow.h"
#include "joystick.h"

static textarea_t *desc_ta = NULL;
static listbox_t *race_listbox = NULL;
static button_t  *back_btn = NULL;
static button_t  *start_btn = NULL;
static ssbutton_t *conditions_ssbtn = NULL;
static ssbutton_t *snow_ssbtn = NULL;
static ssbutton_t *wind_ssbtn = NULL;
static ssbutton_t *mirror_ssbtn = NULL;
static list_elem_t cur_elem = NULL;
static bool_t cup_complete = False; /* has this cup been completed? */
static list_elem_t last_completed_race = NULL; /* last race that's been won */
static event_data_t *event_data = NULL;
static cup_data_t *cup_data = NULL;
static list_t race_list = NULL;
static player_data_t *plyr = NULL;

/* Forward declaration */
static void race_select_loop( scalar_t time_step )
{
    (void)time_step;
    check_gl_error();
    update_audio();
    set_gl_options( GUI );
    clear_rendering_context();
    ui_setup_display();
    modern_draw_race_select();
    reshape( getparam_x_resolution(), getparam_y_resolution() );
    winsys_swap_buffers();
}


/*---------------------------------------------------------------------------*/
/*! 
  Mode termination function
static void race_select_term(void)
{
    if ( back_btn ) {
	button_delete( back_btn );
    }
    back_btn = NULL;

    if ( start_btn ) {
	button_delete( start_btn );
    }
    start_btn = NULL;

    if ( race_listbox ) {
	listbox_delete( race_listbox );
    }
    race_listbox = NULL;

    if ( conditions_ssbtn ) {
	ssbutton_delete( conditions_ssbtn );
    }
    conditions_ssbtn = NULL;

    if ( snow_ssbtn ) {
	ssbutton_delete( snow_ssbtn );
    }
    snow_ssbtn = NULL;

    if ( wind_ssbtn ) {
	ssbutton_delete( wind_ssbtn );
    }
    wind_ssbtn = NULL;

    if ( mirror_ssbtn ) {
	ssbutton_delete( mirror_ssbtn );
    }
    mirror_ssbtn = NULL;

    textarea_delete( desc_ta );
    desc_ta = NULL;
}


/*---------------------------------------------------------------------------*/
/*! 
  Advances to the next race condition
  \author  jfpatry
  \date    Created:  2000-09-30
  \date    Modified: 2000-09-30
*/
void next_race_condition( void )
{
    if ( conditions_ssbtn ) {
	ssbutton_simulate_mouse_click( conditions_ssbtn );
    }
}


/*---------------------------------------------------------------------------*/
/*! 
  Toggles the mirrored state of the course
  \author  jfpatry
  \date    Created:  2000-09-30
  \date    Modified: 2000-09-30
*/
void toggle_mirror( void )
{
    if ( mirror_ssbtn ) {
	ssbutton_simulate_mouse_click( mirror_ssbtn );
    }
}


/*---------------------------------------------------------------------------*/
/*! 
  Toggles the windy state of the course
  \author  jfpatry
  \date    Created:  2000-09-30
  \date    Modified: 2000-09-30
*/
void toggle_wind( void )
{
    if ( wind_ssbtn ) {
	ssbutton_simulate_mouse_click( conditions_ssbtn );
    }
}


START_KEYBOARD_CB( race_select_key_cb )
{
    if ( release ) {
	return;
    }

    if ( special ) {
	switch (key) {
	case WSK_UP:
	case WSK_LEFT:
	    if ( race_listbox ) {
		listbox_goto_prev_item( race_listbox );
	    }
	    break;
	case WSK_RIGHT:
	case WSK_DOWN:
	    if ( race_listbox ) {
		listbox_goto_next_item( race_listbox );
	    }
	    break;
	}
    } else {
	key = (int) tolower( (char) key );

	switch (key) {
	case 13: /* Enter */
	    if ( start_btn ) {
		button_simulate_mouse_click( start_btn );
		ui_set_dirty();
	    }
	    break;
	case 27: /* Esc */
	    if ( back_btn ) {
		button_simulate_mouse_click( back_btn );
		ui_set_dirty();
	    }
	    break;
	case 'c': 
	    next_race_condition();
	    break;
	case 'w': 
	    toggle_wind();
	    break;
	case 'm':
	    toggle_mirror();
	    break;
	case 's':
	    /* XXX snow disabled for now */
	    break;
	}
    }

    ui_check_dirty();
}
END_KEYBOARD_CB


/*---------------------------------------------------------------------------*/
/*! 
  Mode registration function
  \author  jfpatry
  \date    Created:  2000-09-24
  \date    Modified: 2000-09-24
*/
void race_select_register()
{
    int status = 0;

    status |= 
	add_keymap_entry( RACE_SELECT,
			  DEFAULT_CALLBACK, NULL, NULL, race_select_key_cb );

    check_assertion( status == 0,
		     "out of keymap entries" );

    register_loop_funcs( RACE_SELECT, 
			 race_select_init,
			 race_select_loop,
			 race_select_term );
}


/* EOF */
