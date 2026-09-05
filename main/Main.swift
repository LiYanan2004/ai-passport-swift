import EmbeddedSwiftUI
import LVGLRendererAdaptor

@_cdecl("app_main")
func app_main() {
    print("AI Passport starting")
    _ = bsp_i2c_init()
    guard Display.shared.initialize() else {
        print("Display initialization failed")
        return
    }
    if !passport_ui_initialize_input() {
        print("Button initialization failed")
    }
    if !DeviceConnectivityMonitor.shared.start() {
        print("Connectivity monitor initialization failed")
    }

    setApplicationImageResolver { name in
        TiboAvatarAssets.shared.resolve(named: name)
    }
    PassportApp.main()

    if WiFiCredentials.all.isEmpty {
        print("Wi-Fi startup skipped: no credentials configured")
    } else {
        var wifiStartupTask: TaskHandle_t?
        let taskResult = xTaskCreate(
            swiftWiFiStartupTask,
            UnsafePointer<CChar>(OpaquePointer(StaticString("wifi_startup").utf8Start)),
            6_144,
            nil,
            3,
            &wifiStartupTask
        )
        if taskResult != pdPASS {
            print("Wi-Fi startup task allocation failed")
        }
    }
}

@_cdecl("swift_wifi_startup_task")
private func swiftWiFiStartupTask(_ argument: UnsafeMutableRawPointer?) {
    _ = argument
    // Keep Wi-Fi allocations after the initial UI mount, measured below one second.
    vTaskDelay(TickType_t(CONFIG_FREERTOS_HZ * 2))
    WiFiConnectionController.shared.start()
    if WiFiConnectionController.shared.scanState == .failed {
        print("Wi-Fi startup failed: \(WiFiConnectionController.shared.errorDescription)")
    } else {
        print("Wi-Fi station ready")
    }
    vTaskDelete(nil)
}
