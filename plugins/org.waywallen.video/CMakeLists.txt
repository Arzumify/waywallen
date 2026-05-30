find_package(Vulkan REQUIRED)
find_package(Threads REQUIRED)

add_executable(waywallen-video-renderer
    src/main.cpp
)
set_target_properties(waywallen-video-renderer PROPERTIES
    INSTALL_RPATH "${WAYWALLEN_PLUGIN_BIN_RPATH}"
)
target_compile_features(waywallen-video-renderer PRIVATE cxx_std_20)
set_target_properties(waywallen-video-renderer PROPERTIES CXX_SCAN_FOR_MODULES ON)
target_compile_options(waywallen-video-renderer PRIVATE
    -Wall -Wextra -Wpedantic
    -Wno-missing-field-initializers
)

target_link_libraries(waywallen-video-renderer
    PRIVATE
        waywallen::bridge
        wavsen::video
        wavsen::audio
        rstd::log
        Vulkan::Vulkan
        Threads::Threads
)

set(_VIDEO_PLUGIN_DIR ${CMAKE_INSTALL_DATADIR}/waywallen/plugins/org.waywallen.video)

install(TARGETS waywallen-video-renderer
    RUNTIME DESTINATION ${_VIDEO_PLUGIN_DIR}/bin
)

install(FILES
    ${CMAKE_CURRENT_SOURCE_DIR}/plugin.toml
    ${CMAKE_CURRENT_SOURCE_DIR}/video.lua
    ${CMAKE_CURRENT_SOURCE_DIR}/files.txt
    DESTINATION ${_VIDEO_PLUGIN_DIR}
)
