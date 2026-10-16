# Tux Racer Modern's narrowly scoped SDL2 2.32.x iOS 26+ backport.
#
# Reason: SDL2's legacy UIKit entrypoint invokes SDL_main before UIScene
# connects, and UIKit_CreateWindow uses initWithFrame instead of
# initWithWindowScene. iOS 27 SDK aborts apps without a scene lifecycle.
#
# This script edits only CMake FetchContent's pinned SDL2 source checkout,
# never the macOS preservation files or checked-in SDL source.
if(NOT DEFINED sdl2_SOURCE_DIR OR NOT EXISTS "${sdl2_SOURCE_DIR}/src/video/uikit/SDL_uikitwindow.m")
  message(FATAL_ERROR "SDL2 source not populated; cannot apply iOS scene patch")
endif()

set(_app_delegate "${sdl2_SOURCE_DIR}/src/video/uikit/SDL_uikitappdelegate.m")
file(READ "${_app_delegate}" _delegate_src)
set(_app_old "    [self performSelector:@selector(postFinishLaunch) withObject:nil afterDelay:0.0];")
set(_app_new "    /* Tux iOS scene bridge calls postFinishLaunch after UIWindowScene connects. */")
if(_delegate_src MATCHES "Tux iOS scene bridge calls postFinishLaunch")
  message(STATUS "SDL2 UIKit scene launch patch already applied")
else()
  string(FIND "${_delegate_src}" "${_app_old}" _app_found)
  if(_app_found EQUAL -1)
    message(FATAL_ERROR "SDL2 appdelegate launch anchor changed; review upstream SDL2 version")
  endif()
  string(REPLACE "${_app_old}" "${_app_new}" _delegate_src "${_delegate_src}")
  file(WRITE "${_app_delegate}" "${_delegate_src}")
  message(STATUS "Patched SDL2: defer SDL_main until UIWindowScene connects")
endif()

# SDL2's launch splash creates a standalone UIWindow via initWithFrame inside
# application:didFinishLaunching, BEFORE a UIWindowScene exists. Our first-party
# scene delegate owns a correctly attached placeholder window instead.
file(READ "${_app_delegate}" _delegate_src)
set(_legacy_splash "#ifdef SDL_IPHONE_LAUNCHSCREEN")
set(_scene_splash "#if 0 /* Tux UIScene delegate manages the launch placeholder */")
if(NOT _delegate_src MATCHES "Tux UIScene delegate manages the launch placeholder")
  string(FIND "${_delegate_src}" "${_legacy_splash}" _legacy_splash_found)
  if(_legacy_splash_found EQUAL -1)
    message(FATAL_ERROR "SDL2 legacy splash anchor changed; inspect upstream source")
  endif()
  string(REPLACE "${_legacy_splash}" "${_scene_splash}" _delegate_src "${_delegate_src}")
  file(WRITE "${_app_delegate}" "${_delegate_src}")
  message(STATUS "Patched SDL2: prevent unattached UIWindow before scene connection")
endif()

set(_uikit_window "${sdl2_SOURCE_DIR}/src/video/uikit/SDL_uikitwindow.m")
file(READ "${_uikit_window}" _window_src)
if(_window_src MATCHES "TuxGetActiveWindowScene")
  message(STATUS "SDL2 UIKit window scene patch already applied")
else()
  set(_import_old "#import \"SDL_uikitview.h\"")
  set(_import_new "extern UIWindowScene *TuxGetActiveWindowScene(void);\n#import \"SDL_uikitview.h\"")
  set(_window_old "        uiwindow = [[SDL_uikitwindow alloc] initWithFrame:data.uiscreen.bounds];")
  set(_window_new "        UIWindowScene *activeScene = TuxGetActiveWindowScene();\n        if (activeScene == nil) {\n            return SDL_SetError(\"Tux: UIWindowScene not connected before SDL_CreateWindow\");\n        }\n        uiwindow = [[SDL_uikitwindow alloc] initWithWindowScene:activeScene];\n        uiwindow.frame = activeScene.coordinateSpace.bounds;")

  string(FIND "${_window_src}" "${_import_old}" _import_found)
  string(FIND "${_window_src}" "${_window_old}" _window_found)
  if(_import_found EQUAL -1 OR _window_found EQUAL -1)
    message(FATAL_ERROR "SDL2 UIKit window anchors changed; review pinned SDL2 source")
  endif()
  string(REPLACE "${_import_old}" "${_import_new}" _window_src "${_window_src}")
  string(REPLACE "${_window_old}" "${_window_new}" _window_src "${_window_src}")
  file(WRITE "${_uikit_window}" "${_window_src}")
  message(STATUS "Patched SDL2: create Metal UIWindow within connected UIWindowScene")
endif()
