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
#include "audio.h"
#include "game_config.h"
#include "multiplayer.h"
#include "gl_util.h"
#include "fps.h"
#include "render_util.h"
#include "phys_sim.h"
#include "view.h"
#include "course_render.h"
#include "tux.h"
#include "tux_shadow.h"
#include "keyboard.h"
#include "loop.h"
#include "fog.h"
#include "viewfrustum.h"
#include "hud.h"
#include "game_logic_util.h"
#include "fonts.h"
#include "ui_mgr.h"
#include "joystick.h"
#include "part_sys.h"
#ifdef __APPLE__
#include "renderer_metal.h"
#endif

#define NEXT_MODE RACE_SELECT

static bool_t aborted = False;
static bool_t race_won = False;

static void mouse_cb( int button, int state, int x, int y )
{
    set_game_mode( NEXT_MODE );
    winsys_post_redisplay();
}


/*---------------------------------------------------------------------------*/
/*! 
  Draws the text for the game over screen
  \author  jfpatry
  \date    Created:  2000-09-24
  \date    Modified: 2000-09-24
*/
void draw_game_over_text( void )
{
    int w = getparam_x_resolution();
    int h = getparam_y_resolution();
    int x_org, y_org;
    int box_width, box_height;
    char *string;
    int string_w, asc, desc;
    char buff[BUFF_LEN];
    font_t *font;
    font_t *stat_label_font;
    player_data_t *plyr = get_player_data( local_player() );

    box_width = 200;
    box_height = 250;

    x_org = w/2.0 - box_width/2.0;
    y_org = h/2.0 - box_height/2.0;

    if ( !get_font_binding( "race_over", &font ) ) {
	print_warning( IMPORTANT_WARNING,
		       "Couldn't get font for binding race_over" );
    } else {
	string = "Race Over";
	get_font_metrics( font, string, &string_w, &asc, &desc );
	
	glPushMatrix();
	{
	    glTranslatef( x_org + box_width/2.0 - string_w/2.0,
			  y_org + box_height - asc, 
			  0 );
	    bind_font_texture( font );
	    draw_string( font, string );
	}
	glPopMatrix();
    }

    /* If race was aborted, don't print stats */
    if ( !g_game.race_aborted ) {
	if ( !get_font_binding( "race_stats_label", &stat_label_font ) ||
	     !get_font_binding( "race_stats", &font ) )
	{
	    print_warning( IMPORTANT_WARNING,
			   "Couldn't get fonts for race stats" );
	} else {
	    int asc2;
	    int desc2;
	    get_font_metrics( font, "", &string_w, &asc, &desc );
	    get_font_metrics( stat_label_font, "", &string_w, &asc2, &desc2 );
	
	    if ( asc < asc2 ) {
		asc = asc2;
	    }
	    if ( desc < desc2 ) {
		desc = desc2;
	    }

	    glPushMatrix();
	    {
		int minutes;
		int seconds;
		int hundredths;

		glTranslatef( x_org,
			      y_org + 150,
			      0 );

		bind_font_texture( stat_label_font );
		draw_string( stat_label_font, "Time: " );

		get_time_components( g_game.time, &minutes, &seconds, &hundredths );

		sprintf( buff, "%02d:%02d.%02d", minutes, seconds, hundredths );

		bind_font_texture( font );
		draw_string( font, buff );
	    }
	    glPopMatrix();

	    glPushMatrix();
	    {
		glTranslatef( x_org,
			      y_org + 150 - (asc + desc),
			      0 );

		bind_font_texture( stat_label_font );
		draw_string( stat_label_font, "Herring: " );

		sprintf( buff, "%3d", plyr->herring );

		bind_font_texture( font );
		draw_string( font, buff );
	    }
	    glPopMatrix();

	    glPushMatrix();
	    {
		glTranslatef( x_org,
			      y_org + 150 - 2*(asc + desc),
			      0 );

		bind_font_texture( stat_label_font );
		draw_string( stat_label_font, "Score: " );

		sprintf( buff, "%6d", plyr->score );

		bind_font_texture( font );
		draw_string( font, buff );
	    }
	    glPopMatrix();
	}
    }

    if ( g_game.race_aborted ) {
	string = "Race aborted.";
    } else if ( ( g_game.practicing || is_current_cup_complete() ) &&
		did_player_beat_best_results() ) 
    {
	string = "You beat your best score!";
    } else if ( g_game.practicing || is_current_cup_complete() ) {
	string = "";
    } else if ( race_won && is_current_race_last_race_in_cup() ) {
	string = "Congratulations! You won the cup!";
    } else if ( race_won ) {
	string = "You advanced to the next race!";
    } else {
	string = "You didn't advance.";
    }

    if ( !get_font_binding( "race_result_msg", &font ) ) {
	print_warning( IMPORTANT_WARNING, 
		       "Couldn't get font for binding race_result_msg" );
    } else {
	get_font_metrics( font, string, &string_w, &asc, &desc );
	glPushMatrix();
	{
	    glTranslatef( x_org + box_width/2. - string_w/2.,
			  y_org + desc,
			  0 );
	    bind_font_texture( font );
	    draw_string( font, string );
	}
	glPopMatrix();
    }
}

