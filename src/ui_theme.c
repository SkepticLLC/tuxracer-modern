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
#include "ui_theme.h"
#include "textures.h"

colour_t ui_background_colour = { 0.055, 0.105, 0.17, 1.0 };
colour_t ui_foreground_colour = { 1.0, 1.0, 1.0, 1.0 }; 
colour_t ui_highlight_colour = { 0.72, 0.90, 1.0, 1.0 };
colour_t ui_disabled_colour = { 1.0, 1.0, 1.0, 0.6 };

static void draw_quad(int x, int y, int w, int h)
{
    glPushMatrix();
    {
	glTranslatef( x, y, 0 );
	glBegin( GL_QUADS );
	{
	    glTexCoord2f( 0, 0 );
	    glVertex2f( 0, 0 );
	    
	    glTexCoord2f( 1, 0 );
	    glVertex2f( w, 0 );
	    
	    glTexCoord2f( 1, 1 );
	    glVertex2f( w, h );
	    
	    glTexCoord2f( 0, 1 );
	    glVertex2f( 0, h );
	}
	glEnd();
    }
    glPopMatrix();
}

void ui_draw_menu_decorations()
{
    int w=getparam_x_resolution(),h=getparam_y_resolution();
    set_gl_options(GUI); glDisable(GL_TEXTURE_2D); glEnable(GL_BLEND);
    glBlendFunc(GL_SRC_ALPHA,GL_ONE_MINUS_SRC_ALPHA);
    glBegin(GL_QUADS);
    glColor4f(.035f,.085f,.15f,1);glVertex2f(0,0);glVertex2f(w,0);
    glColor4f(.16f,.34f,.55f,1);glVertex2f(w,h);glVertex2f(0,h);
    glEnd();
    glColor4f(.018f,.040f,.068f,.50f);glBegin(GL_QUADS);
    glVertex2f(w*.25f,h*.15f);glVertex2f(w*.75f,h*.15f);
    glVertex2f(w*.75f,h*.82f);glVertex2f(w*.25f,h*.82f);glEnd();
    glColor4f(.72f,.90f,1,.22f);glBegin(GL_QUADS);
    glVertex2f(w*.25f,h*.82f);glVertex2f(w*.75f,h*.82f);
    glVertex2f(w*.75f,h*.825f);glVertex2f(w*.25f,h*.825f);glEnd();
    glColor4f(.82f,.91f,.99f,.11f);glBegin(GL_QUADS);
    glVertex2f(0,0);glVertex2f(w,0);glVertex2f(w,h*.16f);glVertex2f(0,h*.10f);glEnd();
}
/* EOF */
