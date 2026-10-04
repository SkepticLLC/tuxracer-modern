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
#include "winsys.h"
#include "joystick.h"
#include "audio.h"

/* Windowing System Abstraction Layer */
/* Abstracts creation of windows, handling of events, etc. */

#if defined( HAVE_SDL )

#if defined( HAVE_SDL_MIXER )
#   include <SDL_mixer.h>
#endif

/* SDL2 preservation layer.  Keep the historical winsys API so the game
 * logic remains untouched while replacing only the obsolete SDL 1.2 calls. */
static SDL_Window *window = NULL;
static SDL_GLContext gl_context = NULL;
static winsys_display_func_t display_func = NULL;
static winsys_idle_func_t idle_func = NULL;
static winsys_reshape_func_t reshape_func = NULL;
static winsys_keyboard_func_t keyboard_func = NULL;
static winsys_mouse_func_t mouse_func = NULL;
static winsys_motion_func_t motion_func = NULL;
static winsys_motion_func_t passive_motion_func = NULL;
static winsys_atexit_func_t atexit_func = NULL;
static bool_t redisplay = False;
static bool_t key_repeat_enabled = False;

void winsys_post_redisplay() { redisplay = True; }
void winsys_set_display_func( winsys_display_func_t func ) { display_func = func; }
void winsys_set_idle_func( winsys_idle_func_t func ) { idle_func = func; }
void winsys_set_reshape_func( winsys_reshape_func_t func ) { reshape_func = func; }
void winsys_set_keyboard_func( winsys_keyboard_func_t func ) { keyboard_func = func; }
void winsys_set_mouse_func( winsys_mouse_func_t func ) { mouse_func = func; }
void winsys_set_motion_func( winsys_motion_func_t func ) { motion_func = func; }
void winsys_set_passive_motion_func( winsys_motion_func_t func ) { passive_motion_func = func; }

void winsys_swap_buffers() { SDL_GL_SwapWindow( window ); }
void winsys_warp_pointer( int x, int y ) { SDL_WarpMouseInWindow( window, x, y ); }
void winsys_show_cursor( bool_t visible ) { SDL_ShowCursor( visible ? SDL_ENABLE : SDL_DISABLE ); }
void winsys_enable_key_repeat( bool_t enabled ) { key_repeat_enabled = enabled; }

void winsys_get_drawable_size( int *w, int *h )
{
    int dw = getparam_x_resolution();
    int dh = getparam_y_resolution();

    if ( window != NULL ) {
        SDL_GL_GetDrawableSize( window, &dw, &dh );
    }

    if ( w ) *w = dw;
    if ( h ) *h = dh;
}

void winsys_get_window_size( int *w, int *h )
{
    int ww = getparam_x_resolution();
    int wh = getparam_y_resolution();
    if ( window != NULL ) {
        SDL_GetWindowSize( window, &ww, &wh );
    }
    if ( w ) *w = ww;
    if ( h ) *h = wh;
}

static void setup_sdl_video_mode()
{
    Uint32 flags = SDL_WINDOW_OPENGL | SDL_WINDOW_ALLOW_HIGHDPI;
    int width = getparam_x_resolution();
    int height = getparam_y_resolution();

    if ( !getparam_fullscreen() ) flags |= SDL_WINDOW_RESIZABLE;

    if ( window == NULL ) {
        window = SDL_CreateWindow( "Tux Racer", SDL_WINDOWPOS_CENTERED,
                                   SDL_WINDOWPOS_CENTERED, width, height, flags );
        if ( window == NULL ) handle_system_error( 1, "Couldn't create window: %s", SDL_GetError() );
        gl_context = SDL_GL_CreateContext( window );
        if ( gl_context == NULL ) handle_system_error( 1, "Couldn't create OpenGL context: %s", SDL_GetError() );
    } else {
        SDL_SetWindowSize( window, width, height );
    }

    if ( getparam_fullscreen() ) {
        if ( SDL_SetWindowFullscreen( window, SDL_WINDOW_FULLSCREEN_DESKTOP ) != 0 )
            handle_system_error( 1, "Couldn't enter fullscreen mode: %s", SDL_GetError() );
    } else {
        SDL_SetWindowFullscreen( window, 0 );
    }
}

