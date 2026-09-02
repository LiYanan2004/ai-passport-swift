idf_component_register(
    SRCS "interop/LVGLInterop.c"
         "interop/DeviceInterop.c"
    INCLUDE_DIRS "."
    REQUIRES bsp bt esp_event esp_hw_support esp_netif esp_timer esp_wifi nvs_flash
    PRIV_REQUIRES idf_swift
)

idf_component_register_swift(${COMPONENT_LIB}
    BRIDGING_HEADER "${CMAKE_CURRENT_LIST_DIR}/interop/InteropBridge.h"
    SRCS "Main.swift"
         "PageRouter.swift"
         "pages/LVBatteryViewController.swift"
         "pages/LVDisplayViewController.swift"
         "pages/LVButtonViewController.swift"
         "pages/LVAudioViewController.swift"
         "pages/LVWiFiViewController.swift"
         "pages/LVBluetoothViewController.swift"
         "pages/LVLowPowerViewController.swift"
         "ui/UIPixel.swift"
         "platform/LVAlignment.swift"
         "platform/LVFont.swift"
         "platform/LVColor.swift"
         "platform/LVObject.swift"
         "platform/LVContainer.swift"
         "platform/LVLabel.swift"
         "platform/LVMascotAnimation.swift"
         "platform/LVViewController.swift"
         "platform/LVTimer.swift"
         "ui/UIPixelMath.swift"
)
