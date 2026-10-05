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
#include "fonts.h"
#include "gl_util.h"
#include "textures.h"
#include "fps.h"
#include "phys_sim.h"
#include "multiplayer.h"
#include "ui_mgr.h"
#include "game_logic_util.h"

#define SECONDS_IN_MINUTE 60

#define TIME_LABEL_X_OFFSET 12.0
#define TIME_LABEL_Y_OFFSET 12.0

#define TIME_X_OFFSET 30.0
#define TIME_Y_OFFSET 5.0

#define HERRING_ICON_HEIGHT 30.0
#define HERRING_ICON_WIDTH 48.0
#define HERRING_ICON_IMG_SIZE 64.0
#define HERRING_ICON_X_OFFSET 160.0
#define HERRING_ICON_Y_OFFSET 41.0
#define HERRING_COUNT_Y_OFFSET 37.0

#define GAUGE_IMG_SIZE 128

#define ENERGY_GAUGE_BOTTOM 3.0
#define ENERGY_GAUGE_HEIGHT 103.0
#define ENERGY_GAUGE_CENTER_X 71.0
#define ENERGY_GAUGE_CENTER_Y 55.0

#define GAUGE_WIDTH 127.0
#define SPEED_UNITS_Y_OFFSET 4.0

#define SPEEDBAR_OUTER_RADIUS ( ENERGY_GAUGE_CENTER_X )
#define SPEEDBAR_BASE_ANGLE 225
#define SPEEDBAR_MAX_ANGLE 45
#define SPEEDBAR_GREEN_MAX_SPEED ( MAX_PADDLING_SPEED * M_PER_SEC_TO_KM_PER_H )
#define SPEEDBAR_YELLOW_MAX_SPEED 100
#define SPEEDBAR_RED_MAX_SPEED 160
#define SPEEDBAR_GREEN_FRACTION 0.5
#define SPEEDBAR_YELLOW_FRACTION 0.25
#define SPEEDBAR_RED_FRACTION 0.25

#define FPS_X_OFFSET 12
#define FPS_Y_OFFSET 12


static GLfloat energy_background_color[] = { 0.2, 0.2, 0.2, 0.5 };
static GLfloat energy_foreground_color[] = { 0.54, 0.59, 1.00, 0.5 };
static GLfloat speedbar_background_color[] = { 0.2, 0.2, 0.2, 0.5 };
static GLfloat white[] = { 1.0, 1.0, 1.0, 1.0 };

static void draw_modern_panel( scalar_t x, scalar_t y,
                               scalar_t w, scalar_t h )
{
    set_gl_options( GUI );
    glDisable( GL_TEXTURE_2D );
    glEnable( GL_BLEND );
    glBlendFunc( GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA );
    glColor4f( 0.025f, 0.045f, 0.070f, 0.48f );
    glBegin( GL_QUADS );
    glVertex2f( x, y );
    glVertex2f( x+w, y );
    glVertex2f( x+w, y+h );
    glVertex2f( x, y+h );
    glEnd();
}

static void draw_time()
{
    font_t *value_font, *small_font;
    int minutes, seconds, hundredths;
    int w, asc, desc;
    char buff[BUFF_LEN];
    char hundredths_buff[16];

    get_time_components( g_game.time, &minutes, &seconds, &hundredths );
    if ( !get_font_binding( "modern_hud_value", &value_font ) ||
         !get_font_binding( "modern_hud_small", &small_font ) ) return;

    sprintf( buff, "%02d:%02d", minutes, seconds );
    sprintf( hundredths_buff, ".%02d", hundredths );

    draw_modern_panel( 18.0, getparam_y_resolution()-91.0, 210.0, 65.0 );

    bind_font_texture( small_font );
    set_gl_options( TEXFONT );
    glPushMatrix();
    glTranslatef( 31.0, getparam_y_resolution()-48.0, 0 );
    draw_string( small_font, "TIME" );
    glPopMatrix();

    get_font_metrics( value_font, buff, &w, &asc, &desc );
    bind_font_texture( value_font );
    glPushMatrix();
    glTranslatef( 82.0, getparam_y_resolution()-70.0, 0 );
    draw_string( value_font, buff );
    glPopMatrix();

    bind_font_texture( small_font );
    glPushMatrix();
    glTranslatef( 82.0+w+4.0, getparam_y_resolution()-64.0, 0 );
    draw_string( small_font, hundredths_buff );
    glPopMatrix();
}