void game_over_init(void) 
{
    winsys_set_display_func( main_loop );
    winsys_set_idle_func( main_loop );
    winsys_set_reshape_func( reshape );
    winsys_set_mouse_func( mouse_cb );
    winsys_set_motion_func( ui_event_motion_func );
    winsys_set_passive_motion_func( ui_event_motion_func );

    halt_sound( "flying_sound" );
    halt_sound( "rock_sound" );
    halt_sound( "ice_sound" );
    halt_sound( "snow_sound" );

    play_music( "game_over" );

    aborted = g_game.race_aborted;

    if ( !aborted ) {
	update_player_score( get_player_data( local_player() ) );
    }

    if ( !g_game.practicing ) {
	race_won = was_current_race_won();
    }
}

void game_over_loop( scalar_t time_step )
{
    player_data_t *plyr = get_player_data( local_player() );
    int width=getparam_x_resolution(),height=getparam_y_resolution();
    int minutes,seconds,hundredths;
    char time_text[32];
    const char *headline;
    const char *message;
    (void)time_step;
    update_audio();

    get_time_components( g_game.time, &minutes, &seconds, &hundredths );
    snprintf(time_text,sizeof(time_text),"%02d:%02d.%02d",minutes,seconds,hundredths);
    if(g_game.race_aborted){headline="RACE ABORTED";message="RETURN TO COURSE SELECT";}
    else if(race_won){headline="RACE COMPLETE";message=is_current_race_last_race_in_cup()?"CUP COMPLETE":"NEXT RACE UNLOCKED";}
    else{headline="RACE COMPLETE";message="TRY AGAIN";}

#ifdef __APPLE__
    if(renderer_metal_begin_menu_frame(width,height)){
        renderer_metal_draw_results_menu(headline,message,time_text,
                                         plyr->herring,plyr->score);
        renderer_metal_end_menu_frame();
    }
#else
    clear_rendering_context();
    set_gl_options(GUI);ui_setup_display();draw_game_over_text();
    reshape(width,height);winsys_swap_buffers();
#endif
}

START_KEYBOARD_CB( game_over_cb )
{
    if ( release ) return;
    set_game_mode( NEXT_MODE );
    winsys_post_redisplay();
}
END_KEYBOARD_CB

void game_over_register()
{
    int status = 0;

    status |= add_keymap_entry( GAME_OVER, 
				DEFAULT_CALLBACK, NULL, NULL, game_over_cb );

    check_assertion( status == 0, "out of keymap entries" );

    register_loop_funcs( GAME_OVER, game_over_init, game_over_loop, NULL );
}


