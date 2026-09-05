# Source-only Embedded Swift port; no desktop SwiftPM dependencies are linked.
set(embedded_swiftui_sources
    Sources/EmbeddedSwiftUI/Animatable.swift
    Sources/EmbeddedSwiftUI/AppearanceActionModifier.swift
    Sources/EmbeddedSwiftUI/AlignmentExtensions.swift
    Sources/EmbeddedSwiftUI/Animation.swift
    Sources/EmbeddedSwiftUI/App.swift
    Sources/EmbeddedSwiftUI/ConditionalContent.swift
    Sources/EmbeddedSwiftUI/DisplayList.swift
    Sources/EmbeddedSwiftUI/DisplayListLayout.swift
    Sources/EmbeddedSwiftUI/DynamicProperty.swift
    Sources/EmbeddedSwiftUI/Alignment.swift
    Sources/EmbeddedSwiftUI/Background.swift
    Sources/EmbeddedSwiftUI/Color.swift
    Sources/EmbeddedSwiftUI/EdgeInsets.swift
    Sources/EmbeddedSwiftUI/Environment.swift
    Sources/EmbeddedSwiftUI/Frame.swift
    Sources/EmbeddedSwiftUI/GeometryEffect.swift
    Sources/EmbeddedSwiftUI/HStack.swift
    Sources/EmbeddedSwiftUI/Image.swift
    Sources/EmbeddedSwiftUI/Layout.swift
    Sources/EmbeddedSwiftUI/LayoutSubviews.swift
    Sources/EmbeddedSwiftUI/LayoutView.swift
    Sources/EmbeddedSwiftUI/Offset.swift
    Sources/EmbeddedSwiftUI/OpacityEffect.swift
    Sources/EmbeddedSwiftUI/OptionalView.swift
    Sources/EmbeddedSwiftUI/Padding.swift
    Sources/EmbeddedSwiftUI/ProposedViewSize.swift
    Sources/EmbeddedSwiftUI/Rect.swift
    Sources/EmbeddedSwiftUI/RenderTypes.swift
    Sources/EmbeddedSwiftUI/RendererEffect.swift
    Sources/EmbeddedSwiftUI/RendererConfiguration.swift
    Sources/EmbeddedSwiftUI/RootGeometry.swift
    Sources/EmbeddedSwiftUI/Size.swift
    Sources/EmbeddedSwiftUI/Spacer.swift
    Sources/EmbeddedSwiftUI/StackLayout.swift
    Sources/EmbeddedSwiftUI/State.swift
    Sources/EmbeddedSwiftUI/Text.swift
    Sources/EmbeddedSwiftUI/VStack.swift
    Sources/EmbeddedSwiftUI/ViewHost.swift
    Sources/EmbeddedSwiftUI/ViewPair.swift
    Sources/EmbeddedSwiftUI/ZStack.swift
    Sources/EmbeddedSwiftUI/Font.swift
    Sources/EmbeddedSwiftUI/ScrollView.swift
    Sources/EmbeddedSwiftUI/ScaleEffect.swift
    Sources/EmbeddedSwiftUI/Shape.swift
    Sources/EmbeddedSwiftUI/View.swift
    Sources/EmbeddedSwiftUI/ViewBuilder.swift
    Sources/EmbeddedSwiftUI/ViewInputs.swift
    Sources/EmbeddedSwiftUI/ViewIdentity.swift
    Sources/EmbeddedSwiftUI/ViewList.swift
    Sources/EmbeddedSwiftUI/ViewModifier.swift
    Sources/EmbeddedSwiftUI/ViewModifiers.swift
    Sources/EmbeddedSwiftUI/ViewOutputs.swift
    Sources/EmbeddedSwiftUI/ViewTrait.swift
    Sources/EmbeddedSwiftUI/ZIndex.swift
)

extract_riscv_flags(embedded_swiftui_arch_flags)
idf_build_get_property(embedded_swiftui_config_dir CONFIG_DIR)

add_library(EmbeddedSwiftUI STATIC ${embedded_swiftui_sources})
add_library(
    LVGLRendererAdaptor STATIC
    Sources/LVGLRendererAdaptor/DisplayListRenderer.swift
    Sources/LVGLRendererAdaptor/LVGLApplicationRuntime.swift
    Sources/LVGLRendererAdaptor/LVGLRendererAdaptor.swift
    Sources/LVGLRendererAdaptor/LVGLFont.swift
    Sources/LVGLRendererAdaptor/LVGLSystemColorDefinition.swift
    Sources/LVGLRendererAdaptor/LVGLShapeRenderer.swift
    Sources/LVGLRendererAdaptor/LVGLAnimation.swift
    Sources/LVGLRendererAdaptor/LVGLScreenshot.swift
    Sources/LVGLRendererAdaptor/PhysicalButton.swift
)
foreach(swift_target EmbeddedSwiftUI LVGLRendererAdaptor)
    # Archive RISC-V objects with the IDF toolchain instead of host libtool.
    set_target_properties(${swift_target} PROPERTIES
        LINKER_LANGUAGE C
        COMPILE_OPTIONS ""
        Swift_MODULE_DIRECTORY "${CMAKE_CURRENT_BINARY_DIR}/modules")
    target_compile_options(${swift_target} PRIVATE
        "SHELL:-target riscv32-none-none-eabi ${embedded_swiftui_arch_flags}
        -enable-experimental-feature Embedded -package-name EmbeddedSwiftUI -wmo -Osize -parse-as-library
        -Xfrontend -function-sections
        -Xcc -fno-pic -Xcc -fno-pie")
    target_include_directories(${swift_target} PUBLIC "${CMAKE_CURRENT_BINARY_DIR}/modules")
endforeach()
target_compile_options(LVGLRendererAdaptor PRIVATE
    "SHELL:-Xcc -DESP_PLATFORM
    -import-bridging-header ${CMAKE_CURRENT_LIST_DIR}/../HeaderBridge.h")
target_include_directories(LVGLRendererAdaptor PRIVATE "${embedded_swiftui_config_dir}")
target_link_libraries(
    LVGLRendererAdaptor
    PUBLIC EmbeddedSwiftUI
    PRIVATE idf::bsp idf::espressif__idf_swift idf::lvgl__lvgl
)

set(property_generator "${CMAKE_CURRENT_BINARY_DIR}/generate-dynamic-properties")
add_custom_command(
    OUTPUT "${property_generator}"
    COMMAND bash "${PROJECT_DIR}/tools/build-swift-property-generator.sh"
        "${CMAKE_Swift_COMPILER}" "${property_generator}"
    DEPENDS "${PROJECT_DIR}/tools/GenerateDynamicProperties.swift"
        "${PROJECT_DIR}/tools/build-swift-property-generator.sh"
    VERBATIM
)
add_custom_target(embedded_swiftui_property_generator DEPENDS "${property_generator}")
set(EMBEDDED_SWIFTUI_PROPERTY_GENERATOR "${property_generator}" PARENT_SCOPE)