static void draw_herring_count( int herring_count )
{
    char *string;
    char buff[BUFF_LEN];
    GLuint texobj;
    font_t *font;
    char *binding;
    int w, asc, desc;

    set_gl_options( TEXFONT );
    glColor3f( 1.0, 1.0, 1.0 );

    binding = "herring_icon";

    if ( !get_texture_binding( binding, &texobj ) ) {
	print_warning( IMPORTANT_WARNING,
		       "Couldn't get texture for binding %s", binding );
	return;
    }

    binding = "herring_count";

    if ( !get_font_binding( binding, &font ) ) {
	print_warning( IMPORTANT_WARNING,
		       "Couldn't get font for binding %s", binding );
	return;
    }

    sprintf( buff, " x %03d", herring_count ); 

    string = buff;

    get_font_metrics( font, string, &w, &asc, &desc );

    glBindTexture( GL_TEXTURE_2D, texobj );

    glPushMatrix();
    {
	glTranslatef( getparam_x_resolution() - HERRING_ICON_X_OFFSET,
		      getparam_y_resolution() - HERRING_ICON_Y_OFFSET - asc, 
		      0 );

	glBegin( GL_QUADS );
	{
	    glTexCoord2f( 0, 0 );
	    glVertex2f( 0, 0 );

	    glTexCoord2f( (GLfloat) HERRING_ICON_WIDTH / HERRING_ICON_IMG_SIZE,
			  0 );
	    glVertex2f( HERRING_ICON_WIDTH, 0 );

	    glTexCoord2f( 
		(GLfloat)HERRING_ICON_WIDTH / HERRING_ICON_IMG_SIZE,
		(GLfloat)HERRING_ICON_HEIGHT / HERRING_ICON_IMG_SIZE );
	    glVertex2f( HERRING_ICON_WIDTH, HERRING_ICON_HEIGHT );

	    glTexCoord2f( 
		0,
		(GLfloat)HERRING_ICON_HEIGHT / HERRING_ICON_IMG_SIZE );
	    glVertex2f( 0, HERRING_ICON_HEIGHT );
	}
	glEnd();

	
	bind_font_texture( font );

	glTranslatef( HERRING_ICON_WIDTH, 
		      HERRING_ICON_Y_OFFSET -  HERRING_COUNT_Y_OFFSET,
		      0 );

	draw_string( font, string );
    }
    glPopMatrix();

    
}

#define CIRCLE_DIVISIONS 10

point2d_t calc_new_fan_pt( scalar_t angle )
{
    point2d_t pt;
    pt.x = ENERGY_GAUGE_CENTER_X + cos( ANGLES_TO_RADIANS( angle ) ) *
	SPEEDBAR_OUTER_RADIUS;
    pt.y = ENERGY_GAUGE_CENTER_Y + sin( ANGLES_TO_RADIANS( angle ) ) *
	SPEEDBAR_OUTER_RADIUS;

    return pt;
}

void start_tri_fan()
{
    point2d_t pt;

    glBegin( GL_TRIANGLE_FAN );
    glVertex2f( ENERGY_GAUGE_CENTER_X, 
		ENERGY_GAUGE_CENTER_Y );

    pt = calc_new_fan_pt( SPEEDBAR_BASE_ANGLE ); 

    glVertex2f( pt.x, pt.y );
}

