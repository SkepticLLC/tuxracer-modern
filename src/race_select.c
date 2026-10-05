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
#ifdef __APPLE__
#include "modern_text.h"
#include "renderer_metal.h"
#endif

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
    const char *name="",*desc="";
    char progress[64],requirements[128];
    int index=0,total=0,can_start=1;
    list_elem_t e;
    (void)time_step;
    update_audio();

    if(cur_elem){
        if(g_game.practicing){
            open_course_data_t *d=(open_course_data_t*)get_list_elem_data(cur_elem);
            name=d->name?d->name:"COURSE"; desc=d->description?d->description:"";
        }else{
            race_data_t *d=(race_data_t*)get_list_elem_data(cur_elem);
            name=d->name?d->name:"RACE"; desc=d->description?d->description:"";
        }
    }
    for(e=get_list_head(race_list);e!=NULL;e=get_next_list_elem(race_list,e)){
        ++total;if(e==cur_elem)index=total;
    }
    snprintf(progress,sizeof(progress),"%02d / %02d",index,total);
    if(g_game.practicing){
        snprintf(requirements,sizeof(requirements),"PRACTICE  •  FREE RUN");
    }else{
        difficulty_level_t d=g_game.difficulty;
        can_start=(cup_complete||is_current_race_first_incomplete());
        snprintf(requirements,sizeof(requirements),"TIME %.0fs  •  HERRING %d",
                 g_game.race.time_req[d],g_game.race.herring_req[d]);
    }
#ifdef __APPLE__
    if(renderer_metal_begin_menu_frame(getparam_x_resolution(),getparam_y_resolution())){
        renderer_metal_draw_course_menu(name,desc,progress,requirements,can_start);
        renderer_metal_end_menu_frame();
    }
#else
    set_gl_options(GUI);clear_rendering_context();ui_setup_display();
    modern_draw_race_select();reshape(getparam_x_resolution(),getparam_y_resolution());
    winsys_swap_buffers();
#endif
}

/*---------------------------------------------------------------------------*/
/*! 
  Function used by listbox to convert list element to a string to display
  \author  jfpatry
  \date    Created:  2000-09-24
  \date    Modified: 2000-09-24
*/
static char* get_name_from_open_course_data( list_elem_data_t elem )
{
    open_course_data_t *data;

    data = (open_course_data_t*) elem;
    return data->name;
}


/*---------------------------------------------------------------------------*/
/*! 
  Function used by listbox to convert list element to a string to display
  \author  jfpatry
  \date    Created:  2000-09-24
  \date    Modified: 2000-09-24
*/
static char* get_name_from_race_data( list_elem_data_t elem )
{
    race_data_t *data;

    data = (race_data_t*) elem;
    return data->name;
}


/*---------------------------------------------------------------------------*/
/*! 
  Returns true iff the current race is completed
  \author  jfpatry
  \date    Created:  2000-09-24
  \date    Modified: 2000-09-24
*/
static bool_t is_current_race_completed( void )
{
    check_assertion( cur_elem != NULL, "current race is null" );

    if ( last_completed_race == NULL ) {
	return False;
    }

    if ( compare_race_positions( cup_data, cur_elem,
				 last_completed_race ) >= 0 )
    {
	return True;
    }

    return False;
}


/*---------------------------------------------------------------------------*/
/*! 
  Returns true iff the current race is the first incomplete race
  \author  jfpatry
  \date    Created:  2000-09-24
  \date    Modified: 2000-09-24
*/
static bool_t is_current_race_first_incomplete( void )
{
    check_assertion( cur_elem != NULL, "current race is null" );

    if ( last_completed_race == NULL ) {
	if ( cur_elem == get_list_head( race_list ) ) {
	    return True;
	} else {
	    return False;
	}
    }

    if ( compare_race_positions( cup_data, last_completed_race,
				 cur_elem ) == 1 )
    {
	return True;
    }

    return False;
}



