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
    # Iter 2: compile the NV12→RGBA compute shader at build time. The
    # `--vn` flag emits a C header with the SPIR-V words as a const
    # uint32_t array, which yuv_to_rgba.cpp #include's directly.
    find_program(GLSLANG_VALIDATOR
        NAMES glslangValidator
        DOC   "GLSL → SPIR-V compiler used to bake video plugin shaders")
    if(NOT GLSLANG_VALIDATOR)
        message(FATAL_ERROR
            "libs/ffmpeg: glslangValidator not found in PATH — required to "
            "build waywallen::ffmpeg_vk's NV12→RGBA shader. Install Vulkan "
            "SDK or `glslang` distro package, or set GLSLANG_VALIDATOR.")
    endif()

    set(_ww_shader_src ${CMAKE_CURRENT_SOURCE_DIR}/shaders/nv12_to_rgba.comp)
    set(_ww_shader_hdr ${CMAKE_CURRENT_BINARY_DIR}/generated/nv12_to_rgba.spv.h)
    add_custom_command(
        OUTPUT  ${_ww_shader_hdr}
        COMMAND ${CMAKE_COMMAND} -E make_directory ${CMAKE_CURRENT_BINARY_DIR}/generated
        COMMAND ${GLSLANG_VALIDATOR} -V --vn nv12_to_rgba_spv
                -o ${_ww_shader_hdr} ${_ww_shader_src}
        DEPENDS ${_ww_shader_src}
        COMMENT "Compiling NV12→RGBA compute shader"
        VERBATIM
    )

    add_library(waywallen_ffmpeg_vk STATIC
        src/vk_device.cpp
        src/video_decoder.cpp
        src/yuv_to_rgba.cpp
        ${_ww_shader_hdr}
    )
    add_library(waywallen::ffmpeg_vk ALIAS waywallen_ffmpeg_vk)

    target_compile_features(waywallen_ffmpeg_vk PUBLIC cxx_std_20)
    target_compile_options(waywallen_ffmpeg_vk PRIVATE
        -Wall -Wextra -Wpedantic -Wno-missing-field-initializers
    )
    target_include_directories(waywallen_ffmpeg_vk
        PUBLIC
            ${CMAKE_CURRENT_SOURCE_DIR}/src
        PRIVATE
            ${CMAKE_CURRENT_BINARY_DIR}/generated
    )
    target_link_libraries(waywallen_ffmpeg_vk
        PUBLIC
            Vulkan::Vulkan
        PRIVATE
            PkgConfig::WW_AVFORMAT
            PkgConfig::WW_AVCODEC
            PkgConfig::WW_AVUTIL
            PkgConfig::WW_SWSCALE
    )
    set_property(TARGET waywallen_ffmpeg_vk PROPERTY POSITION_INDEPENDENT_CODE ON)
endif()
