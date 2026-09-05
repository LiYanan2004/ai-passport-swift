cmake_minimum_required(VERSION 3.29)

# SourceKit-LSP reads the Swift compiler from build/compile_commands.json.
# Configure Embedded Swift before ESP-IDF calls project() so the generated
# database describes the same toolchain that builds the firmware.
if(NOT DEFINED CMAKE_Swift_COMPILER)
    set(
        CMAKE_Swift_COMPILER
        "/Library/Developer/Toolchains/swift-DEVELOPMENT-SNAPSHOT-2026-08-30-a.xctoolchain/usr/bin/swiftc"
        CACHE FILEPATH
        "Embedded Swift compiler")
endif()

include($ENV{IDF_PATH}/tools/cmake/project.cmake)

# Community firmware replaces the bootloader when installed over USB. Keep the
# factory Recovery entry gesture in every derivative build so USB development
# does not strand the device outside the mini-program BLE install path.
idf_build_set_property(
    BOOTLOADER_EXTRA_COMPONENT_DIRS
    "${CMAKE_CURRENT_LIST_DIR}/bootloader_components/"
    APPEND)
idf_build_set_property(MINIMAL_BUILD ON)

project(FoloToy-AI-Passport)
