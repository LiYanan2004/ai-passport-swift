private var wifiScreen: OpaquePointer?
private var wifiStatusLabel: OpaquePointer?
private var wifiResultsLabel: OpaquePointer?
private var wifiTimer: OpaquePointer?

private func refreshWiFiPage() {
    guard let wifiStatusLabel else { return }
    switch swift_platform_wifi_state() {
    case SWIFT_WIFI_STARTING:
        lv_label_set_text(wifiStatusLabel, "Starting Wi-Fi...")
    case SWIFT_WIFI_SCANNING:
        lv_label_set_text(wifiStatusLabel, "Scanning 2.4 GHz...")
    case SWIFT_WIFI_FAILED:
        lv_label_set_text(wifiStatusLabel, "Wi-Fi failed:")
        if let wifiResultsLabel { lv_label_set_text(wifiResultsLabel, swift_platform_wifi_error()) }
    default:
        if let wifiResultsLabel, let results = swift_platform_wifi_results(), results.pointee != 0 {
            lv_label_set_text(wifiStatusLabel, "Scan complete  |  OK: RESCAN")
            lv_label_set_text(wifiResultsLabel, results)
        }
    }
}

private func wifiTimerTick(_ timer: OpaquePointer?) {
    _ = timer
    refreshWiFiPage()
}

@_cdecl("demo_wifi_enter")
func demoWiFiEnter() {
    wifiScreen = uiPixelScreenCreate("WI-FI SCAN")
    guard let wifiScreen else { return }
    let panel = uiPixelPanelCreate(wifiScreen, 12, 54, 216, 190, UInt32(UI_PAPER))
    wifiStatusLabel = uiPixelLabel(panel, "Starting Wi-Fi...", swift_lvgl_font_montserrat_14(), UInt32(UI_SKY_DARK))
    if let wifiStatusLabel {
        lv_obj_set_width(wifiStatusLabel, 190)
        lv_obj_align(wifiStatusLabel, LV_ALIGN_TOP_LEFT, 2, 2)
    }
    wifiResultsLabel = uiPixelLabel(panel, "RSSI  SSID  CHANNEL", swift_lvgl_font_montserrat_14(), UInt32(UI_INK))
    if let wifiResultsLabel {
        lv_obj_set_width(wifiResultsLabel, 190)
        lv_obj_align(wifiResultsLabel, LV_ALIGN_TOP_LEFT, 2, 35)
    }
    _ = uiPixelMascotCreate(wifiScreen, 101, 246)
    wifiTimer = lv_timer_create(wifiTimerTick, 100, nil)
    lv_screen_load(wifiScreen)
    swift_platform_wifi_start()
}

@_cdecl("demo_wifi_exit")
func demoWiFiExit() {
    if let wifiTimer { lv_timer_delete(wifiTimer) }
    wifiTimer = nil
    swift_platform_wifi_stop()
    if let wifiScreen { lv_obj_delete(wifiScreen) }
    wifiScreen = nil
    wifiStatusLabel = nil
    wifiResultsLabel = nil
}

@_cdecl("demo_wifi_key")
func demoWiFiKey(_ button: Int32, _ event: Int32) {
    guard button == Int32(BSP_BTN_OK.rawValue), event == Int32(BSP_BTN_CLICK.rawValue) else { return }
    if let wifiResultsLabel { lv_label_set_text(wifiResultsLabel, "RSSI  SSID  CHANNEL") }
    swift_platform_wifi_rescan()
}
