cmake_minimum_required(VERSION 3.24)
project(tuxracer-modern VERSION 0.1.9 LANGUAGES C CXX)

set(CMAKE_C_STANDARD 99)
set(CMAKE_C_STANDARD_REQUIRED ON)
set(CMAKE_CXX_STANDARD 11)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

option(TUXRACER_WARNINGS "Enable useful compiler warnings" ON)

find_package(OpenGL REQUIRED)
find_package(TCL REQUIRED)
find_package(SDL2 REQUIRED CONFIG)
find_package(SDL2_mixer REQUIRED CONFIG)

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
    SDL2::SDL2
    SDL2_mixer::SDL2_mixer
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