void winsys_init( int *argc, char **argv, char *window_title, char *icon_title )
{
    (void)argc; (void)argv; (void)icon_title;
    if ( SDL_Init( SDL_INIT_VIDEO ) < 0 ) handle_error( 1, "Couldn't initialize SDL: %s", SDL_GetError() );
    SDL_GL_SetAttribute( SDL_GL_DOUBLEBUFFER, 1 );
#if defined( USE_STENCIL_BUFFER )
    SDL_GL_SetAttribute( SDL_GL_STENCIL_SIZE, 8 );
#endif
    setup_sdl_video_mode();
    SDL_SetWindowTitle( window, window_title );
}

void winsys_shutdown()
{
    shutdown_joystick();
    if ( gl_context ) { SDL_GL_DeleteContext( gl_context ); gl_context = NULL; }
    if ( window ) { SDL_DestroyWindow( window ); window = NULL; }
    SDL_Quit();
}

static bool_t translate_sdl2_key( SDL_Keycode sym, unsigned int *key, bool_t *special )
{
    *special = True;
    switch ( sym ) {
    case SDLK_KP_0: *key = WSK_KP0; break;
    case SDLK_KP_1: *key = WSK_KP1; break;
    case SDLK_KP_2: *key = WSK_KP2; break;
    case SDLK_KP_3: *key = WSK_KP3; break;
    case SDLK_KP_4: *key = WSK_KP4; break;
    case SDLK_KP_5: *key = WSK_KP5; break;
    case SDLK_KP_6: *key = WSK_KP6; break;
    case SDLK_KP_7: *key = WSK_KP7; break;
    case SDLK_KP_8: *key = WSK_KP8; break;
    case SDLK_KP_9: *key = WSK_KP9; break;
    case SDLK_KP_PERIOD: *key = WSK_KP_PERIOD; break;
    case SDLK_KP_DIVIDE: *key = WSK_KP_DIVIDE; break;
    case SDLK_KP_MULTIPLY: *key = WSK_KP_MULTIPLY; break;
    case SDLK_KP_MINUS: *key = WSK_KP_MINUS; break;
    case SDLK_KP_PLUS: *key = WSK_KP_PLUS; break;
    case SDLK_KP_ENTER: *key = WSK_KP_ENTER; break;
    case SDLK_KP_EQUALS: *key = WSK_KP_EQUALS; break;
    case SDLK_UP: *key = WSK_UP; break;
    case SDLK_DOWN: *key = WSK_DOWN; break;
    case SDLK_RIGHT: *key = WSK_RIGHT; break;
    case SDLK_LEFT: *key = WSK_LEFT; break;
    case SDLK_INSERT: *key = WSK_INSERT; break;
    case SDLK_HOME: *key = WSK_HOME; break;
    case SDLK_END: *key = WSK_END; break;
    case SDLK_PAGEUP: *key = WSK_PAGEUP; break;
    case SDLK_PAGEDOWN: *key = WSK_PAGEDOWN; break;
    case SDLK_F1: *key = WSK_F1; break;
    case SDLK_F2: *key = WSK_F2; break;
    case SDLK_F3: *key = WSK_F3; break;
    case SDLK_F4: *key = WSK_F4; break;
    case SDLK_F5: *key = WSK_F5; break;
    case SDLK_F6: *key = WSK_F6; break;
    case SDLK_F7: *key = WSK_F7; break;
    case SDLK_F8: *key = WSK_F8; break;
    case SDLK_F9: *key = WSK_F9; break;
    case SDLK_F10: *key = WSK_F10; break;
    case SDLK_F11: *key = WSK_F11; break;
    case SDLK_F12: *key = WSK_F12; break;
    case SDLK_F13: *key = WSK_F13; break;
    case SDLK_F14: *key = WSK_F14; break;
    case SDLK_F15: *key = WSK_F15; break;
    case SDLK_NUMLOCKCLEAR: *key = WSK_NUMLOCK; break;
    case SDLK_CAPSLOCK: *key = WSK_CAPSLOCK; break;
    case SDLK_SCROLLLOCK: *key = WSK_SCROLLOCK; break;
    case SDLK_RSHIFT: *key = WSK_RSHIFT; break;
    case SDLK_LSHIFT: *key = WSK_LSHIFT; break;
    case SDLK_RCTRL: *key = WSK_RCTRL; break;
    case SDLK_LCTRL: *key = WSK_LCTRL; break;
    case SDLK_RALT: *key = WSK_RALT; break;
    case SDLK_LALT: *key = WSK_LALT; break;
    case SDLK_RGUI: *key = WSK_RMETA; break;
    case SDLK_LGUI: *key = WSK_LMETA; break;
    case SDLK_RETURN: *key = 13; *special = False; break;
    case SDLK_BACKSPACE: *key = '\b'; *special = False; break;
    case SDLK_TAB: *key = '\t'; *special = False; break;
    case SDLK_ESCAPE: *key = 27; *special = False; break;
    case SDLK_DELETE: *key = 127; *special = False; break;
    default:
        if ( sym >= 0 && sym < 256 ) {
            *key = (unsigned int)sym;
            *special = False;
        } else {
            return False;
        }
    }
    return True;
}

