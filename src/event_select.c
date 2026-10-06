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
#include "event_select.h"
#include "ui_mgr.h"
#include "ui_theme.h"
#include "button.h"
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
#include "save.h"
#include "ui_snow.h"
#include "joystick.h"
#ifdef __APPLE__
#include "renderer_metal.h"
#endif

static listbox_t *event_listbox = NULL;
static listbox_t *cup_listbox = NULL;
static button_t *back_btn = NULL;
static button_t *continue_btn = NULL;
static list_elem_t cur_event = NULL;
static event_data_t *event_data = NULL;
static list_elem_t cur_cup = NULL;

static char* event_list_elem_to_string_func( list_elem_data_t elem )
{
    return get_event_name( (event_data_t*) elem );
}

static char* cup_list_elem_to_string_func( list_elem_data_t elem )
{
    return get_cup_name( (cup_data_t*) elem );
}


/*---------------------------------------------------------------------------*/
/*! 
  Updates the enabled states of the buttons
  \author  jfpatry
  \date    Created:  2000-09-24
  \date    Modified: 2000-09-24
*/
static void update_button_enabled_states( )
{
    if ( continue_btn == NULL ) {
	return;
    }

    if ( is_cup_complete( event_data, cur_cup ) ||
	 is_cup_first_incomplete_cup( event_data, cur_cup ) )
    {
	button_set_enabled( continue_btn, True );
    } else {
	button_set_enabled( continue_btn, False );
    }
}


static void set_cur_cup_to_first_incomplete( event_data_t *event_data,
					     list_t cup_list ) 
{
    cur_cup = get_last_complete_cup_for_event( event_data );
    
    if ( cur_cup == NULL ) {
	cur_cup = get_list_head( cup_list );
    } else if ( cur_cup != get_list_tail( cup_list ) ) {
	cur_cup = get_next_list_elem( cup_list, cur_cup ); 
    }
}

static void event_listbox_item_change_cb( listbox_t *listbox, void *userdata )
{
    list_elem_t cur_event;
    list_t cup_list;

    check_assertion( userdata == NULL, "userdata is not null" );

    cur_event = listbox_get_current_item( listbox );
    event_data = (event_data_t*) get_list_elem_data( cur_event );

    cup_list =  get_event_cup_list( event_data );
    listbox_set_item_list( cup_listbox, cup_list,
			   cup_list_elem_to_string_func );

    set_cur_cup_to_first_incomplete( event_data, cup_list );

    listbox_set_current_item( cup_listbox, cur_cup );

    update_button_enabled_states();

    ui_set_dirty();
}

static void cup_listbox_item_change_cb( listbox_t *listbox, void *userdata )
{
    check_assertion( userdata == NULL, "userdata is not null" );

    cur_cup = listbox_get_current_item( listbox );

    update_button_enabled_states();
}

static void back_click_cb( button_t *button, void *userdata )
{
    check_assertion( userdata == NULL, "userdata is not null" );

    set_game_mode( GAME_TYPE_SELECT );

    ui_set_dirty();
}

static void continue_click_cb( button_t *button, void *userdata )
{
    cup_data_t *cup_data;
    player_data_t *plyr = get_player_data( local_player() );

    check_assertion( userdata == NULL, "userdata is not null" );

    cur_event = listbox_get_current_item( event_listbox );
    event_data = (event_data_t*) get_list_elem_data( cur_event );

    cur_cup = listbox_get_current_item( cup_listbox );
    cup_data = (cup_data_t*) get_list_elem_data( cur_cup );

    g_game.current_event = get_event_name( event_data );
    g_game.current_cup = get_cup_name( cup_data );

    plyr->lives = INIT_NUM_LIVES;

    set_game_mode( RACE_SELECT );

    ui_set_dirty();
}

