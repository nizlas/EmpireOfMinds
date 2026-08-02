cmake_minimum_required(VERSION 3.22)

# Empire of Minds native GDExtension (N3b.1a build-and-load scaffold).
#
# Produces a shared library (eom_terrain_native) loaded by the project's
# Godot 4.6.2-stable editor/headless binary via game/bin/eom_native.gdextension.
# Build with the CMake presets in this directory (Ninja + MSVC); see
# native/README.md for the reproducible command sequence.
#
# godot-cpp is pinned to the immutable commit of tag `godot-4.5-stable`
# (the newest stable godot-cpp release; godot-cpp 4.6 does not exist —
# upstream v10/master is beta and versioned independently). Extensions
# targeting Godot 4.5 load in 4.6.x per upstream's forward-compatibility
# guarantee; `compatibility_minimum` in the descriptor is 4.5 accordingly.

project(eom_native LANGUAGES CXX)

include(FetchContent)

set(EOM_GODOT_CPP_COMMIT "e83fd0904c13356ed1d4c3d09f8bb9132bdc6b77") # tag: godot-4.5-stable
FetchContent_Declare(
    godot-cpp
    URL "https://github.com/godotengine/godot-cpp/archive/${EOM_GODOT_CPP_COMMIT}.tar.gz"
    URL_HASH SHA256=d4c03daf46c8bef4544614182b0762c3e32789151c7f8f44e8eb2053d5cddeba
    DOWNLOAD_EXTRACT_TIMESTAMP TRUE
)

# Editor-feature binding: the only current consumer is the dev editor/headless
# binary (headless tests + terrain preview). The engine is a standard
# single-precision build; PackedFloat64Array elements are float64 regardless.
set(GODOTCPP_TARGET "editor" CACHE STRING "godot-cpp feature target (editor|template_debug|template_release)")
set(GODOTCPP_PRECISION "single" CACHE STRING "Engine float precision of the target Godot build")

FetchContent_MakeAvailable(godot-cpp)

add_library(eom_terrain_native SHARED
    src/register_types.cpp
    src/eom_terrain_native.cpp
)
target_compile_features(eom_terrain_native PRIVATE cxx_std_17)
target_link_libraries(eom_terrain_native PRIVATE godot::cpp)

set(EOM_LIB_BASENAME "eom_terrain_native.windows.${GODOTCPP_TARGET}.x86_64")
set_target_properties(
    eom_terrain_native
    PROPERTIES
        OUTPUT_NAME "${EOM_LIB_BASENAME}"
        PREFIX ""
)

# Deploy the DLL plus a generated .gdextension descriptor into the gitignored
# Godot project directory game/bin/ so res://bin/... resolves. Nothing under
# game/bin/ is committed; a missing build simply means the descriptor is absent.
set(EOM_GAME_BIN_DIR "${CMAKE_CURRENT_SOURCE_DIR}/../game/bin")
configure_file(
    "${CMAKE_CURRENT_SOURCE_DIR}/eom_native.gdextension.in"
    "${EOM_GAME_BIN_DIR}/eom_native.gdextension"
    @ONLY
)
add_custom_command(
    TARGET eom_terrain_native
    POST_BUILD
    COMMAND
        ${CMAKE_COMMAND} -E copy_if_different "$<TARGET_FILE:eom_terrain_native>"
        "${EOM_GAME_BIN_DIR}/${EOM_LIB_BASENAME}.dll"
    COMMENT "Deploying ${EOM_LIB_BASENAME}.dll to game/bin/"
)