static void translate_mouse_to_game_coords( int in_x, int in_y, int *out_x, int *out_y )
{
    int window_w = 0, window_h = 0;
    int game_w = getparam_x_resolution();
    int game_h = getparam_y_resolution();

    if ( window != NULL ) {
        SDL_GetWindowSize( window, &window_w, &window_h );
    }

    if ( window_w > 0 && window_h > 0 && game_w > 0 && game_h > 0 ) {
        *out_x = (int)( (double)in_x * (double)game_w / (double)window_w );
        *out_y = (int)( (double)in_y * (double)game_h / (double)window_h );
    } else {
        *out_x = in_x;
        *out_y = in_y;
    }
}

void winsys_process_events()
{
    SDL_Event event;
    unsigned int key;
    bool_t special;
    int x, y;

    while ( True ) {
        while ( SDL_PollEvent( &event ) ) {
            switch ( event.type ) {
            case SDL_QUIT:
                winsys_exit( 0 );
                break;
            case SDL_KEYDOWN:
                if ( event.key.repeat && !key_repeat_enabled ) break;
                if ( keyboard_func ) {
                    int raw_x, raw_y;
                    SDL_GetMouseState( &raw_x, &raw_y );
                    translate_mouse_to_game_coords( raw_x, raw_y, &x, &y );
                    if ( translate_sdl2_key( event.key.keysym.sym, &key, &special ) )
                        (*keyboard_func)( key, special, False, x, y );
                }
                break;
            case SDL_KEYUP:
                if ( keyboard_func ) {
                    int raw_x, raw_y;
                    SDL_GetMouseState( &raw_x, &raw_y );
                    translate_mouse_to_game_coords( raw_x, raw_y, &x, &y );
                    if ( translate_sdl2_key( event.key.keysym.sym, &key, &special ) )
                        (*keyboard_func)( key, special, True, x, y );
                }
                break;
            case SDL_MOUSEBUTTONDOWN:
            case SDL_MOUSEBUTTONUP:
                if ( mouse_func ) {
                    translate_mouse_to_game_coords( event.button.x, event.button.y, &x, &y );
                    (*mouse_func)( event.button.button,
                        event.type == SDL_MOUSEBUTTONDOWN ? SDL_PRESSED : SDL_RELEASED,
                        x, y );
                }
                break;
            case SDL_MOUSEMOTION:
                translate_mouse_to_game_coords( event.motion.x, event.motion.y, &x, &y );
                if ( event.motion.state ) {
                    if ( motion_func ) (*motion_func)( x, y );
                } else if ( passive_motion_func ) {
                    (*passive_motion_func)( x, y );
                }
                break;
            case SDL_JOYDEVICEADDED:
                handle_joystick_device_event( 1, event.jdevice.which );
                break;
            case SDL_JOYDEVICEREMOVED:
                handle_joystick_device_event( 0, event.jdevice.which );
                break;
            case SDL_WINDOWEVENT:
                if ( ( event.window.event == SDL_WINDOWEVENT_SIZE_CHANGED ||
                       event.window.event == SDL_WINDOWEVENT_RESIZED ) && reshape_func ) {
                    int logical_w = 0, logical_h = 0;
                    SDL_GetWindowSize( window, &logical_w, &logical_h );
                    (*reshape_func)( logical_w, logical_h );
                }
                break;
            }
        }
        if ( redisplay && display_func ) { redisplay = False; (*display_func)(); }
        else if ( idle_func ) (*idle_func)();
        SDL_Delay( 1 );
    }
}