static void set_widget_positions_and_draw_decorations()
{
    int w = getparam_x_resolution();
    int h = getparam_y_resolution();
    int box_width, box_height, box_max_y;
    int x_org, y_org;
    char *string;
    font_t *font;
    int text_width, asc, desc;
    list_t cup_list;
    GLuint texobj;

    /* set the dimensions of the box in which all widgets should fit */
    box_width = 460;
    box_height = 310;
    box_max_y = h - 128;

    x_org = w/2 - box_width/2;
    y_org = h/2 - box_height/2;
    if ( y_org + box_height > box_max_y ) {
	y_org = box_max_y - box_height;
    }

    button_set_position( 
	back_btn,
	make_point2d( x_org + 131 - button_get_width( back_btn )/2.0,
		      42 ) );

    button_set_position(
	continue_btn,
	make_point2d( x_org + 329 - button_get_width( continue_btn )/2.0,
		      42 ) );

    listbox_set_position( 
	cup_listbox,
	make_point2d( x_org + 52,
		      y_org + 103 ) );

    listbox_set_position( 
	event_listbox,
	make_point2d( x_org + 52,
		      y_org + 193 ) );

    /* 
     * Draw other stuff 
     */

    /* Event & cup icons */
    if ( !get_texture_binding( get_event_icon_texture_binding( event_data ),
			       &texobj ) ) {
	texobj = 0;
    }

    glBindTexture( GL_TEXTURE_2D, texobj );


    glBegin( GL_QUADS );
    {
	point2d_t tll, tur;
	point2d_t ll, ur;

	ll = make_point2d( x_org, y_org + 193 );
	ur = make_point2d( x_org + 44, y_org + 193 + 44 );
	tll = make_point2d( 0, 0 );
	tur = make_point2d( 44.0/64.0, 44.0/64.0 );

	glTexCoord2f( tll.x, tll.y );
	glVertex2f( ll.x, ll.y );

	glTexCoord2f( tur.x, tll.y );
	glVertex2f( ur.x, ll.y );

	glTexCoord2f( tur.x, tur.y );
	glVertex2f( ur.x, ur.y );

	glTexCoord2f( tll.x, tur.y );
	glVertex2f( ll.x, ur.y );
    }
    glEnd();

    if ( !get_texture_binding( 
	get_cup_icon_texture_binding( 
	    (cup_data_t*) get_list_elem_data( cur_cup ) ), &texobj ) ) 
    {
	texobj = 0;
    }

    glBindTexture( GL_TEXTURE_2D, texobj );

    glBegin( GL_QUADS );
    {
	point2d_t tll, tur;
	point2d_t ll, ur;

	ll = make_point2d( x_org, y_org + 103 );
	ur = make_point2d( x_org + 44, y_org + 103 + 44 );
	tll = make_point2d( 0, 0 );
	tur = make_point2d( 44.0/64.0, 44.0/64.0 );

	glTexCoord2f( tll.x, tll.y );
	glVertex2f( ll.x, ll.y );

	glTexCoord2f( tur.x, tll.y );
	glVertex2f( ur.x, ll.y );

	glTexCoord2f( tur.x, tur.y );
	glVertex2f( ur.x, ur.y );

	glTexCoord2f( tll.x, tur.y );
	glVertex2f( ll.x, ur.y );
    }
    glEnd();

    if ( !get_font_binding( "menu_label", &font ) ) {
	print_warning( IMPORTANT_WARNING,
		       "Couldn't get font for binding menu_label" );
    } else {
	bind_font_texture( font );
	string = "Select event and cup";
	get_font_metrics( font, string, &text_width,  &asc, &desc );

	glPushMatrix();
	{
	    glTranslatef( x_org + box_width/2.0 - text_width/2.0,
			  y_org + 310 - asc, 
			  0 );

	    draw_string( font, string );
	}
	glPopMatrix();
    }

    if ( !get_font_binding( "event_and_cup_label", &font ) ) {
	print_warning( IMPORTANT_WARNING,
		       "Couldn't get font for binding menu_label" );
    } else {
	bind_font_texture( font );
	string = "Event:";
	get_font_metrics( font, string, &text_width,  &asc, &desc );

	glPushMatrix();
	{
	    glTranslatef( x_org,
			  y_org + 193 + 44 + 5 + desc, 
			  0 );

	    draw_string( font, string );
	}
	glPopMatrix();

	string = "Cup:";

	glPushMatrix();
	{
	    glTranslatef( x_org,
			  y_org + 103 + 44 + 5 + desc, 
			  0 );

	    draw_string( font, string );
	}
	glPopMatrix();
    }

    cur_event = listbox_get_current_item( event_listbox );
    event_data = (event_data_t*) get_list_elem_data( cur_event );
    cup_list = get_event_cup_list( event_data );
    cur_cup = listbox_get_current_item( cup_listbox );

    if ( is_cup_complete( event_data, cur_cup ) ) {
	string = "You've won this cup!";
    } else if ( is_cup_first_incomplete_cup( event_data, cur_cup ) ) {
	string = "You must complete this cup next";
    } else {
	string = "You cannot enter this cup yet"; 
    }

    if ( !get_font_binding( "cup_status", &font ) ) {
	print_warning( IMPORTANT_WARNING,
		       "Couldn't get font for binding cup_status" );
    } else {
	bind_font_texture( font );

	get_font_metrics( font, string, &text_width, &asc, &desc );

	glPushMatrix();
	{
	    glTranslatef( x_org + box_width/2.0 - text_width/2.0,
			  y_org + 70, 
			  0 );

	    draw_string( font, string );
	}
	glPopMatrix();
    }
}

static int modern_event_focus = 0;

static const char *modern_event_status(void)
{
    if ( event_data == NULL || cur_cup == NULL ) return "";
    if ( is_cup_complete( event_data, cur_cup ) ) return "COMPLETED";
    if ( is_cup_first_incomplete_cup( event_data, cur_cup ) ) return "AVAILABLE";
    return "LOCKED";
}

static void modern_event_sync(void)
{
    list_t cup_list;
    if ( cur_event == NULL ) return;
    event_data = (event_data_t*)get_list_elem_data( cur_event );
    cup_list = get_event_cup_list( event_data );
    if ( cur_cup == NULL ) set_cur_cup_to_first_incomplete( event_data, cup_list );
}

