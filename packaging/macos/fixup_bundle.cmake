# CMake BundleUtilities pass for the public macOS bundle.
cmake_minimum_required(VERSION 3.24)

if(NOT DEFINED APP OR APP STREQUAL "")
    message(FATAL_ERROR "APP must point to the .app bundle")
endif()

if(NOT DEFINED SEARCH_DIRS)
    set(SEARCH_DIRS "")
endif()

if(NOT DEFINED EXTRA_LIBS)
    set(EXTRA_LIBS "")
endif()

include(BundleUtilities)
set(BU_CHMOD_BUNDLE_ITEMS ON)

message(STATUS "Fixing up macOS bundle: ${APP}")
message(STATUS "Dependency search dirs: ${SEARCH_DIRS}")
message(STATUS "Explicit runtime libraries: ${EXTRA_LIBS}")

fixup_bundle("${APP}" "${EXTRA_LIBS}" "${SEARCH_DIRS}")
verify_app("${APP}")
