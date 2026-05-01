cmake_minimum_required(VERSION 3.28)

# Two sibling targets:
#
#   waywallen::ffmpeg     — C++20 module thumbnail extractor; depends on rstd
#                           (consumed by the daemon/UI media-probe path).
#   waywallen::ffmpeg_vk  — plain C++ Vulkan-side helpers shared by the
#                           renderer plugins (image + video). No rstd dep so
#                           the plugins build tree can pull it in directly.
#                           Iter 1 ships waywallen::ffvk::Producer; Iter 2
#                           grows it with FFmpeg-vulkan glue + GPU YUV→RGB.
#
# This file is `add_subdirectory`-d from BOTH plugins/ and ui/ — make each
# target's add_library idempotent so a second invocation is a no-op.

find_package(PkgConfig REQUIRED)
pkg_check_modules(WW_AVFORMAT REQUIRED IMPORTED_TARGET libavformat>=58)
pkg_check_modules(WW_AVCODEC  REQUIRED IMPORTED_TARGET libavcodec>=58)
pkg_check_modules(WW_AVUTIL   REQUIRED IMPORTED_TARGET libavutil>=56)
pkg_check_modules(WW_SWSCALE  REQUIRED IMPORTED_TARGET libswscale>=5)
find_package(Vulkan REQUIRED)

# ---------------------------------------------------------------------------
# waywallen::ffmpeg — module-based thumbnail extractor (rstd-dependent)
# ---------------------------------------------------------------------------
if(TARGET rstd::rstd AND NOT TARGET waywallen_ffmpeg)
    add_library(waywallen_ffmpeg STATIC)
    add_library(waywallen::ffmpeg ALIAS waywallen_ffmpeg)

    target_compile_features(waywallen_ffmpeg PUBLIC cxx_std_20)
    target_compile_options(waywallen_ffmpeg PRIVATE
        -Wall -Wextra -Wpedantic -Wno-missing-field-initializers
    )

    target_sources(waywallen_ffmpeg
        PUBLIC FILE_SET CXX_MODULES FILES
            src/decoder.cppm
    )
    target_sources(waywallen_ffmpeg PRIVATE
        src/decoder.cpp
    )

    target_link_libraries(waywallen_ffmpeg
        PUBLIC
            rstd::rstd
        PRIVATE
            PkgConfig::WW_AVFORMAT
            PkgConfig::WW_AVCODEC
            PkgConfig::WW_AVUTIL
            PkgConfig::WW_SWSCALE
    )
    set_target_properties(waywallen_ffmpeg PROPERTIES CXX_SCAN_FOR_MODULES ON)
elseif(NOT TARGET rstd::rstd AND NOT TARGET waywallen_ffmpeg)
    message(STATUS
        "libs/ffmpeg: rstd::rstd not present — skipping waywallen::ffmpeg "
        "(thumbnail extractor). waywallen::ffmpeg_vk is unaffected.")
endif()

# ---------------------------------------------------------------------------
# waywallen::ffmpeg_vk — plain C++ Vulkan helpers for the renderer plugins
# ---------------------------------------------------------------------------
if(NOT TARGET waywallen_ffmpeg_vk)
    add_library(waywallen_ffmpeg_vk STATIC
        src/vk_device.cpp
    )
    add_library(waywallen::ffmpeg_vk ALIAS waywallen_ffmpeg_vk)

    target_compile_features(waywallen_ffmpeg_vk PUBLIC cxx_std_20)
    target_compile_options(waywallen_ffmpeg_vk PRIVATE
        -Wall -Wextra -Wpedantic -Wno-missing-field-initializers
    )
    target_include_directories(waywallen_ffmpeg_vk PUBLIC
        ${CMAKE_CURRENT_SOURCE_DIR}/src
    )
    target_link_libraries(waywallen_ffmpeg_vk
        PUBLIC
            Vulkan::Vulkan
    )
    set_property(TARGET waywallen_ffmpeg_vk PROPERTY POSITION_INDEPENDENT_CODE ON)
endif()
