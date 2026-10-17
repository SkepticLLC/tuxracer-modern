/*
 * UIKit UIScene lifecycle bridge for Tux Racer Modern (iOS 26+).
 * SDL2 2.32.x launches using an application delegate; iOS 27 SDK requires
 * scene management. SDL_main must not run before the window scene connects.
 *
 * This file is compiled into the application, not into SDL2.
 */
#import <UIKit/UIKit.h>
#import <dispatch/dispatch.h>
#include <stdlib.h>
#include <string.h>
#import "SDL_uikitappdelegate.h"
#include <SDL.h>

/* Return a heap-owned path resolved by NSBundle, not by the process CWD.
 * Caller frees this with free(). UIKit may change the CWD at launch. */
char *TuxIOSCopyBundleResourcePath(void)
{
    const char *path = [[[NSBundle mainBundle] resourcePath] fileSystemRepresentation];
    return path ? strdup(path) : NULL;
}

static __weak UIWindowScene *g_tuxWindowScene = nil;
static BOOL g_gameStarted = NO;

/* Queried by our narrow SDL2 UIKit_CreateWindow compatibility patch. */
UIWindowScene *TuxGetActiveWindowScene(void)
{
    return g_tuxWindowScene;
}

@interface SDLUIKitDelegate (TuxSceneLaunch)
- (void)postFinishLaunch;
@end

@interface TuxSceneDelegate : UIResponder <UIWindowSceneDelegate>
@property (nonatomic, strong) UIWindow *window;
@end

@implementation TuxSceneDelegate

- (void)scene:(UIScene *)scene
    willConnectToSession:(UISceneSession *)session
                 options:(UISceneConnectionOptions *)options
{
    (void)session;
    (void)options;
    if (![scene isKindOfClass:[UIWindowScene class]]) {
        NSLog(@"TuxSceneDelegate expected UIWindowScene, got %@", scene);
        return;
    }

    UIWindowScene *windowScene = (UIWindowScene *)scene;
    g_tuxWindowScene = windowScene;

    /* Brief placeholder until SDL2 constructs its Metal-backed UIWindow. */
    UIWindow *placeholder = [[UIWindow alloc] initWithWindowScene:windowScene];
    UIViewController *controller = [[UIViewController alloc] init];
    controller.view.backgroundColor = [UIColor colorWithRed:0.035 green:0.11 blue:0.19 alpha:1.0];
    placeholder.rootViewController = controller;
    [placeholder makeKeyAndVisible];
    self.window = placeholder;

    /* SDL2's application delegate has already called SDL_SetMainReady().
     * Crucially, start SDL_main AFTER UIKit connects the scene. */
    dispatch_async(dispatch_get_main_queue(), ^{
        if (!g_gameStarted) {
            g_gameStarted = YES;
            SDLUIKitDelegate *delegate = [SDLUIKitDelegate sharedAppDelegate];
            [delegate postFinishLaunch];
        }
    });
}

- (void)sceneDidDisconnect:(UIScene *)scene
{
    if (scene == g_tuxWindowScene) {
        g_tuxWindowScene = nil;
    }
    self.window = nil;
}

/* SDL2 historically receives app-wide notifications. Scene-wide callbacks
 * are the canonical iOS 26+ UI lifecycle. Forward to SDL's public event
 * queue once the game has started; avoid using SDL private APIs. */
- (void)sceneDidBecomeActive:(UIScene *)scene
{
    (void)scene;
    if (g_gameStarted) {
        SDL_Event event = {0};
        event.type = SDL_APP_DIDENTERFOREGROUND;
        SDL_PushEvent(&event);
    }
}

- (void)sceneWillResignActive:(UIScene *)scene
{
    (void)scene;
    if (g_gameStarted) {
        SDL_Event event = {0};
        event.type = SDL_APP_WILLENTERBACKGROUND;
        SDL_PushEvent(&event);
    }
}

- (void)sceneDidEnterBackground:(UIScene *)scene
{
    (void)scene;
    if (g_gameStarted) {
        SDL_Event event = {0};
        event.type = SDL_APP_DIDENTERBACKGROUND;
        SDL_PushEvent(&event);
    }
}

- (void)sceneWillEnterForeground:(UIScene *)scene
{
    (void)scene;
    if (g_gameStarted) {
        SDL_Event event = {0};
        event.type = SDL_APP_WILLENTERFOREGROUND;
        SDL_PushEvent(&event);
    }
}

@end

/* Augment SDL2's EXISTING app delegate with the required scene configuration
 * selector. This category ADDS a method; it does not override any SDL2 method.
 */
@implementation SDLUIKitDelegate (TuxSceneLaunch)

- (UISceneConfiguration *)application:(UIApplication *)application
    configurationForConnectingSceneSession:(UISceneSession *)connectingSceneSession
                                   options:(UISceneConnectionOptions *)options
{
    (void)application;
    (void)options;
    UISceneConfiguration *config =
        [[UISceneConfiguration alloc] initWithName:@"TuxWindowScene"
                                      sessionRole:connectingSceneSession.role];
    config.delegateClass = [TuxSceneDelegate class];
    return config;
}

@end
