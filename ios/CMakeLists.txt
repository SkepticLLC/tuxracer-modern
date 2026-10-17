cmake_minimum_required(VERSION 3.24)
project(TuxRacerModernIOS LANGUAGES C OBJC)

if(NOT CMAKE_SYSTEM_NAME STREQUAL "iOS")
  message(FATAL_ERROR "Configure with -DCMAKE_SYSTEM_NAME=iOS (see ios/README.md)")
endif()

# iOS 26+ is the minimum supported version; test on SDK 27.
set(CMAKE_OSX_DEPLOYMENT_TARGET "26.0" CACHE STRING "Minimum iOS version" FORCE)

include(FetchContent)
# Metal-only graphics: avoid building deprecated OpenGL ES/Vulkan backends.
set(SDL_SHARED OFF CACHE BOOL "" FORCE)
set(SDL_STATIC ON CACHE BOOL "" FORCE)
set(SDL_TEST OFF CACHE BOOL "" FORCE)
set(SDL_TESTS OFF CACHE BOOL "" FORCE)
set(SDL2_DISABLE_INSTALL ON CACHE BOOL "" FORCE)
set(SDL_OPENGLES OFF CACHE BOOL "Disable unused OpenGL ES backend" FORCE)
set(SDL_VULKAN OFF CACHE BOOL "Disable unused Vulkan backend" FORCE)
set(SDL_METAL ON CACHE BOOL "Enable Metal backend" FORCE)
set(SDL_RENDER_METAL ON CACHE BOOL "Enable SDL Metal renderer" FORCE)
FetchContent_Declare(SDL2
  GIT_REPOSITORY https://github.com/libsdl-org/SDL.git
  GIT_TAG release-2.32.10
  GIT_SHALLOW TRUE
)
FetchContent_MakeAvailable(SDL2)
# Isolated iOS 27 UIScene backport for pinned SDL2; fail if upstream anchors move.
include("${CMAKE_CURRENT_SOURCE_DIR}/patch-sdl2-scene.cmake")

# SDL_spinlock.c checks HAVE_GCC_ATOMICS, not SDL_USE_GCC_ATOMICS.
if(TARGET SDL2-static)
  target_compile_definitions(SDL2-static PRIVATE HAVE_GCC_ATOMICS=1)
endif()

option(TUX_IOS_METAL_SMOKE "Run the known-good dark blue Metal smoke target" OFF)
if(TUX_IOS_METAL_SMOKE)
  set(TUX_IOS_ENTRY metal_smoke_main.m)
else()
  set(TUX_IOS_ENTRY prototype_race.c)
endif()

add_executable(TuxRacerModernIOS MACOSX_BUNDLE
  ${TUX_IOS_ENTRY}
  scene_lifecycle.m
  original_course.c
  "${CMAKE_CURRENT_SOURCE_DIR}/../src/platform/mobile_input.c"
)
target_include_directories(TuxRacerModernIOS PRIVATE
  "${CMAKE_CURRENT_SOURCE_DIR}/../src/platform"
)
# Xcode's Objective-C target defaults can differ from CMake generator
# expressions. Enable ARC at both the Xcode target and per-source level.
# The scene bridge declares a __weak UIWindowScene reference; compiling it
# with manual reference counting fails before the linker runs.
set_source_files_properties(
  scene_lifecycle.m
  PROPERTIES COMPILE_FLAGS "-fobjc-arc"
)
set_target_properties(TuxRacerModernIOS PROPERTIES
  XCODE_ATTRIBUTE_CLANG_ENABLE_OBJC_ARC "YES"
)
set_target_properties(TuxRacerModernIOS PROPERTIES
  C_STANDARD 99
  C_STANDARD_REQUIRED ON
  C_EXTENSIONS OFF
  MACOSX_BUNDLE_INFO_PLIST "${CMAKE_CURRENT_SOURCE_DIR}/Info.plist"
  XCODE_ATTRIBUTE_PRODUCT_BUNDLE_IDENTIFIER "org.skepticllc.tuxracermodern.ios"
  XCODE_ATTRIBUTE_TARGETED_DEVICE_FAMILY "1"
  XCODE_ATTRIBUTE_IPHONEOS_DEPLOYMENT_TARGET "26.0"
  XCODE_ATTRIBUTE_CODE_SIGN_STYLE "Automatic"
  XCODE_ATTRIBUTE_GENERATE_INFOPLIST_FILE "NO"
)
target_link_libraries(TuxRacerModernIOS PRIVATE SDL2::SDL2 SDL2::SDL2main
  "-framework Metal" "-framework QuartzCore" "-framework Foundation")
target_include_directories(TuxRacerModernIOS PRIVATE
  ${sdl2_SOURCE_DIR}/include
  ${sdl2_SOURCE_DIR}/src/video/uikit
)

# Have Xcode copy the entire original, unmodified data directory during
# the native Copy Bundle Resources phase (before signing). A PRE_LINK command
# does not reliably participate in the Xcode resource lifecycle.
set(_tux_original_data "${CMAKE_CURRENT_SOURCE_DIR}/../data")
if(NOT EXISTS "${_tux_original_data}/courses/bunny_hill/course.tcl")
  message(FATAL_ERROR "Missing original Bunny Hill assets: ${_tux_original_data}")
endif()
set_source_files_properties("${_tux_original_data}"
  PROPERTIES MACOSX_PACKAGE_LOCATION "Resources")
target_sources(TuxRacerModernIOS PRIVATE "${_tux_original_data}")
message(STATUS "Xcode app resource: original data/ directory")

# Run the cleanup as an Xcode PRE_LINK step, prior to CodeSign.
# Clean generated app bundles only; do not mutate source checkout metadata.
add_custom_command(TARGET TuxRacerModernIOS PRE_LINK
  COMMAND /bin/sh "${CMAKE_CURRENT_SOURCE_DIR}/prepare-signing.sh"
          "$<TARGET_BUNDLE_DIR:TuxRacerModernIOS>"
  COMMENT "Remove forbidden extended attributes from iOS app before signing"
  VERBATIM
)

# Last line of defense: use the codesign native stripping option when supported.
execute_process(COMMAND /usr/bin/codesign --help
  OUTPUT_VARIABLE _codesign_help_out
  ERROR_VARIABLE _codesign_help_err)
if("${_codesign_help_out}${_codesign_help_err}" MATCHES "strip-disallowed-xattrs")
  set_target_properties(TuxRacerModernIOS PROPERTIES
    XCODE_ATTRIBUTE_OTHER_CODE_SIGN_FLAGS "--strip-disallowed-xattrs")
  message(STATUS "codesign supports --strip-disallowed-xattrs")
endif()
