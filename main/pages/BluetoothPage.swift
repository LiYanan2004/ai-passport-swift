private var bluetoothScreen: OpaquePointer?
private var bluetoothStatusLabel: OpaquePointer?
private var bluetoothTimer: OpaquePointer?

private func refreshBluetoothPage() {
    guard let bluetoothStatusLabel else { return }
    switch swift_platform_ble_state() {
    case SWIFT_BLE_STARTING:
        lv_label_set_text(bluetoothStatusLabel, "Starting NimBLE...")
    case SWIFT_BLE_ADVERTISING:
        lv_label_set_text(bluetoothStatusLabel, "ADVERTISING\n\nName: FoloPassport\n\nUse a BLE scanner\non your phone.\n\nOK: RESTART ADV")
    case SWIFT_BLE_FAILED:
        swift_lvgl_label_set_value(bluetoothStatusLabel, swift_platform_ble_error(), "BLE error")
    default:
        break
    }
}

private func bluetoothTimerTick(_ timer: OpaquePointer?) {
    _ = timer
    refreshBluetoothPage()
}

@_cdecl("demo_ble_enter")
func demoBluetoothEnter() {
    bluetoothScreen = uiPixelScreenCreate("BLUETOOTH LE")
    guard let bluetoothScreen else { return }
    let panel = uiPixelPanelCreate(bluetoothScreen, 22, 58, 196, 180, UInt32(UI_PAPER))
    bluetoothStatusLabel = uiPixelLabel(panel, "Starting NimBLE...", swift_lvgl_font_montserrat_14(), UInt32(UI_INK))
    if let bluetoothStatusLabel {
        lv_obj_set_width(bluetoothStatusLabel, 168)
        lv_obj_set_style_text_align(bluetoothStatusLabel, LV_TEXT_ALIGN_CENTER, 0)
        lv_obj_center(bluetoothStatusLabel)
    }
    _ = uiPixelMascotCreate(bluetoothScreen, 101, 244)
    bluetoothTimer = lv_timer_create(bluetoothTimerTick, 100, nil)
    lv_screen_load(bluetoothScreen)
    swift_platform_ble_start()
}

@_cdecl("demo_ble_exit")
func demoBluetoothExit() {
    if let bluetoothTimer { lv_timer_delete(bluetoothTimer) }
    bluetoothTimer = nil
    swift_platform_ble_stop()
    if let bluetoothScreen { lv_obj_delete(bluetoothScreen) }
    bluetoothScreen = nil
    bluetoothStatusLabel = nil
}

@_cdecl("demo_ble_key")
func demoBluetoothKey(_ button: Int32, _ event: Int32) {
    guard button == Int32(BSP_BTN_OK.rawValue), event == Int32(BSP_BTN_CLICK.rawValue) else { return }
    swift_platform_ble_restart_advertising()
}