static void modern_event_move_event(int direction)
{
    list_t events = get_events_list();
    list_t cups;
    list_elem_t next;
    if ( cur_event == NULL ) cur_event = get_list_head( events );
    next = direction < 0 ? get_prev_list_elem( events, cur_event )
                         : get_next_list_elem( events, cur_event );
    if ( next == NULL ) next = direction < 0 ? get_list_tail( events )
                                              : get_list_head( events );
    cur_event = next;
    event_data = (event_data_t*)get_list_elem_data( cur_event );
    cups = get_event_cup_list( event_data );
    set_cur_cup_to_first_incomplete( event_data, cups );
}

static void modern_event_move_cup(int direction)
{
    list_t cups;
    list_elem_t next;
    if ( event_data == NULL ) return;
    cups = get_event_cup_list( event_data );
    if ( cur_cup == NULL ) cur_cup = get_list_head( cups );
    next = direction < 0 ? get_prev_list_elem( cups, cur_cup )
                         : get_next_list_elem( cups, cur_cup );
    if ( next == NULL ) next = direction < 0 ? get_list_tail( cups )
                                              : get_list_head( cups );
    cur_cup = next;
}

static void modern_event_continue(void)
{
    cup_data_t *cup;
    player_data_t *plyr;
    if ( event_data == NULL || cur_cup == NULL ) return;
    if ( !is_cup_complete( event_data, cur_cup ) &&
         !is_cup_first_incomplete_cup( event_data, cur_cup ) ) return;
    cup = (cup_data_t*)get_list_elem_data( cur_cup );
    plyr = get_player_data( local_player() );
    g_game.current_event = get_event_name( event_data );
    g_game.current_cup = get_cup_name( cup );
    plyr->lives = INIT_NUM_LIVES;
    set_game_mode( RACE_SELECT );
}

static void event_select_init(void)
{
    list_t events = get_events_list();
    list_t cups;
    winsys_set_display_func( main_loop );
    winsys_set_idle_func( main_loop );
    winsys_set_reshape_func( reshape );
    modern_event_focus = 0;
    if ( g_game.prev_mode != RACE_SELECT || cur_event == NULL ) {
        cur_event = get_list_head( events );
        event_data = (event_data_t*)get_list_elem_data( cur_event );
        cups = get_event_cup_list( event_data );
        set_cur_cup_to_first_incomplete( event_data, cups );
    } else {
        modern_event_sync();
    }
    play_music( "start_screen" );
}

static void event_select_loop( scalar_t time_step )
{
    int w=getparam_x_resolution(),h=getparam_y_resolution();
    const char *event_name="";
    const char *cup_name="";
    (void)time_step;
    update_audio();
    modern_event_sync();
    int event_index=0,event_total=0,cup_index=0,cup_total=0;
    list_elem_t it;
    list_t events=get_events_list();
    list_t cups=NULL;
    if(event_data) event_name=get_event_name(event_data);
    if(cur_cup) cup_name=get_cup_name((cup_data_t*)get_list_elem_data(cur_cup));
    for(it=get_list_head(events);it!=NULL;it=get_next_list_elem(events,it)){
        ++event_total;if(it==cur_event)event_index=event_total;
    }
    if(event_data)cups=get_event_cup_list(event_data);
    if(cups)for(it=get_list_head(cups);it!=NULL;it=get_next_list_elem(cups,it)){
        ++cup_total;if(it==cur_cup)cup_index=cup_total;
    }
#ifdef __APPLE__
    if(renderer_metal_begin_menu_frame(w,h)){
        renderer_metal_draw_event_menu(event_name,cup_name,modern_event_status(),
                                       modern_event_focus,event_index,event_total,
                                       cup_index,cup_total);
        renderer_metal_end_menu_frame();
    }
#else
    clear_rendering_context();ui_setup_display();ui_draw_menu_decorations();
    reshape(w,h);winsys_swap_buffers();
#endif
}

static void event_select_term(void)
{
}

START_KEYBOARD_CB( event_select_key_cb )
{
    if ( release ) return;
    if ( special ) {
        if ( key == WSK_UP || key == WSK_DOWN ) {
            modern_event_focus = 1-modern_event_focus;
        } else if ( key == WSK_LEFT ) {
            if(modern_event_focus==0)modern_event_move_event(-1);
            else modern_event_move_cup(-1);
        } else if ( key == WSK_RIGHT ) {
            if(modern_event_focus==0)modern_event_move_event(1);
            else modern_event_move_cup(1);
        }
    } else {
        if ( key == 13 ) modern_event_continue();
        else if ( key == 27 ) set_game_mode( GAME_TYPE_SELECT );
    }
    winsys_post_redisplay();
}
END_KEYBOARD_CB

void event_select_register()
{
    int status = 0;

    status |= 
	add_keymap_entry( EVENT_SELECT,
			  DEFAULT_CALLBACK, NULL, NULL, event_select_key_cb );

    check_assertion( status == 0,
		     "out of keymap entries" );

    register_loop_funcs( EVENT_SELECT,
			 event_select_init,
			 event_select_loop,
			 event_select_term );
}



/* EOF */