void winsys_atexit( winsys_atexit_func_t func )
{
    static bool_t called = False;
    check_assertion( called == False, "winsys_atexit called twice" );
    called = True; atexit_func = func;
}

void winsys_exit( int code )
{
    if ( atexit_func ) (*atexit_func)();
    exit( code );
}

#else

/*---------------------------------------------------------------------------*/
/*---------------------------------------------------------------------------*/
/* GLUT version */
/*---------------------------------------------------------------------------*/
/*---------------------------------------------------------------------------*/

static winsys_keyboard_func_t keyboard_func = NULL;

static bool_t redisplay = False;


/*---------------------------------------------------------------------------*/
/*! 
  Requests that the screen be redrawn
  \author  jfpatry
  \date    Created:  2000-10-19
  \date    Modified: 2000-10-19
*/
void winsys_post_redisplay() 
{
    redisplay = True;
}


/*---------------------------------------------------------------------------*/
/*! 
  Sets the display callback
  \author  jfpatry
  \date    Created:  2000-10-19
  \date    Modified: 2000-10-19
*/
void winsys_set_display_func( winsys_display_func_t func )
{
    glutDisplayFunc( func );
}


/*---------------------------------------------------------------------------*/
/*! 
  Sets the idle callback
  \author  jfpatry
  \date    Created:  2000-10-19
  \date    Modified: 2000-10-19
*/
void winsys_set_idle_func( winsys_idle_func_t func )
{
    glutIdleFunc( func );
}


/*---------------------------------------------------------------------------*/
/*! 
  Sets the reshape callback
  \author  jfpatry
  \date    Created:  2000-10-19
  \date    Modified: 2000-10-19
*/
void winsys_set_reshape_func( winsys_reshape_func_t func )
{
    glutReshapeFunc( func );
}


/* Keyboard callbacks */
static void glut_keyboard_cb( unsigned char ch, int x, int y ) 
{
    if ( keyboard_func ) {
	(*keyboard_func)( ch, False, False, x, y );
    }
}

static void glut_special_cb( int key, int x, int y ) 
{
    if ( keyboard_func ) {
	(*keyboard_func)( key, True, False, x, y );
    }
}

static void glut_keyboard_up_cb( unsigned char ch, int x, int y ) 
{
    if ( keyboard_func ) {
	(*keyboard_func)( ch, False, True, x, y );
    }
}

static void glut_special_up_cb( int key, int x, int y ) 
{
    if ( keyboard_func ) {
	(*keyboard_func)( key, True, True, x, y );
    }
}


/*---------------------------------------------------------------------------*/
/*! 
  Sets the keyboard callback
  \author  jfpatry
  \date    Created:  2000-10-19
  \date    Modified: 2000-10-19
*/
void winsys_set_keyboard_func( winsys_keyboard_func_t func )
{
    keyboard_func = func;
}


/*---------------------------------------------------------------------------*/
/*! 
  Sets the mouse button-press callback
  \author  jfpatry
  \date    Created:  2000-10-19
  \date    Modified: 2000-10-19
*/
void winsys_set_mouse_func( winsys_mouse_func_t func )
{
    glutMouseFunc( func );
}


/*---------------------------------------------------------------------------*/
/*! 
  Sets the mouse motion callback (when a mouse button is pressed)
  \author  jfpatry
  \date    Created:  2000-10-19
  \date    Modified: 2000-10-19
*/
void winsys_set_motion_func( winsys_motion_func_t func )
{
    glutMotionFunc( func );
}


/*---------------------------------------------------------------------------*/
/*! 
  Sets the mouse motion callback (when no mouse button is pressed)
  \author  jfpatry
  \date    Created:  2000-10-19
  \date    Modified: 2000-10-19
*/
void winsys_set_passive_motion_func( winsys_motion_func_t func )
{
    glutPassiveMotionFunc( func );
}



/*---------------------------------------------------------------------------*/
/*! 
  Copies the OpenGL back buffer to the front buffer
  \author  jfpatry
  \date    Created:  2000-10-19
  \date    Modified: 2000-10-19
*/
void winsys_swap_buffers()
{
    glutSwapBuffers();
}


