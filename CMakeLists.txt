cmake_minimum_required(VERSION 3.16)
include($ENV{IDF_PATH}/tools/cmake/project.cmake)

# Community firmware replaces the bootloader when installed over USB. Keep the
# factory Recovery entry gesture in every derivative build so USB development
# does not strand the device outside the mini-program BLE install path.
idf_build_set_property(
    BOOTLOADER_EXTRA_COMPONENT_DIRS
    "${CMAKE_CURRENT_LIST_DIR}/bootloader_components/"
    APPEND)

# Swiftly exposes `swiftc` through a dispatcher.  CMake later launches the
# frontend selected by Xcode unless it receives the resolved toolchain binary.
# Resolve the toolchain selected by `.swift-version` before idf_swift enables
# the Swift language, while preserving an explicit CMAKE_Swift_COMPILER value.
if(NOT DEFINED CMAKE_Swift_COMPILER)
    find_program(SWIFTLY_EXECUTABLE swiftly)
    if(NOT SWIFTLY_EXECUTABLE)
        message(FATAL_ERROR
            "Embedded Swift requires Swift 6.3.3. Install Swiftly and run "
            "'swiftly install 6.3.3', or set CMAKE_Swift_COMPILER to that "
            "toolchain's swiftc binary. See docs/development/engineering/environment-setup.md.")
    endif()
    execute_process(
        COMMAND "${SWIFTLY_EXECUTABLE}" use --print-location
        WORKING_DIRECTORY "${CMAKE_CURRENT_LIST_DIR}"
        OUTPUT_VARIABLE SWIFT_TOOLCHAIN_DIRECTORY
        OUTPUT_STRIP_TRAILING_WHITESPACE
        ERROR_QUIET
        RESULT_VARIABLE SWIFTLY_RESULT)
    set(SWIFT_COMPILER_PATH "${SWIFT_TOOLCHAIN_DIRECTORY}/usr/bin/swiftc")
    if(NOT SWIFTLY_RESULT EQUAL 0 OR NOT EXISTS "${SWIFT_COMPILER_PATH}")
        message(FATAL_ERROR
            "Swiftly could not resolve the Swift 6.3.3 toolchain selected by .swift-version. "
            "Run 'swiftly install 6.3.3' and configure it with 'swiftly use 6.3.3'.")
    endif()
    set(CMAKE_Swift_COMPILER "${SWIFT_COMPILER_PATH}" CACHE FILEPATH
        "Embedded Swift compiler selected by Swiftly")
endif()

project(FoloToy-AI-Passport)
