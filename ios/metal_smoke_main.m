/*
 * Tux Racer Modern iOS Metal bring-up.
 * This is a platform smoke test, NOT the Tux Racer game engine.
 * SDL2 iOS bootstrap supplies UIApplicationMain via SDL_main.
 */
#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
#import <QuartzCore/CAMetalLayer.h>
#include <SDL.h>
#include <SDL_metal.h>
#include <stdbool.h>
#include <stdio.h>

int main(int argc, char **argv)
{
    (void)argc; (void)argv;
    if (SDL_Init(SDL_INIT_VIDEO | SDL_INIT_GAMECONTROLLER) != 0) {
        fprintf(stderr, "SDL initialization failed: %s\n", SDL_GetError());
        return 1;
    }

    SDL_Window *window = SDL_CreateWindow("Tux Racer Modern iOS",
        SDL_WINDOWPOS_UNDEFINED, SDL_WINDOWPOS_UNDEFINED, 1280, 720,
        SDL_WINDOW_METAL | SDL_WINDOW_ALLOW_HIGHDPI | SDL_WINDOW_FULLSCREEN);
    if (!window) {
        fprintf(stderr, "SDL window failed: %s\n", SDL_GetError());
        SDL_Quit();
        return 2;
    }

    SDL_MetalView view = SDL_Metal_CreateView(window);
    if (!view) {
        fprintf(stderr, "SDL Metal view failed: %s\n", SDL_GetError());
        SDL_DestroyWindow(window);
        SDL_Quit();
        return 3;
    }

    CAMetalLayer *layer = (__bridge CAMetalLayer *)SDL_Metal_GetLayer(view);
    id<MTLDevice> device = MTLCreateSystemDefaultDevice();
    if (!device) {
        fprintf(stderr, "Metal device unavailable\n");
        SDL_Metal_DestroyView(view);
        SDL_DestroyWindow(window);
        SDL_Quit();
        return 4;
    }

    layer.device = device;
    layer.pixelFormat = MTLPixelFormatBGRA8Unorm;
    layer.framebufferOnly = YES;
    id<MTLCommandQueue> queue = [device newCommandQueue];
    bool running = true;
    bool suspended = false;

    while (running) {
        SDL_Event event;
        while (SDL_PollEvent(&event)) {
            if (event.type == SDL_QUIT) running = false;
            if (event.type == SDL_APP_WILLENTERBACKGROUND ||
                event.type == SDL_APP_DIDENTERBACKGROUND) {
                suspended = true;
            }
            if (event.type == SDL_APP_WILLENTERFOREGROUND ||
                event.type == SDL_APP_DIDENTERFOREGROUND) {
                suspended = false;
            }
        }
        if (!running) break;
        if (suspended) {
            SDL_Delay(30);
            continue;
        }
        @autoreleasepool {
            int width = 0, height = 0;
            SDL_Metal_GetDrawableSize(window, &width, &height);
            if (width <= 0 || height <= 0) {
                SDL_Delay(16);
                continue;
            }
            layer.drawableSize = CGSizeMake(width, height);
            id<CAMetalDrawable> drawable = [layer nextDrawable];
            if (!drawable) {
                SDL_Delay(16);
                continue;
            }
            MTLRenderPassDescriptor *pass = [MTLRenderPassDescriptor renderPassDescriptor];
            pass.colorAttachments[0].texture = drawable.texture;
            pass.colorAttachments[0].loadAction = MTLLoadActionClear;
            pass.colorAttachments[0].storeAction = MTLStoreActionStore;
            pass.colorAttachments[0].clearColor = MTLClearColorMake(0.035, 0.11, 0.19, 1.0);
            id<MTLCommandBuffer> command = [queue commandBuffer];
            id<MTLRenderCommandEncoder> encoder = [command renderCommandEncoderWithDescriptor:pass];
            [encoder endEncoding];
            [command presentDrawable:drawable];
            [command commit];
        }
        SDL_Delay(16);
    }

    SDL_Metal_DestroyView(view);
    SDL_DestroyWindow(window);
    SDL_Quit();
    return 0;
}
