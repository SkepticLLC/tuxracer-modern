#import <AppKit/AppKit.h>
#import <Metal/Metal.h>
#import <QuartzCore/CAMetalLayer.h>
#import <SDL2/SDL.h>
#import <SDL2/SDL_syswm.h>
#include "metal_present.h"

static CAMetalLayer *g_layer = nil;
static NSView *g_host_view = nil;

int metal_present_attach_to_sdl_window( void *opaque_window, void *opaque_device )
{
    @autoreleasepool {
        SDL_Window *window = (SDL_Window *)opaque_window;
        id<MTLDevice> device = (__bridge id<MTLDevice>)opaque_device;
        SDL_SysWMinfo info;

        if ( window == NULL || device == nil ) return 0;

        SDL_VERSION( &info.version );
        if ( !SDL_GetWindowWMInfo( window, &info ) ) return 0;

        NSWindow *nswindow = info.info.cocoa.window;
        if ( nswindow == nil || nswindow.contentView == nil ) return 0;

        g_host_view = nswindow.contentView;
        g_host_view.wantsLayer = YES;

        g_layer = [CAMetalLayer layer];
        g_layer.device = device;
        g_layer.pixelFormat = MTLPixelFormatBGRA8Unorm;
        g_layer.framebufferOnly = YES;
        g_layer.opaque = YES;
        g_layer.contentsScale = nswindow.backingScaleFactor;
        g_layer.frame = g_host_view.bounds;
        g_layer.hidden = YES;

        [g_host_view.layer addSublayer:g_layer];
        return 1;
    }
}

void metal_present_resize( int drawable_width, int drawable_height )
{
    @autoreleasepool {
        if ( g_layer == nil || g_host_view == nil ) return;
        g_layer.frame = g_host_view.bounds;
        g_layer.drawableSize = CGSizeMake( drawable_width, drawable_height );
    }
}

void *metal_present_next_drawable( void )
{
    @autoreleasepool {
        if ( g_layer == nil || g_layer.hidden ) return NULL;
        id<CAMetalDrawable> drawable = [g_layer nextDrawable];
        return (__bridge_retained void *)drawable;
    }
}

void *metal_present_layer( void )
{
    return (__bridge void *)g_layer;
}

void metal_present_set_visible( int visible )
{
    @autoreleasepool {
        if ( g_layer != nil ) g_layer.hidden = visible ? NO : YES;
    }
}

void metal_present_shutdown( void )
{
    @autoreleasepool {
        [g_layer removeFromSuperlayer];
        g_layer = nil;
        g_host_view = nil;
    }
}
