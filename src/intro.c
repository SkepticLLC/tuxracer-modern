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
#include "keyframe.h"
#include "course_render.h"
#include "multiplayer.h"
#include "gl_util.h"
#include "fps.h"
#include "loop.h"
#include "render_util.h"
#include "view.h"
#include "tux.h"
#include "tux_shadow.h"
#include "fog.h"
#include "viewfrustum.h"
#include "keyboard.h"
#include "hud.h"
#include "phys_sim.h"
#include "part_sys.h"
#include "course_load.h"
#include "joystick.h"
#include "renderer.h"
#ifdef __APPLE__
#include "renderer_metal.h"
#endif

static bool_t staging_lights_active = False;
static scalar_t staging_lights_time = 0.0;

static void abort_intro( player_data_t *plyr ) {
    point2d_t start_pt = get_start_pt();

    set_game_mode( RACING );

    plyr->orientation_initialized = False;
    plyr->view.initialized = False;

    plyr->pos.x = start_pt.x;
    plyr->pos.z = start_pt.y;

    winsys_post_redisplay();
}

void intro_init(void) 
{
    int i, num_items;
    item_t *item_locs;

    player_data_t *plyr = get_player_data( local_player() );
    point2d_t start_pt = get_start_pt();

    init_key_frame();
    staging_lights_active = False;
    staging_lights_time = 0.0;

    winsys_set_display_func( main_loop );
    winsys_set_idle_func( main_loop );
    winsys_set_reshape_func( renderer_resize );
    winsys_set_mouse_func( NULL );
    winsys_set_motion_func( NULL );
    winsys_set_passive_motion_func( NULL );

    plyr->orientation_initialized = False;

    plyr->view.initialized = False;

    g_game.time = 0.0;
    plyr->herring = 0;
    plyr->score = 0;

    plyr->pos.x = start_pt.x;
    plyr->pos.z = start_pt.y;

    init_physical_simulation();

    plyr->vel = make_vector( 0, 0, 0 );

    clear_particles();

    set_view_mode( plyr, ABOVE );
    update_view( plyr, EPS ); 

    /* reset all items as collectable */
    num_items = get_num_items();
    item_locs = get_item_locs();
    for (i = 0; i < num_items; i++ ) {
	if ( item_locs[i].collectable != -1 ) {
	    item_locs[i].collectable = 1;
	}
    }

    play_music( "intro" );
}

