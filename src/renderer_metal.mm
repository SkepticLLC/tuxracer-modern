/*
 * Initial Metal probe for Tux Racer Modern.
 *
 * This does not present pixels yet.  It proves that the v0.2 renderer branch
 * can create and address the native Apple GPU independently of legacy OpenGL.
 */
#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
#include "renderer_metal.h"

static id<MTLDevice> g_probe_device = nil;
static char g_device_name[256] = {0};

int renderer_metal_probe( void )
{
    @autoreleasepool {
        if ( g_probe_device == nil ) {
            g_probe_device = MTLCreateSystemDefaultDevice();
            if ( g_probe_device == nil ) {
                return 0;
            }

            const char *name = [[g_probe_device name] UTF8String];
            if ( name != NULL ) {
                snprintf( g_device_name, sizeof(g_device_name), "%s", name );
            }
        }
        return 1;
    }
}

const char *renderer_metal_device_name( void )
{
    return g_device_name[0] != '\0' ? g_device_name : "Unavailable";
}