/*---------------------------------------------------------------------------*/
/*! 
  Updates g_game.race to reflect current race data
  \author  jfpatry
  \date    Created:  2000-09-24
  \date    Modified: 2000-09-24
*/
void update_race_data( void )
{
    int i;

    if ( g_game.practicing ) {
	open_course_data_t *data;

	data = (open_course_data_t*) get_list_elem_data( cur_elem );
	g_game.race.course = data->course;
	g_game.race.name = data->name;
	g_game.race.description = data->description;

	for (i=0; i<DIFFICULTY_NUM_LEVELS; i++) {
	    g_game.race.herring_req[i] = 0;
	    g_game.race.time_req[i] = 0;
	    g_game.race.score_req[i] = 0;
	}

	g_game.race.time_req[0] = data->par_time;

        /* Modern Practice owns these values directly; no hidden UI widgets. */
        g_game.race.snowing = False;
    } else {
	race_data_t *data;
	data = (race_data_t*) get_list_elem_data( cur_elem );
	g_game.race = *data;

	if ( cup_complete && 
	     mirror_ssbtn != NULL &&
	     conditions_ssbtn != NULL &&
	     wind_ssbtn != NULL &&
	     snow_ssbtn != NULL )
	{
	    /* If the cup is complete, allowed to customize settings */
	    g_game.race.mirrored = (bool_t) ssbutton_get_state( mirror_ssbtn );
	    g_game.race.conditions = (race_conditions_t) ssbutton_get_state(
		conditions_ssbtn );
	    g_game.race.windy = (bool_t) ssbutton_get_state( wind_ssbtn );
	    g_game.race.snowing = (bool_t) ssbutton_get_state( snow_ssbtn );
	}
    }
}


/*---------------------------------------------------------------------------*/
/*! 
  Updates the enabled states of the buttons
  \author  jfpatry
  \date    Created:  2000-09-24
  \date    Modified: 2000-09-24
*/
void update_button_enabled_states( void )
{
    if ( start_btn == NULL ) {
	return;
    }

    if ( g_game.practicing ) {
	button_set_enabled( start_btn, True );
    } else if ( cup_complete ) {
	button_set_enabled( start_btn, True );
    } else if ( plyr->lives <= 0 ) {
	button_set_enabled( start_btn, False );
    } else {
	if ( is_current_race_first_incomplete() ) 
	{
	    button_set_enabled( start_btn, True );
	} else {
	    button_set_enabled( start_btn, False );
	}
    } 
}


/*---------------------------------------------------------------------------*/
/*! 
  Updates the race results based on the results of the race just completed
  Should be called before last_race_completed is updated.
  \author  jfpatry
  \date    Created:  2000-09-24
  \date    Modified: 2000-09-24
*/
static void update_race_results( void )
{
    char *event;
    char *cup;
    bool_t update_score = False;
    char *race_name;
    scalar_t time;
    int herring;
    int score;

    if ( g_game.practicing ) {
	open_course_data_t *data;
	data = (open_course_data_t*)get_list_elem_data( cur_elem );
	race_name = data->name;
    } else {
	race_data_t *data;
	data = (race_data_t*)get_list_elem_data( cur_elem );
	race_name = data->name;
    }

    event = g_game.current_event;
    cup = g_game.current_cup;

    if ( !get_saved_race_results( plyr->name,
				  event,
				  cup,
				  race_name,
				  g_game.difficulty,
				  &time,
				  &herring,
				  &score ) )
    {
	update_score = True;
    } else if ( !g_game.practicing && !cup_complete ) {
	/* Scores are always overwritten if cup isn't complete */
	update_score = True;
    } else if ( plyr->score > score ) {
	update_score = True;
    } else {
	update_score = False;
    }

    if ( update_score ) {
	bool_t result;
	result = 
	    set_saved_race_results( plyr->name,
				    event,
				    cup,
				    race_name,
				    g_game.difficulty,
				    g_game.time,
				    plyr->herring,
				    plyr->score ); 
	if ( !result ) {
	    print_warning( IMPORTANT_WARNING,
			   "Couldn't save race results" );
	}
    }
}


/*---------------------------------------------------------------------------*/
/*! 
  Call when a race has just been won
  \author  jfpatry
  \date    Created:  2000-09-24
  \date    Modified: 2000-09-24
*/
void update_for_won_race( void )
{
    race_data_t *race_data;

    check_assertion( g_game.practicing == False,
		     "Tried to update for won race in practice mode" );

    race_data = (race_data_t*)get_list_elem_data( cur_elem );

    if ( last_completed_race == NULL ||
	 compare_race_positions( cup_data, last_completed_race, 
				 cur_elem ) > 0 )
    {
	last_completed_race = cur_elem;
		
	if ( cur_elem == get_list_tail( race_list ) ) {
	    cup_complete = True;

	    if ( !set_last_completed_cup( 
		plyr->name,
		g_game.current_event,
		g_game.difficulty,
		g_game.current_cup ) )
	    {
		print_warning( IMPORTANT_WARNING,
			       "Couldn't save cup completion" );
	    } else {
		print_debug( DEBUG_GAME_LOGIC, 
			     "Cup %s completed", 
			     g_game.current_cup );
	    }
	}
    }
	
    update_button_enabled_states();
}