/*---------------------------------------------------------------------------*/
/*! 
  Moves the mouse pointer to (x,y)
  \author  jfpatry
  \date    Created:  2000-10-19
  \date    Modified: 2000-10-19
*/
void winsys_warp_pointer( int x, int y )
{
    glutWarpPointer( x, y );
}


/*---------------------------------------------------------------------------*/
/*! 
  Initializes the OpenGL rendering context, and creates a window (or 
  sets up fullscreen mode if selected)
  \author  jfpatry
  \date    Created:  2000-10-19
  \date    Modified: 2000-10-19
*/
void winsys_init( int *argc, char **argv, char *window_title, 
		  char *icon_title )
{
    int width, height;
    int glutWindow;

    glutInit( argc, argv );

#ifdef USE_STENCIL_BUFFER
    glutInitDisplayMode( GLUT_RGBA | GLUT_DEPTH | GLUT_DOUBLE | GLUT_STENCIL );
#else
    glutInitDisplayMode( GLUT_RGBA | GLUT_DEPTH | GLUT_DOUBLE );
#endif 

    /* Create a window */
    if ( getparam_fullscreen() ) {
	glutInitWindowPosition( 0, 0 );
	glutEnterGameMode();
    } else {
	/* Set the initial window size */
	width = getparam_x_resolution();
	height = getparam_y_resolution();
	glutInitWindowSize( width, height );

	if ( getparam_force_window_position() ) {
	    glutInitWindowPosition( 0, 0 );
	}

	glutWindow = glutCreateWindow( window_title );

	if ( glutWindow == 0 ) {
	    handle_error( 1, "Couldn't create a window." );
	}
    }
}


/*---------------------------------------------------------------------------*/
/*! 
  Deallocates resources in preparation for program termination
  \author  jfpatry
  \date    Created:  2000-10-19
  \date    Modified: 2000-10-19
*/
void winsys_shutdown()
{
    if ( getparam_fullscreen() ) {
	glutLeaveGameMode();
    }
}

/*---------------------------------------------------------------------------*/
/*! 
  Enables/disables key repeat messages from being generated
  \return  
  \author  jfpatry
  \date    Created:  2000-10-19
  \date    Modified: 2000-10-19
*/
void winsys_enable_key_repeat( bool_t enabled )
{
    glutIgnoreKeyRepeat(!enabled);
}

/*---------------------------------------------------------------------------*/
/*! 
  Shows/hides mouse cursor
  \author  jfpatry
  \date    Created:  2000-10-19
  \date    Modified: 2000-10-19
*/
void winsys_show_cursor( bool_t visible )
{
    if ( visible ) {
	glutSetCursor( GLUT_CURSOR_LEFT_ARROW );
    } else {
	glutSetCursor( GLUT_CURSOR_NONE );
    }
}



/*---------------------------------------------------------------------------*/
/*! 
  Processes and dispatches events.  This function never returns.
  \return  No.
  \author  jfpatry
  \date    Created:  2000-10-19
  \date    Modified: 2000-10-19
*/
void winsys_process_events()
{
    /* Set up keyboard callbacks */
    glutKeyboardFunc( glut_keyboard_cb );
    glutKeyboardUpFunc( glut_keyboard_up_cb );
    glutSpecialFunc( glut_special_cb );
    glutSpecialUpFunc( glut_special_up_cb );

    glutMainLoop();
}

/*---------------------------------------------------------------------------*/
/*! 
  Sets the function to be called when program ends.  Note that this
  function should only be called once.
  \author  jfpatry
  \date    Created:  2000-10-20
  \date Modified: 2000-10-20 */
void winsys_atexit( winsys_atexit_func_t func )
{
    static bool_t called = False;

    check_assertion( called == False, "winsys_atexit called twice" );

    called = True;

    atexit(func);
}


/*---------------------------------------------------------------------------*/
/*! 
  Exits the program
  \author  jfpatry
  \date    Created:  2000-10-20
  \date    Modified: 2000-10-20
*/
void winsys_exit( int code )
{
    exit(code);
}

#endif /* defined( HAVE_SDL ) */

/* EOF */
