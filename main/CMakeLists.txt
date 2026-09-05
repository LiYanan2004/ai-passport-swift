idf_component_register(
    SRCS /dev/null
    INCLUDE_DIRS "."
    REQUIRES bsp bt esp_event esp_netif esp_timer esp_wifi nvs_flash wpa_supplicant
    PRIV_REQUIRES esp_http_client idf_swift json mbedtls
)

if(CONFIG_APP_EMBEDDED_SWIFTUI_DEMO)
    if(CONFIG_LV_MEM_SIZE_KILOBYTES LESS 48)
        message(FATAL_ERROR "EmbeddedSwiftUI demo requires CONFIG_LV_MEM_SIZE_KILOBYTES >= 48. Update sdkconfig with menuconfig and rebuild.")
    endif()
    add_subdirectory(EmbeddedSwiftUI)
    # Generate dynamic-property registration for every application source in
    # this component. Keeping the source list implicit prevents a newly added
    # View or ViewModifier from silently falling back to the no-op
    # `_makeProperties` implementation.
    file(GLOB_RECURSE embedded_application_swift_sources CONFIGURE_DEPENDS
        "${CMAKE_CURRENT_LIST_DIR}/*.swift")
    # Legacy UIKit/application sources and the EmbeddedSwiftUI package
    # manifest are outside this target and must not be sent to the generator.
    list(FILTER embedded_application_swift_sources EXCLUDE REGEX "/legacy/")
    list(FILTER embedded_application_swift_sources EXCLUDE REGEX "/EmbeddedSwiftUI/")
    # Optional audio, sleep, and Agent Monitor BLE services are not started by
    # this application. Keep their wrappers available for their later owners.
    list(FILTER embedded_application_swift_sources EXCLUDE REGEX
        "/platform/hardware/(Bluetooth|Microphone|SleepManager|Speaker)\\.swift$")
    list(FILTER embedded_application_swift_sources EXCLUDE REGEX "/config/WiFiCredentials.*\\.swift$")
    if(EXISTS "${CMAKE_CURRENT_LIST_DIR}/config/WiFiCredentials.local.swift")
        list(APPEND embedded_application_swift_sources
            "${CMAKE_CURRENT_LIST_DIR}/config/WiFiCredentials.local.swift")
    else()
        list(APPEND embedded_application_swift_sources
            "${CMAKE_CURRENT_LIST_DIR}/config/WiFiCredentialsDefault.swift")
    endif()
    set(embedded_application_sources)
    foreach(source IN LISTS embedded_application_swift_sources)
        file(RELATIVE_PATH source_relative "${CMAKE_CURRENT_LIST_DIR}" "${source}")
        set(generated "${CMAKE_CURRENT_BINARY_DIR}/generated/${source_relative}")
        get_filename_component(generated_directory "${generated}" DIRECTORY)
        add_custom_command(
            OUTPUT "${generated}"
            COMMAND "${CMAKE_COMMAND}" -E make_directory "${generated_directory}"
            COMMAND "${EMBEDDED_SWIFTUI_PROPERTY_GENERATOR}" "${source}" "${generated}"
            DEPENDS "${source}" embedded_swiftui_property_generator
            VERBATIM
        )
        list(APPEND embedded_application_sources "${generated}")
    endforeach()
    idf_component_register_swift(${COMPONENT_LIB}
        BRIDGING_HEADER "${CMAKE_CURRENT_LIST_DIR}/HeaderBridge.h"
        SRCS ${embedded_application_sources}
    )
    target_compile_options(${COMPONENT_LIB} PRIVATE
        "$<$<COMPILE_LANGUAGE:Swift>:SHELL:-Xcc -DESP_PLATFORM>")
    target_link_libraries(${COMPONENT_LIB} PRIVATE LVGLRendererAdaptor)
    target_add_binary_data(${COMPONENT_LIB} "assets/tibo-reset-confirmed.rgb565" BINARY)
    target_add_binary_data(${COMPONENT_LIB} "assets/tibo-reset-announced.rgb565" BINARY)
    target_add_binary_data(${COMPONENT_LIB} "assets/tibo-reset-idle.rgb565" BINARY)
else()
    message(FATAL_ERROR "Only the EmbeddedSwiftUI demo build is currently supported.")
endif()