/*---------------------------------------------------------------------------*/
/*! 
  Callback called when race listbox item changes
  \author  jfpatry
  \date    Created:  2000-09-24
  \date    Modified: 2000-09-24
*/
static void race_listbox_item_change_cb( listbox_t *listbox, void *userdata )
{
    check_assertion( userdata == NULL, "userdata is not null" );

    cur_elem = listbox_get_current_item( listbox );

    if ( g_game.practicing ) {
	open_course_data_t *data;

	data = (open_course_data_t*) get_list_elem_data( cur_elem );
	textarea_set_text( desc_ta, data->description );

	ui_set_dirty();
    } else {
	race_data_t *data;

	data = (race_data_t*) get_list_elem_data( cur_elem );
	textarea_set_text( desc_ta, data->description );

	if ( cup_complete && 
	     conditions_ssbtn &&
	     wind_ssbtn &&
	     snow_ssbtn &&
	     mirror_ssbtn ) 
	{
	    ssbutton_set_state( conditions_ssbtn,
				(int) data->conditions );
	    ssbutton_set_state( wind_ssbtn,
				(int) data->windy );
	    ssbutton_set_state( snow_ssbtn,
				(int) data->snowing );
	    ssbutton_set_state( mirror_ssbtn,
				(int) data->mirrored );
	}

	update_button_enabled_states();

	ui_set_dirty();
    } 

    update_race_data();
}


/*---------------------------------------------------------------------------*/
/*! 
  Callback called when back button is clicked
  \author  jfpatry
  \date    Created:  2000-09-24
  \date    Modified: 2000-09-24
*/
static void back_click_cb( button_t *button, void *userdata )
{
    check_assertion( userdata == NULL, "userdata is not null" );

    if ( g_game.practicing ) {
	set_game_mode( GAME_TYPE_SELECT );
    } else {
	set_game_mode( EVENT_SELECT );
    }

    ui_set_dirty();
}


/*---------------------------------------------------------------------------*/
/*! 
  Callback called when start button is clicked
  \author  jfpatry
  \date    Created:  2000-09-24
  \date    Modified: 2000-09-24
*/
static void start_click_cb( button_t *button, void *userdata )
{
    check_assertion( userdata == NULL, "userdata is not null" );

    button_set_highlight( start_btn, True );
    race_select_loop( 0 );

    update_race_data();

    set_game_mode( LOADING );
}


/*---------------------------------------------------------------------------*/
/*! 
  Draws a status message on the screen
  \author  jfpatry
  \date    Created:  2000-09-24
  \date    Modified: 2000-09-24
*/
void draw_status_msg( int x_org, int y_org, int box_width, int box_height )
{
    char *msg;
    scalar_t time;
    int herring;
    int score;
    font_t *label_font;
    font_t *font;
    char buff[BUFF_LEN];
    bool_t draw_stats = True;

    if ( !g_game.practicing ) {
	if ( is_current_race_completed() ) {
	    race_data_t *race_data;

	    if ( cup_complete ) {
		msg = "Best result:";
	    } else {
		msg = "Race won! Your result:";
	    }

	    race_data = (race_data_t*)get_list_elem_data( cur_elem );

	    if ( !get_saved_race_results( plyr->name,
					  g_game.current_event,
					  g_game.current_cup,
					  race_data->name,
					  g_game.difficulty,
					  &time,
					  &herring,
					  &score ) )
	    {
		difficulty_level_t d = g_game.difficulty;

		print_warning( IMPORTANT_WARNING,
			       "No saved results for race `%s'.  Using "
			       "race minimum requirements.",
			       race_data->name );

		time = g_game.race.time_req[d];
		herring = g_game.race.herring_req[d];
		score = g_game.race.score_req[d];
	    }
	} else if ( plyr->lives <= 0 ) {
	    msg = "You don't have any lives left.";
	    draw_stats = False;
	} else {
	    difficulty_level_t d = g_game.difficulty;

	    time = g_game.race.time_req[d];
	    herring = g_game.race.herring_req[d];
	    score = g_game.race.score_req[d];

	    if ( is_current_race_first_incomplete() ) {
		msg = "Needed to advance:";
	    } else {
		msg = "You can't enter this race yet.";
		draw_stats = False;
	    }
	}
    } else {
	open_course_data_t *data;

	data = (open_course_data_t*)get_list_elem_data( cur_elem );

	msg = "Best result:";

	if ( !get_saved_race_results( plyr->name,
				      g_game.current_event,
				      g_game.current_cup,
				      data->name,
				      g_game.difficulty,
				      &time,
				      &herring,
				      &score ) )
	{
	    /* Don't display anything if no score saved */
	    return;
	}
    }

    if ( !get_font_binding( "race_requirements", &font ) ||
	 !get_font_binding( "race_requirements_label", &label_font ) ) 
    {
	print_warning( IMPORTANT_WARNING,
		       "Couldn't get fonts for race requirements" );
    } else {
	glPushMatrix();
	{
	    glTranslatef( x_org + 0,
			  y_org + 200,
			  0 );
	    
	    bind_font_texture( label_font );
	    draw_string( label_font, msg );
	}
	glPopMatrix();

	if ( draw_stats ) {
	    glPushMatrix();
	    {
		int minutes;
		int seconds;
		int hundredths;
	    
		get_time_components( time, &minutes, &seconds, &hundredths );
	    
		glTranslatef( x_org + 0,
			      y_org + 184,
			      0 );
	    
	    
		bind_font_texture( label_font );
		draw_string( label_font, "Time: " );
	    
		sprintf( buff, "%02d:%02d.%02d",
			 minutes, seconds, hundredths );
		bind_font_texture( font );
		draw_string( font, buff );
	    
		bind_font_texture( label_font );
		draw_string( label_font, "    Herring: " );
	    
		sprintf( buff, "%03d", herring ); 
		bind_font_texture( font );
		draw_string( font, buff );
	    
		bind_font_texture( label_font );
		draw_string( label_font, "   Score: " );
	    
		sprintf( buff, "%06d", score );
		bind_font_texture( font );
		draw_string( font, buff );
	    }
	    glPopMatrix();
	}
    }
}

