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
#include "game_type_select.h"
#include "ui_mgr.h"
#include "ui_theme.h"
#include "button.h"
#include "loop.h"
#include "render_util.h"
#include "audio.h"
#include "gl_util.h"
#include "keyboard.h"
#include "multiplayer.h"
#include "ui_snow.h"
#include "joystick.h"
#ifdef __APPLE__
#include "renderer_metal.h"
#endif

static int modern_home_selected=0;

static void modern_home_activate(void)
{
    g_game.current_event=NULL;g_game.current_cup=NULL;g_game.current_race=-1;
    switch(modern_home_selected){
    case 0:g_game.practicing=False;set_game_mode(EVENT_SELECT);break;
    case 1:g_game.practicing=True;set_game_mode(RACE_SELECT);break;
    case 2:set_game_mode(CREDITS);break;
    case 3:winsys_exit(0);break;
    }
}
static void game_type_select_init(void)
{
    winsys_set_display_func(main_loop);winsys_set_idle_func(main_loop);winsys_set_reshape_func(reshape);
    modern_home_selected=0;play_music("start_screen");
}
static void game_type_select_loop(scalar_t time_step)
{
    int w=getparam_x_resolution(),h=getparam_y_resolution();(void)time_step;update_audio();
#ifdef __APPLE__
    if(renderer_metal_begin_menu_frame(w,h)){renderer_metal_draw_home_menu(modern_home_selected);renderer_metal_end_menu_frame();}
#else
    clear_rendering_context();ui_setup_display();ui_draw_menu_decorations();reshape(w,h);winsys_swap_buffers();
#endif
}
static void game_type_select_term(void){}
START_KEYBOARD_CB(game_type_select_cb)
{
    if(release)return;
    if(special){
        if(key==WSK_UP)modern_home_selected=(modern_home_selected+3)%4;
        else if(key==WSK_DOWN)modern_home_selected=(modern_home_selected+1)%4;
    }else{
        if(key==13)modern_home_activate();
        else if(key==27||tolower((char)key)=='q')winsys_exit(0);
    }
    winsys_post_redisplay();
}
END_KEYBOARD_CB

void game_type_select_register()
{
    add_keymap_entry( GAME_TYPE_SELECT,
                      DEFAULT_CALLBACK, NULL, NULL, game_type_select_cb );
    register_loop_funcs( GAME_TYPE_SELECT,
                         game_type_select_init,
                         game_type_select_loop,
                         game_type_select_term );
}


/* EOF */
