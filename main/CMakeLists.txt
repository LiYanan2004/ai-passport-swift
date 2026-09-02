idf_component_register(
    SRCS "bridge/swift_lvgl_bridge.c"
         "bridge/swift_platform_bridge.c"
    INCLUDE_DIRS "."
    REQUIRES bsp bt esp_event esp_hw_support esp_netif esp_timer esp_wifi nvs_flash
    PRIV_REQUIRES idf_swift
)

idf_component_register_swift(${COMPONENT_LIB}
    BRIDGING_HEADER "${CMAKE_CURRENT_LIST_DIR}/bridge/SwiftBridge.h"
    SRCS "Main.swift"
         "pages/BatteryPage.swift"
         "pages/DisplayPage.swift"
         "pages/ButtonPage.swift"
         "pages/AudioPage.swift"
         "pages/WiFiPage.swift"
         "pages/BluetoothPage.swift"
         "pages/LowPowerPage.swift"
         "ui/UIPixel.swift"
         "ui/UITheme.swift"
         "ui/UIPixelMath.swift"
)