/*---------------------------------------------------------------------------*/
/*! 
  Sets the widget positions and draws other on-screen goo 
  \author  jfpatry
  \date    Created:  2000-09-24
  \date    Modified: 2000-09-24
*/
static void modern_draw_text( const char *binding, const char *text,
                              scalar_t x, scalar_t y )
{
#ifdef __APPLE__
    float size=22.0f, alpha=.90f;
    int weight=0;
    if ( strcmp(binding,"modern_screen_title")==0 ) { size=48.0f;weight=1;alpha=1.0f; }
    else if ( strcmp(binding,"modern_screen_eyebrow")==0 ) { size=20.0f;weight=1;alpha=.78f; }
    else if ( strcmp(binding,"modern_screen_body")==0 ) { size=24.0f;alpha=.90f; }
    else if ( strcmp(binding,"modern_screen_hint")==0 ) { size=18.0f;alpha=.70f; }
    else if ( strcmp(binding,"modern_screen_action")==0 ) { size=22.0f;weight=1;alpha=.96f; }
    modern_text_draw(text,(float)x,(float)y,size,.90f,.95f,1.0f,alpha,weight);
#else
    font_t *font;
    if ( text == NULL || !get_font_binding( (char *)binding, &font ) ) return;
    bind_font_texture( font );
    glPushMatrix(); glTranslatef( x, y, 0 ); draw_string( font, (char *)text ); glPopMatrix();
#endif
}

static void modern_draw_race_select( void )
{
    int w=getparam_x_resolution(), h=getparam_y_resolution();
    int pw=(int)(w*.43), ph=(int)(h*.42);
    int px=(int)(w*.51), py=(int)(h*.30);
    const char *name=NULL,*desc=NULL,*course=NULL;
    GLuint texobj=0;
    char counter[64],line[96];
    int index=0,total=0;
    list_elem_t e;

    if(g_game.practicing){
        open_course_data_t *d=(open_course_data_t*)get_list_elem_data(cur_elem);
        name=d->name;desc=d->description;course=d->course;
    }else{
        race_data_t *d=(race_data_t*)get_list_elem_data(cur_elem);
        name=d->name;desc=d->description;course=d->course;
    }
    for(e=get_list_head(race_list);e!=NULL;e=get_next_list_elem(race_list,e)){
        ++total;if(e==cur_elem)index=total;
    }

    ui_draw_menu_decorations();
    modern_draw_text("modern_screen_eyebrow",g_game.practicing?"PRACTICE":"RACE",w*.065,h*.865);
    modern_draw_text("modern_screen_title",name,w*.065,h*.745);
    modern_draw_text("modern_screen_body",desc,w*.065,h*.665);
    snprintf(counter,sizeof(counter),"<   %02d / %02d   >",index,total);
    modern_draw_text("modern_screen_meta",counter,w*.065,h*.545);

    if(g_game.practicing){
        snprintf(line,sizeof(line),"CONDITIONS   %s",
                 g_game.race.conditions==0?"CLEAR":
                 g_game.race.conditions==1?"CLOUDY":"NIGHT");
        modern_draw_text("modern_screen_meta",line,w*.065,h*.445);
        snprintf(line,sizeof(line),"WIND         %s",g_game.race.windy?"ON":"OFF");
        modern_draw_text("modern_screen_meta",line,w*.065,h*.395);
        snprintf(line,sizeof(line),"MIRRORED     %s",g_game.race.mirrored?"ON":"OFF");
        modern_draw_text("modern_screen_meta",line,w*.065,h*.345);
        modern_draw_text("modern_screen_hint","C  CONDITIONS    W  WIND    M  MIRROR",w*.065,h*.265);
    }

    glDisable(GL_TEXTURE_2D);glEnable(GL_BLEND);
    glColor4f(.88f,.94f,1,.16f);glBegin(GL_QUADS);
    glVertex2f(px-4,py-4);glVertex2f(px+pw+4,py-4);glVertex2f(px+pw+4,py+ph+4);glVertex2f(px-4,py+ph+4);glEnd();
    glColor4f(.01f,.025f,.045f,.72f);glBegin(GL_QUADS);
    glVertex2f(px,py);glVertex2f(px+pw,py);glVertex2f(px+pw,py+ph);glVertex2f(px,py+ph);glEnd();
    glEnable(GL_TEXTURE_2D);
    if(!get_texture_binding((char*)course,&texobj))get_texture_binding("no_preview",&texobj);
    glBindTexture(GL_TEXTURE_2D,texobj);glColor4f(1,1,1,1);glBegin(GL_QUADS);
    glTexCoord2f(0,0);glVertex2f(px,py);glTexCoord2f(1,0);glVertex2f(px+pw,py);
    glTexCoord2f(1,1);glVertex2f(px+pw,py+ph);glTexCoord2f(0,1);glVertex2f(px,py+ph);glEnd();

    modern_draw_text("modern_screen_hint","ESC  BACK",w*.065,h*.085);
    modern_draw_text("modern_screen_action","ENTER  START",w*.78,h*.085);
}

