option(WAYWALLEN_BUILD_IMAGE_PLUGIN "Build the ffmpeg+Vulkan image plugin" ON)
option(WAYWALLEN_BUILD_VIDEO_PLUGIN "Build the ffmpeg+Vulkan video plugin" ON)
option(WAYWALLEN_BUILD_MPV_PLUGIN   "Build the libmpv+EGL/GBM video plugin" OFF)

include(${CMAKE_SOURCE_DIR}/cmake/FetchDeps.cmake)
fetchdeps(${CMAKE_SOURCE_DIR}/deps.json NAMES rstd cubeb wavsen)

add_subdirectory(../bridge waywallen-bridge-build)

if(WAYWALLEN_BUILD_IMAGE_PLUGIN)
    add_subdirectory(image)
endif()

if(WAYWALLEN_BUILD_VIDEO_PLUGIN)
    add_subdirectory(video)
endif()

if(WAYWALLEN_BUILD_MPV_PLUGIN)
    add_subdirectory(mpv)
endif()