void intro_loop( scalar_t time_step )
{
    int width, height;
    player_data_t *plyr = get_player_data( local_player() );

    if ( getparam_do_intro_animation() == False ) {
	set_game_mode( RACING );
	return;
    }

    width = getparam_x_resolution();
    height = getparam_y_resolution();

    check_gl_error();

    /* Check joystick */
    if ( is_joystick_active() ) {
	update_joystick();

	if ( is_joystick_continue_button_down() ) {
	    abort_intro( plyr );
	    return;
	}
    }
    
    new_frame_for_fps_calc();

    update_audio();

    /*
     * Modern level entry: slow only the scripted walk-out/keyframe.
     * Audio, rendering, particles, and the rest of the game clock remain
     * real-time so the scene feels deliberate rather than slow-motion.
     */
    if ( !staging_lights_active ) {
        if ( update_key_frame( plyr, time_step * 0.78 ) ) {
            staging_lights_active = True;
            staging_lights_time = 0.0;
        }
    } else {
        staging_lights_time += time_step;
        if ( staging_lights_time >= 2.25 ) {
            set_game_mode( RACING );
            return;
        }
    }

    renderer_begin_frame();

    clear_rendering_context();

    setup_fog();

    update_view( plyr, time_step );

    setup_view_frustum( plyr, NEAR_CLIP_DIST, 
			getparam_forward_clip_distance() );

    draw_sky( plyr->view.pos );

    draw_fog_plane();

    set_course_clipping( True );
    set_course_eye_point( plyr->view.pos );
    setup_course_lighting();
    render_course( );

    if ( renderer_metal_native_enabled() ) {
        draw_mountain_backdrop_metal( plyr->view.pos );
        draw_trees_metal();
        draw_items_metal();
        draw_start_line_metal();

#ifdef __APPLE__
        if ( staging_lights_active ) {
            /*
             * Place the drag tree in the player's local start frame, not
             * global course X. This keeps it visually beside Tux regardless
             * of course orientation or intro camera angle.
             */
            vector_t fwd = plyr->view.dir;
            vector_t side;
            point_t tree_base;
            float side_len;
            int lamp, pair;

            fwd.y = 0.0;
            if ( MAG_SQD(fwd) < 0.0001 ) fwd = make_vector(0,0,-1);
            normalize_vector( &fwd );
            side = make_vector( fwd.z, 0.0, -fwd.x );
            side_len = 2.05f;

            tree_base = move_point( plyr->pos, scale_vector(side_len, side) );
            tree_base = move_point( tree_base, scale_vector(0.10, fwd) );
            tree_base.y = find_y_coord( tree_base.x, tree_base.z );

            {
                static bool_t logged_staging_frame = False;
                double proof_tux[16] = {
                    0.34,0,0,0, 0,0.34,0,0, 0,0,0.34,0,
                    plyr->pos.x, plyr->pos.y + 2.2, plyr->pos.z, 1
                };
                double proof_tree[16] = {
                    0.34,0,0,0, 0,0.34,0,0, 0,0,0.34,0,
                    tree_base.x, tree_base.y + 2.2, tree_base.z, 1
                };
                if ( !logged_staging_frame ) {
                    point2d_t sp = get_start_pt();
                    fprintf(stderr,
                      "Tux Racer Modern: staging debug tux=(%.2f,%.2f,%.2f) start=(%.2f,%.2f) camera=(%.2f,%.2f,%.2f) dir=(%.3f,%.3f,%.3f) side=(%.3f,%.3f) tree=(%.2f,%.2f,%.2f)\\n",
                      plyr->pos.x,plyr->pos.y,plyr->pos.z,sp.x,sp.y,
                      plyr->view.pos.x,plyr->view.pos.y,plyr->view.pos.z,
                      plyr->view.dir.x,plyr->view.dir.y,plyr->view.dir.z,
                      side.x,side.z,tree_base.x,tree_base.y,tree_base.z);
                    logged_staging_frame=True;
                }
                renderer_metal_draw_sphere(proof_tux,10,1.0f,0.0f,1.0f,1.0f);
                renderer_metal_draw_sphere(proof_tree,10,0.0f,1.0f,1.0f,1.0f);
            }

            for ( lamp=0; lamp<3; ++lamp ) {
                for ( pair=0; pair<2; ++pair ) {
                    point_t lp = tree_base;
                    float pair_offset = pair ? 0.13f : -0.13f;
                    double model[16];
                    float rr=0.045f, gg=0.050f, bb=0.055f;
                    int active = (staging_lights_time < 0.75 && lamp==2) ||
                                 (staging_lights_time >= 0.75 && staging_lights_time < 1.50 && lamp==1) ||
                                 (staging_lights_time >= 1.50 && lamp==0);

                    lp = move_point( lp, scale_vector(pair_offset, fwd) );
                    model[0]=0.145;model[1]=0;model[2]=0;model[3]=0;
                    model[4]=0;model[5]=0.145;model[6]=0;model[7]=0;
                    model[8]=0;model[9]=0;model[10]=0.145;model[11]=0;
                    model[12]=lp.x;model[13]=tree_base.y+0.72+lamp*0.39;
                    model[14]=lp.z;model[15]=1;

                    if ( active ) {
                        if ( lamp==2 ) { rr=0.95f; gg=0.07f; bb=0.045f; }
                        if ( lamp==1 ) { rr=1.00f; gg=0.58f; bb=0.035f; }
                        if ( lamp==0 ) { rr=0.08f; gg=0.92f; bb=0.16f; }
                    }
                    renderer_metal_draw_sphere( model, 10, rr,gg,bb,1.0f );
                }
            }
        }
#endif
        draw_tux_shadow_metal();
        draw_tux_metal();
    }

    draw_trees();
    draw_tux();
    draw_tux_shadow();

    draw_hud( plyr );

    renderer_resize( width, height );
    renderer_end_frame();
} 

START_KEYBOARD_CB( intro_cb )
{
    if ( release ) return;

    abort_intro( plyr );
}
END_KEYBOARD_CB

void intro_register()
{
    int status = 0;

    register_loop_funcs( INTRO, intro_init, intro_loop, NULL );

    status |= add_keymap_entry(
	INTRO, DEFAULT_CALLBACK, NULL, NULL, intro_cb );

    check_assertion( status == 0, "out of keymap entries" );

    return;
}

