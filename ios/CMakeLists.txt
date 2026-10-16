cmake_minimum_required(VERSION 3.24)
project(TuxRacerModernIOS LANGUAGES C OBJC)

if(NOT CMAKE_SYSTEM_NAME STREQUAL "iOS")
  message(FATAL_ERROR "Configure with -DCMAKE_SYSTEM_NAME=iOS (see README.md)")
endif()

include(FetchContent)
# The original game remains on the desktop build. This is a native iOS
# Metal bootstrap, with a reproducible SDL2 source version.
set(SDL_SHARED OFF CACHE BOOL "" FORCE)
set(SDL_STATIC ON CACHE BOOL "" FORCE)
set(SDL_TEST OFF CACHE BOOL "" FORCE)
# New iOS SDKs no longer expose legacy OSAtomicCompareAndSwap32Barrier.
# Select Clang/GCC atomic builtins for SDL_spinlock.c instead.
set(SDL_GCC_ATOMICS ON CACHE BOOL "Use compiler atomic builtins" FORCE)
FetchContent_Declare(SDL2
  GIT_REPOSITORY https://github.com/libsdl-org/SDL.git
  GIT_TAG release-2.30.12
  GIT_SHALLOW TRUE
)
FetchContent_MakeAvailable(SDL2)

add_executable(TuxRacerModernIOS MACOSX_BUNDLE metal_smoke_main.m)
set_target_properties(TuxRacerModernIOS PROPERTIES
  C_STANDARD 99
  C_STANDARD_REQUIRED ON
  C_EXTENSIONS OFF
)
# The iOS Xcode toolchain can leave CMAKE_C_COMPILE_FEATURES empty during
# cross-configuration; do not require feature-table detection here.
target_link_libraries(TuxRacerModernIOS PRIVATE SDL2::SDL2 SDL2::SDL2main
  "-framework Metal" "-framework QuartzCore" "-framework Foundation")
target_include_directories(TuxRacerModernIOS PRIVATE ${sdl2_SOURCE_DIR}/include)
set_target_properties(TuxRacerModernIOS PROPERTIES
  MACOSX_BUNDLE_INFO_PLIST "${CMAKE_CURRENT_SOURCE_DIR}/Info.plist"
  XCODE_ATTRIBUTE_PRODUCT_BUNDLE_IDENTIFIER "org.skepticllc.tuxracermodern.ios"
  XCODE_ATTRIBUTE_TARGETED_DEVICE_FAMILY "1"
  XCODE_ATTRIBUTE_IPHONEOS_DEPLOYMENT_TARGET "15.0"
  XCODE_ATTRIBUTE_CODE_SIGN_STYLE "Automatic"
  XCODE_ATTRIBUTE_GENERATE_INFOPLIST_FILE "NO"
)
