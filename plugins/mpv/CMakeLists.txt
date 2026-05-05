find_package(PkgConfig REQUIRED)
pkg_check_modules(MPV REQUIRED IMPORTED_TARGET mpv>=0.33)
pkg_check_modules(EGL REQUIRED IMPORTED_TARGET egl)
pkg_check_modules(GLES REQUIRED IMPORTED_TARGET glesv2)
pkg_check_modules(GBM REQUIRED IMPORTED_TARGET gbm>=21.0)
find_package(Threads REQUIRED)

add_executable(waywallen-mpv-renderer src/main.cpp)
set_target_properties(waywallen-mpv-renderer PROPERTIES 
    INSTALL_RPATH "${WAYWALLEN_BIN_RPATH}"
)
target_compile_features(waywallen-mpv-renderer PRIVATE cxx_std_20)
target_compile_options(waywallen-mpv-renderer PRIVATE
    -Wall -Wextra -Wpedantic
    # Vulkan's VkFoo{STYPE} aggregate init legitimately leaves pNext
    # default-zeroed; the warning is pure noise here.
    -Wno-missing-field-initializers
)

target_link_libraries(waywallen-mpv-renderer
    PRIVATE
        waywallen::bridge
        PkgConfig::MPV
        PkgConfig::EGL
        PkgConfig::GLES
        PkgConfig::GBM
        Threads::Threads
)


install(TARGETS waywallen-mpv-renderer
    RUNTIME DESTINATION ${CMAKE_INSTALL_BINDIR}
)

install(DIRECTORY ${CMAKE_CURRENT_SOURCE_DIR}/renderers/
    DESTINATION ${CMAKE_INSTALL_DATADIR}/waywallen/renderers
    FILES_MATCHING PATTERN "*.toml"
)