void draw_partial_tri_fan( scalar_t fraction )
{
    int divs;
    scalar_t angle, angle_incr, cur_angle;
    int i;
    bool_t trifan = False;
    point2d_t pt;

    angle = SPEEDBAR_BASE_ANGLE + 
	( SPEEDBAR_MAX_ANGLE - SPEEDBAR_BASE_ANGLE ) * fraction;

    divs = (int) ( SPEEDBAR_BASE_ANGLE - angle ) * CIRCLE_DIVISIONS / 360.0;

    cur_angle = SPEEDBAR_BASE_ANGLE;

    angle_incr = 360.0 / CIRCLE_DIVISIONS;

    for (i=0; i<divs; i++) {
	if ( !trifan ) {
	    start_tri_fan();
	    trifan = True;
	}

	cur_angle -= angle_incr;

	pt = calc_new_fan_pt( cur_angle );

	glVertex2f( pt.x, pt.y );
    }

    if ( cur_angle > angle + EPS ) {
	cur_angle = angle;
	if ( !trifan ) {
	    start_tri_fan();
	    trifan = True;
	}

	pt = calc_new_fan_pt( cur_angle );

	glVertex2f( pt.x, pt.y );
    }

    if ( trifan ) {
	glEnd();
	trifan = False;
    }
}

void draw_gauge( scalar_t speed, scalar_t energy )
{
    font_t *value_font, *small_font;
    char buff[BUFF_LEN];
    int w, asc, desc;
    scalar_t panel_x = getparam_x_resolution() - 238.0;
    scalar_t panel_y = 20.0;
    scalar_t energy_w;

    if ( !get_font_binding( "modern_hud_speed", &value_font ) ||
         !get_font_binding( "modern_hud_small", &small_font ) ) return;

    draw_modern_panel( panel_x, panel_y, 218.0, 104.0 );

    sprintf( buff, "%d", (int)speed );
    get_font_metrics( value_font, buff, &w, &asc, &desc );

    bind_font_texture( value_font );
    set_gl_options( TEXFONT );
    glPushMatrix();
    glTranslatef( panel_x+24.0, panel_y+43.0, 0 );
    draw_string( value_font, buff );
    glPopMatrix();

    bind_font_texture( small_font );
    glPushMatrix();
    glTranslatef( panel_x+35.0+w, panel_y+51.0, 0 );
    draw_string( small_font, "KM/H" );
    glPopMatrix();

    /* Minimal translucent energy/charge indicator. */
    energy_w = 174.0 * min( 1.0, max( 0.0, energy ) );
    set_gl_options( GUI );
    glDisable( GL_TEXTURE_2D );
    glEnable( GL_BLEND );
    glBlendFunc( GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA );
    glColor4f( 0.75f, 0.86f, 0.96f, 0.16f );
    glBegin( GL_QUADS );
    glVertex2f(panel_x+22.0,panel_y+20.0);
    glVertex2f(panel_x+196.0,panel_y+20.0);
    glVertex2f(panel_x+196.0,panel_y+25.0);
    glVertex2f(panel_x+22.0,panel_y+25.0);
    glEnd();
    glColor4f( 0.78f, 0.92f, 1.0f, 0.78f );
    glBegin( GL_QUADS );
    glVertex2f(panel_x+22.0,panel_y+20.0);
    glVertex2f(panel_x+22.0+energy_w,panel_y+20.0);
    glVertex2f(panel_x+22.0+energy_w,panel_y+25.0);
    glVertex2f(panel_x+22.0,panel_y+25.0);
    glEnd();
}

void print_fps()
{
    char buff[BUFF_LEN];
    char *string;
    char *binding;
    font_t *font;

    /* This is needed since this can be called from outside */
    ui_setup_display();

    if ( ! getparam_display_fps() ) {
	return;
    }

    binding = "fps";
    if ( !get_font_binding( binding, &font ) ) {
	print_warning( IMPORTANT_WARNING,
		       "Couldn't get font for binding %s", binding );
	return;
    }

    bind_font_texture( font );
    set_gl_options( TEXFONT );
    glColor3f( 1, 1, 1 );

    sprintf( buff, "FPS: %.1f", get_fps() );
    string = buff;

    glPushMatrix();
    {
	glTranslatef( FPS_X_OFFSET,
		      FPS_Y_OFFSET,
		      0 );
	draw_string( font, string );
    }
    glPopMatrix();

}

void draw_hud( player_data_t *plyr )
{
    vector_t vel;
    scalar_t speed;

    vel = plyr->vel;
    speed = normalize_vector( &vel );

    ui_setup_display();

    draw_gauge( speed * M_PER_SEC_TO_KM_PER_H, plyr->control.jump_amt );
    draw_time();
    draw_herring_count( plyr->herring );

    print_fps();
}