static void set_widget_positions_and_draw_decorations()
{
    int w = getparam_x_resolution();
    int h = getparam_y_resolution();
    int box_width, box_height, box_max_y;
    int x_org, y_org;
    char *string;
    font_t *font;
    char *current_course;
    int text_width, asc, desc;
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
	start_btn,
	make_point2d( x_org + 343 - button_get_width( start_btn )/2.0,
		      42 ) );

    listbox_set_position(
	race_listbox,
	make_point2d( x_org,
		      y_org + 221 ) );

    textarea_set_position( 
	desc_ta,
	make_point2d( x_org,
		      y_org + 66 ) );
    
    if ( g_game.practicing || 
	 ( cup_complete &&
	   conditions_ssbtn &&
	   wind_ssbtn &&
	   snow_ssbtn &&
	   mirror_ssbtn ) ) 
    {
	ssbutton_set_position(
	    conditions_ssbtn,
	    make_point2d( x_org + box_width - 4*36 + 4,
			  y_org + 181 ) );

	ssbutton_set_position(
	    wind_ssbtn,
	    make_point2d( x_org + box_width - 3*36 + 4 ,
			  y_org + 181 ) );

	ssbutton_set_position(
	    snow_ssbtn,
	    make_point2d( x_org + box_width - 2*36 + 4,
			  y_org + 181 ) );

	ssbutton_set_position(
	    mirror_ssbtn,
	    make_point2d( x_org + box_width - 1*36 + 4,
			  y_org + 181 ) );

    } else {
	/* Draw tux life icons */
	GLuint texobj;
	int i;

	glPushMatrix();
	{

	    glTranslatef( x_org + box_width - 4*36 + 4,
			  y_org + 181,
			  0 );
	    
	    check_assertion( INIT_NUM_LIVES == 4, 
			     "Assumption about number of lives invalid -- "
			     "need to recode this part" );

	    if ( !get_texture_binding( "tux_life", &texobj ) ) {
		texobj = 0;
	    }

	    glBindTexture( GL_TEXTURE_2D, texobj );

	    for ( i=0; i<4; i++ ) {
		point2d_t ll, ur;
		if ( plyr->lives > i ) {
		    ll = make_point2d( 0, 0.5 );
		    ur = make_point2d( 1, 1 );
		} else {
		    ll = make_point2d( 0, 0 );
		    ur = make_point2d( 1, 0.5 );
		}

		glBegin( GL_QUADS );
		{
		    glTexCoord2f( ll.x, ll.y );
		    glVertex2f( 0, 0 );

		    glTexCoord2f( ur.x, ll.y );
		    glVertex2f( 32, 0 );

		    glTexCoord2f( ur.x, ur.y );
		    glVertex2f( 32, 32 );

		    glTexCoord2f( ll.x, ur.y );
		    glVertex2f( 0, 32 );
		}
		glEnd();

		glTranslatef( 36, 0, 0 );
	    }
	}
	glPopMatrix();
    }

    /* Draw other stuff */
    if ( !get_font_binding( "menu_label", &font ) ) {
	print_warning( IMPORTANT_WARNING,
		       "Couldn't get font for binding menu_label" );
    } else {
	bind_font_texture( font );
	string = "Select a race";
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

    /* Draw text indicating race requirements (if race not completed), 
       or results in race if race completed. */
    draw_status_msg( x_org, y_org, box_width, box_height );

    /* Draw preview */
    if ( g_game.practicing ) {
	list_elem_t elem;
	open_course_data_t *data;

	elem = listbox_get_current_item( race_listbox );
	data = (open_course_data_t*) get_list_elem_data( elem );
	current_course = data->course;
    } else {
	list_elem_t elem;
	race_data_t *data;

	elem = listbox_get_current_item( race_listbox );
	data = (race_data_t*) get_list_elem_data( elem );
	current_course = data->course;
    }

    glDisable( GL_TEXTURE_2D );

    glColor4f( 1.0, 1.0, 1.0, 1.0 );
    glBegin( GL_QUADS );
    {
	glVertex2f( x_org+box_width-140, y_org+66 );
	glVertex2f( x_org+box_width, y_org+66 );
	glVertex2f( x_org+box_width, y_org+66+107 );
	glVertex2f( x_org+box_width-140, y_org+66+107 );
    }
    glEnd();

    glEnable( GL_TEXTURE_2D );

    if ( !get_texture_binding( current_course, &texobj ) ) {
	if ( !get_texture_binding( "no_preview", &texobj ) ) {
	    texobj = 0;
	}
    }

    glBindTexture( GL_TEXTURE_2D, texobj );

    glBegin( GL_QUADS );
    {
	glTexCoord2d( 0, 0);
	glVertex2f( x_org+box_width-136, y_org+70 );

	glTexCoord2d( 1, 0);
	glVertex2f( x_org+box_width-4, y_org+70 );

	glTexCoord2d( 1, 1);
	glVertex2f( x_org+box_width-4, y_org+70+99 );

	glTexCoord2d( 0, 1);
	glVertex2f( x_org+box_width-136, y_org+70+99 );
    }
    glEnd();
}


