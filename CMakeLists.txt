cmake_minimum_required(VERSION 3.24)
project(tuxracer-modern VERSION 0.1.9 LANGUAGES C CXX)

set(CMAKE_C_STANDARD 99)
set(CMAKE_C_STANDARD_REQUIRED ON)
set(CMAKE_CXX_STANDARD 11)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

option(TUXRACER_WARNINGS "Enable useful compiler warnings" ON)
option(TUXRACER_BUNDLED_SDL2
       "Build pinned classic SDL2/SDL2_mixer statically for release packaging"
       OFF)

find_package(OpenGL REQUIRED)
find_package(TCL REQUIRED)

if(TUXRACER_BUNDLED_SDL2)
    include(FetchContent)

    message(STATUS "Tux Racer release build: using pinned classic SDL2 2.32.10")
    message(STATUS "Tux Racer release build: using pinned SDL2_mixer 2.8.2")

    # Classic SDL2. Build static only so the public macOS app has no SDL
    # runtime dylib dependency and no dependency on Homebrew/sdl2-compat/SDL3.
    set(BUILD_SHARED_LIBS OFF CACHE BOOL "" FORCE)
    set(SDL_SHARED OFF CACHE BOOL "" FORCE)
    set(SDL_STATIC ON CACHE BOOL "" FORCE)
    set(SDL_TEST OFF CACHE BOOL "" FORCE)
    set(SDL_TESTS OFF CACHE BOOL "" FORCE)
    set(SDL_INSTALL_TESTS OFF CACHE BOOL "" FORCE)
    set(SDL2_DISABLE_INSTALL ON CACHE BOOL "" FORCE)

    FetchContent_Declare(
        SDL2
        URL https://github.com/libsdl-org/SDL/releases/download/release-2.32.10/SDL2-2.32.10.tar.gz
        URL_HASH SHA256=5f5993c530f084535c65a6879e9b26ad441169b3e25d789d83287040a9ca5165
        DOWNLOAD_EXTRACT_TIMESTAMP TRUE
    )
    FetchContent_MakeAvailable(SDL2)

    # The original preservation data only contains WAV sound effects and
    # Impulse Tracker (.it) music. Keep SDL2_mixer intentionally minimal:
    # WAV plus vendored/static libxmp for IT/MOD-family tracker music.
    set(BUILD_SHARED_LIBS OFF CACHE BOOL "" FORCE)
    set(SDL2MIXER_INSTALL OFF CACHE BOOL "" FORCE)
    set(SDL2MIXER_SAMPLES OFF CACHE BOOL "" FORCE)
    set(SDL2MIXER_DEPS_SHARED OFF CACHE BOOL "" FORCE)
    set(SDL2MIXER_VENDORED ON CACHE BOOL "" FORCE)

    set(SDL2MIXER_FLAC OFF CACHE BOOL "" FORCE)
    set(SDL2MIXER_GME OFF CACHE BOOL "" FORCE)
    set(SDL2MIXER_MOD ON CACHE BOOL "" FORCE)
    set(SDL2MIXER_MOD_MODPLUG OFF CACHE BOOL "" FORCE)
    set(SDL2MIXER_MOD_XMP ON CACHE BOOL "" FORCE)
    set(SDL2MIXER_MP3 OFF CACHE BOOL "" FORCE)
    set(SDL2MIXER_MIDI OFF CACHE BOOL "" FORCE)
    set(SDL2MIXER_OPUS OFF CACHE BOOL "" FORCE)
    set(SDL2MIXER_VORBIS "" CACHE STRING "" FORCE)
    set(SDL2MIXER_WAVPACK OFF CACHE BOOL "" FORCE)
    set(SDL2MIXER_WAVE ON CACHE BOOL "" FORCE)

    FetchContent_Declare(
        SDL2_mixer
        URL https://github.com/libsdl-org/SDL_mixer/releases/download/release-2.8.2/SDL2_mixer-2.8.2.tar.gz
        URL_HASH SHA256=938dff531d00ace2296557a6599abe6f34599e2f34f0a4a08a397e2ccac8b8f7
        DOWNLOAD_EXTRACT_TIMESTAMP TRUE
    )
    FetchContent_MakeAvailable(SDL2_mixer)

    set(TUXRACER_SDL_TARGET SDL2::SDL2-static)
    set(TUXRACER_SDL_MIXER_TARGET SDL2_mixer::SDL2_mixer-static)
else()
    find_package(SDL2 REQUIRED CONFIG)
    find_package(SDL2_mixer REQUIRED CONFIG)
    set(TUXRACER_SDL_TARGET SDL2::SDL2)
    set(TUXRACER_SDL_MIXER_TARGET SDL2_mixer::SDL2_mixer)
endif()

configure_file(cmake/config.h.in ${CMAKE_CURRENT_BINARY_DIR}/generated/config.h @ONLY)
file(GLOB TUXRACER_C_SOURCES CONFIGURE_DEPENDS src/*.c)
file(GLOB TUXRACER_CXX_SOURCES CONFIGURE_DEPENDS src/*.cpp)
add_executable(tuxracer ${TUXRACER_C_SOURCES} ${TUXRACER_CXX_SOURCES})

target_compile_definitions(tuxracer PRIVATE HAVE_CONFIG_H=1)
target_include_directories(tuxracer PRIVATE
    ${CMAKE_CURRENT_BINARY_DIR}/generated
    ${TCL_INCLUDE_PATH}
)

target_link_libraries(tuxracer PRIVATE
    OpenGL::GL
    ${TCL_LIBRARY}
    ${TUXRACER_SDL_TARGET}
    ${TUXRACER_SDL_MIXER_TARGET}
)

if(APPLE)
    target_compile_definitions(tuxracer PRIVATE GL_SILENCE_DEPRECATION=1)
    target_link_libraries(tuxracer PRIVATE OpenGL::GLU)
elseif(WIN32)
    target_link_libraries(tuxracer PRIVATE OpenGL::GLU)
else()
    target_link_libraries(tuxracer PRIVATE OpenGL::GLU m)
endif()

if(TUXRACER_WARNINGS)
    if(MSVC)
        target_compile_options(tuxracer PRIVATE /W3)
    else()
        target_compile_options(tuxracer PRIVATE -Wall -Wextra -Wno-unused-parameter -Wno-deprecated-declarations)
    endif()
endif()

# During development, running from the build tree uses this copied data directory.
add_custom_command(TARGET tuxracer POST_BUILD
    COMMAND ${CMAKE_COMMAND} -E copy_directory
            ${CMAKE_CURRENT_SOURCE_DIR}/data
            $<TARGET_FILE_DIR:tuxracer>/data)