/*---------------------------------------------------------------------------*/
/*! 
  Mode initialization function
  \author  jfpatry
  \date    Created:  2000-09-24
  \date    Modified: 2000-09-24
*/
static void race_select_init(void)
{
    listbox_list_elem_to_string_fptr_t conv_func = NULL;
    point2d_t dummy_pos = {0, 0};
    int i;

    winsys_set_display_func( main_loop );
    winsys_set_idle_func( main_loop );
    winsys_set_reshape_func( reshape );
    winsys_set_mouse_func( ui_event_mouse_func );
    winsys_set_motion_func( ui_event_motion_func );
    winsys_set_passive_motion_func( ui_event_motion_func );

    plyr = get_player_data( local_player() );

    /* Setup the race list */
    if ( g_game.practicing ) {
	g_game.current_event = "__Practice_Event__";
	g_game.current_cup = "__Practice_Cup__";
	race_list = get_open_courses_list();
	conv_func = get_name_from_open_course_data;
	cup_data = NULL;
	last_completed_race = NULL;
	event_data = NULL;
    } else {
	event_data = (event_data_t*) get_list_elem_data( 
	    get_event_by_name( g_game.current_event ) );
	check_assertion( event_data != NULL,
			 "Couldn't find current event." );
	cup_data = (cup_data_t*) get_list_elem_data(
	    get_event_cup_by_name( event_data, g_game.current_cup ) );
	check_assertion( cup_data != NULL,
			 "Couldn't find current cup." );
	race_list = get_cup_race_list( cup_data );
	conv_func = get_name_from_race_data;
    }

    /* Unless we're coming back from a race, initialize the race data to 
       defaults.
    */
    if ( g_game.prev_mode != GAME_OVER ) {
	/* Make sure we don't play previously loaded course */
	cup_complete = False;

	/* Initialize the race data */
	cur_elem = get_list_head( race_list );

	if ( g_game.practicing ) {
	    g_game.race.course = NULL;
	    g_game.race.name = NULL;
	    g_game.race.description = NULL;

	    for (i=0; i<DIFFICULTY_NUM_LEVELS; i++) {
		g_game.race.herring_req[i] = 0;
		g_game.race.time_req[i] = 0;
		g_game.race.score_req[i] = 0;
	    }

	    g_game.race.mirrored = False;
	    g_game.race.conditions = RACE_CONDITIONS_SUNNY;
	    g_game.race.windy = False;
	    g_game.race.snowing = False;
	} else {
	    /* Not practicing */

	    race_data_t *data;
	    data = (race_data_t*) get_list_elem_data( cur_elem );
	    g_game.race = *data;

	    if ( is_cup_complete( event_data, 
				  get_event_cup_by_name( 
				      event_data, 
				      g_game.current_cup ) ) )
	    {
		cup_complete = True;
		last_completed_race = get_list_tail( race_list );
	    } else {
		cup_complete = False;
		last_completed_race = NULL;
	    }
	}
    } else {
	/* Back from a race */
	if ( !g_game.race_aborted ) {
	    update_race_results();
	}

	if (!g_game.practicing && !cup_complete) {
	    if ( was_current_race_won() ) {
		update_for_won_race();

		/* Advance to next race */
		if ( cur_elem != get_list_tail( race_list ) ) {
		    cur_elem = get_next_list_elem( race_list, cur_elem );
		}
	    } else {
		/* lost race */
		plyr->lives -= 1;
	    }
	    print_debug( DEBUG_GAME_LOGIC, "Current lives: %d", plyr->lives );
	}
    }

    if ( g_game.practicing ) {
        /* Modern Practice is a standalone screen: no legacy widgets. */
        update_race_data();
        play_music( "start_screen" );
        return;
    }

    back_btn = button_create( dummy_pos,
			      150, 40, 
			      "button_label", 
			      "Back" );
    button_set_hilit_font_binding( back_btn, "button_label_hilit" );
    button_set_visible( back_btn, False );
    button_set_click_event_cb( back_btn, back_click_cb, NULL );

    start_btn = button_create( dummy_pos,
			       150, 40,
			       "button_label",
			       "Race!" );
    button_set_hilit_font_binding( start_btn, "button_label_hilit" );
    button_set_disabled_font_binding( start_btn, "button_label_disabled" );
    button_set_visible( start_btn, False );
    button_set_click_event_cb( start_btn, start_click_cb, NULL );


    race_listbox = listbox_create( dummy_pos,
				   460, 44,
				   "listbox_item",
				   race_list,
				   conv_func );

    listbox_set_current_item( race_listbox, cur_elem );

    listbox_set_item_change_event_cb( race_listbox, 
				      race_listbox_item_change_cb, 
				      NULL );

    listbox_set_visible( race_listbox, False );

    /* 
     * Create text area 
     */
    desc_ta = textarea_create( dummy_pos,
			       312, 107,
			       "race_description",
			       "" );
    if ( g_game.practicing ) {
	open_course_data_t *data;
	data = (open_course_data_t*) get_list_elem_data( cur_elem );
	textarea_set_text( desc_ta, data->description );
    } else {
	race_data_t *data;
	data = (race_data_t*) get_list_elem_data( cur_elem );
	textarea_set_text( desc_ta, data->description );
    }

    textarea_set_visible( desc_ta, False );
			       

    /* 
     * Create state buttons - only if practicing or if cup_complete
     */

    if ( g_game.practicing || cup_complete ) {
	/* mirror */
	mirror_ssbtn = ssbutton_create( dummy_pos,
					32, 32,
					2 );
	ssbutton_set_state_image( mirror_ssbtn, 
				  0, 
				  "mirror_button",
				  make_point2d( 0.0/64.0, 32.0/64.0 ),
				  make_point2d( 32.0/64.0, 64.0/64.0 ),
				  white );

	ssbutton_set_state_image( mirror_ssbtn, 
				  1, 
				  "mirror_button",
				  make_point2d( 32.0/64.0, 32.0/64.0 ),
				  make_point2d( 64.0/64.0, 64.0/64.0 ),
				  white );

	ssbutton_set_state( mirror_ssbtn, (int)g_game.race.mirrored );
	ssbutton_set_visible( mirror_ssbtn, False );

	/* conditions */
	conditions_ssbtn = ssbutton_create( dummy_pos,
					    32, 32,
					    3 );
	ssbutton_set_state_image( conditions_ssbtn, 
				  0, 
				  "conditions_button",
				  make_point2d( 0.0/64.0, 32.0/64.0 ),
				  make_point2d( 32.0/64.0, 64.0/64.0 ),
				  white );

	ssbutton_set_state_image( conditions_ssbtn, 
				  1, 
				  "conditions_button",
				  make_point2d( 32.0/64.0, 0.0/64.0 ),
				  make_point2d( 64.0/64.0, 32.0/64.0 ),
				  white );

	ssbutton_set_state_image( conditions_ssbtn, 
				  2, 
				  "conditions_button",
				  make_point2d( 32.0/64.0, 32.0/64.0 ),
				  make_point2d( 64.0/64.0, 64.0/64.0 ),
				  white );

	ssbutton_set_state( conditions_ssbtn, (int)g_game.race.conditions );
	ssbutton_set_visible( conditions_ssbtn, False );

	/* wind */
	wind_ssbtn = ssbutton_create( dummy_pos,
				      32, 32,
				      2 );
	ssbutton_set_state_image( wind_ssbtn, 
				  0, 
				  "wind_button",
				  make_point2d( 0.0/64.0, 32.0/64.0 ),
				  make_point2d( 32.0/64.0, 64.0/64.0 ),
				  white );

	ssbutton_set_state_image( wind_ssbtn, 
				  1, 
				  "wind_button",
				  make_point2d( 32.0/64.0, 32.0/64.0 ),
				  make_point2d( 64.0/64.0, 64.0/64.0 ),
				  white );

	ssbutton_set_state( wind_ssbtn, (int)g_game.race.windy );
	ssbutton_set_visible( wind_ssbtn, False );

	/* snow */
	snow_ssbtn = ssbutton_create( dummy_pos,
				      32, 32,
				      2 );
	ssbutton_set_state_image( snow_ssbtn, 
				  0, 
				  "snow_button",
				  make_point2d( 0.0/64.0, 32.0/64.0 ),
				  make_point2d( 32.0/64.0, 64.0/64.0 ),
				  white );

	ssbutton_set_state_image( snow_ssbtn, 
				  1, 
				  "snow_button",
				  make_point2d( 32.0/64.0, 32.0/64.0 ),
				  make_point2d( 64.0/64.0, 64.0/64.0 ),
				  white );

	ssbutton_set_state( snow_ssbtn, (int)g_game.race.snowing );
	ssbutton_set_visible( snow_ssbtn, False );
	/* XXX snow button doesn't do anything, so disable for now */
	ssbutton_set_enabled( snow_ssbtn, False );

	/* Can't change conditions if in cup mode */
	if ( !g_game.practicing ) {
	    ssbutton_set_enabled( conditions_ssbtn, False );
	    ssbutton_set_enabled( wind_ssbtn, False );
	    ssbutton_set_enabled( snow_ssbtn, False );
	    ssbutton_set_enabled( mirror_ssbtn, False );
	}

    } else {
	conditions_ssbtn = NULL;
	wind_ssbtn = NULL;
	snow_ssbtn = NULL;
	mirror_ssbtn = NULL;
    }

    update_race_data();
    update_button_enabled_states();

    play_music( "start_screen" );
}


/*---------------------------------------------------------------------------*/
/*! 
  Mode loop function
  \author  jfpatry
  \date    Created:  2000-09-24
  \date    Modified: 2000-09-24
*/
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
  \author  jfpatry
  \date    Created:  2000-09-24
  \date    Modified: 2000-09-24
*/
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

    if ( desc_ta ) {
        textarea_delete( desc_ta );
    }
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


static void modern_practice_select_prev( void )
{
    list_elem_t prev;
    if ( cur_elem == NULL ) return;
    prev = get_prev_list_elem( race_list, cur_elem );
    if ( prev == NULL ) prev = get_list_tail( race_list );
    cur_elem = prev;
    update_race_data();
}

static void modern_practice_select_next( void )
{
    list_elem_t next;
    if ( cur_elem == NULL ) return;
    next = get_next_list_elem( race_list, cur_elem );
    if ( next == NULL ) next = get_list_head( race_list );
    cur_elem = next;
    update_race_data();
}

static void modern_practice_cycle_conditions( void )
{
    int c=(int)g_game.race.conditions;
    c=(c+1)%3;
    g_game.race.conditions=(race_conditions_t)c;
}

static void modern_practice_toggle_wind( void )
{
    g_game.race.windy = g_game.race.windy ? False : True;
}

static void modern_practice_toggle_mirror( void )
{
    g_game.race.mirrored = g_game.race.mirrored ? False : True;
}

START_KEYBOARD_CB( race_select_key_cb )
{
    if ( release ) {
	return;
    }

    if ( g_game.practicing ) {
        if ( special ) {
            switch ( key ) {
            case WSK_UP:
            case WSK_LEFT:
                modern_practice_select_prev();
                break;
            case WSK_RIGHT:
            case WSK_DOWN:
                modern_practice_select_next();
                break;
            }
        } else {
            key=(int)tolower((char)key);
            switch(key) {
            case 13:
                update_race_data();
                set_game_mode( LOADING );
                break;
            case 27:
                set_game_mode( GAME_TYPE_SELECT );
                break;
            case 'c':
                modern_practice_cycle_conditions();
                break;
            case 'w':
                modern_practice_toggle_wind();
                break;
            case 'm':
                modern_practice_toggle_mirror();
                break;
            }
        }
        ui_set_dirty();
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
            if ( cup_complete || is_current_race_first_incomplete() ) {
                update_race_data();
                set_game_mode( LOADING );
            }
            ui_set_dirty();
	    break;
	case 27: /* Esc */
            set_game_mode( EVENT_SELECT );
            ui_set_dirty();
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
