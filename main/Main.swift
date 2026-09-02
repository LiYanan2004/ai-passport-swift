private let demoCount: Int32 = 7

private var menuScreen: OpaquePointer?
private var menuMascot: OpaquePointer?
private var menuCard0: OpaquePointer?
private var menuCard1: OpaquePointer?
private var menuCard2: OpaquePointer?
private var menuCard3: OpaquePointer?
private var menuCard4: OpaquePointer?
private var menuCard5: OpaquePointer?
private var menuCard6: OpaquePointer?
private var menuRow0: OpaquePointer?
private var menuRow1: OpaquePointer?
private var menuRow2: OpaquePointer?
private var menuRow3: OpaquePointer?
private var menuRow4: OpaquePointer?
private var menuRow5: OpaquePointer?
private var menuRow6: OpaquePointer?
private var selectedDemo: Int32 = 0
private var activeDemo: Int32 = -1
private var displayAvailable = true
private var buttonAvailable = false
private var audioAvailable = false
private var batteryAvailable = false

private func menuCard(_ index: Int32) -> OpaquePointer? {
    switch index {
    case 0: return menuCard0
    case 1: return menuCard1
    case 2: return menuCard2
    case 3: return menuCard3
    case 4: return menuCard4
    case 5: return menuCard5
    default: return menuCard6
    }
}

private func menuRow(_ index: Int32) -> OpaquePointer? {
    switch index {
    case 0: return menuRow0
    case 1: return menuRow1
    case 2: return menuRow2
    case 3: return menuRow3
    case 4: return menuRow4
    case 5: return menuRow5
    default: return menuRow6
    }
}

private func setMenuCard(_ card: OpaquePointer?, _ index: Int32) {
    switch index {
    case 0: menuCard0 = card
    case 1: menuCard1 = card
    case 2: menuCard2 = card
    case 3: menuCard3 = card
    case 4: menuCard4 = card
    case 5: menuCard5 = card
    default: menuCard6 = card
    }
}

private func setMenuRow(_ row: OpaquePointer?, _ index: Int32) {
    switch index {
    case 0: menuRow0 = row
    case 1: menuRow1 = row
    case 2: menuRow2 = row
    case 3: menuRow3 = row
    case 4: menuRow4 = row
    case 5: menuRow5 = row
    default: menuRow6 = row
    }
}

private func isDemoAvailable(_ index: Int32) -> Bool {
    switch index {
    case 0: return displayAvailable
    case 1: return buttonAvailable
    case 2: return audioAvailable
    case 3: return batteryAvailable
    default: return true
    }
}

private func setMenuRowText(_ row: OpaquePointer?, _ index: Int32, _ available: Bool) {
    switch index {
    case 0: lv_label_set_text(row, available ? "Display" : "Display  [FAIL]")
    case 1: lv_label_set_text(row, available ? "Button" : "Button  [FAIL]")
    case 2: lv_label_set_text(row, available ? "Audio" : "Audio  [FAIL]")
    case 3: lv_label_set_text(row, available ? "Battery" : "Battery  [FAIL]")
    case 4: lv_label_set_text(row, "Wi-Fi")
    case 5: lv_label_set_text(row, "BLE")
    default: lv_label_set_text(row, "Low Power")
    }
}

private func enterDemo(_ index: Int32) {
    switch index {
    case 0: enterDisplayPage()
    case 1: enterButtonPage()
    case 2: enterAudioPage()
    case 3: enterBatteryPage()
    case 4: enterWiFiPage()
    case 5: enterBluetoothPage()
    default: enterLowPowerPage()
    }
}

private func exitDemo(_ index: Int32) {
    switch index {
    case 0: exitDisplayPage()
    case 1: exitButtonPage()
    case 2: exitAudioPage()
    case 3: exitBatteryPage()
    case 4: exitWiFiPage()
    case 5: exitBluetoothPage()
    default: exitLowPowerPage()
    }
}

private func sendKeyToDemo(_ index: Int32, _ button: Int32, _ event: Int32) {
    switch index {
    case 0: handleDisplayPageKey(button, event)
    case 1: handleButtonPageKey(button, event)
    case 2: handleAudioPageKey(button, event)
    case 3: handleBatteryPageKey(button, event)
    case 4: handleWiFiPageKey(button, event)
    case 5: handleBluetoothPageKey(button, event)
    default: handleLowPowerPageKey(button, event)
    }
}

private func refreshMenu() {
    for index in 0..<demoCount {
        let available = isDemoAvailable(index)
        setMenuRowText(menuRow(index), index, available)
        uiPixelSetSelected(menuCard(index), index == selectedDemo, available)
        lv_obj_set_style_text_color(
            menuRow(index),
            lv_color_hex(available ? uiInk : 0x7A2020),
            0
        )
    }
}

private func buildMenu() {
    menuScreen = uiPixelScreenCreate("FoloToy")
    guard let menuScreen else {
        return
    }

    for index in 0..<demoCount {
        let horizontalOffset = (index % 2) * 112
        let verticalOffset = (index / 2) * 47
        let card = uiPixelPanelCreate(menuScreen, 11 + horizontalOffset, 52 + verticalOffset, 102, 40, uiPaper)
        let row = lv_label_create(card)
        lv_obj_set_style_text_font(row, swift_lvgl_font_montserrat_14(), 0)
        lv_obj_set_style_text_align(row, LV_TEXT_ALIGN_CENTER, 0)
        lv_obj_center(row)
        setMenuCard(card, index)
        setMenuRow(row, index)
    }

    menuMascot = uiPixelMascotCreate(menuScreen, 101, 242)
    refreshMenu()
    lv_screen_load(menuScreen)
}

private func enterMenu() {
    activeDemo = -1
    buildMenu()
}

@_cdecl("swift_main_button_event")
func swiftMainButtonEvent(_ button: Int32, _ event: Int32) {
    guard bsp_lvgl_lock(500) else {
        return
    }

    if activeDemo >= 0 {
        if button == Int32(BSP_BTN_OK.rawValue) && event == Int32(BSP_BTN_LONG.rawValue) {
            exitDemo(activeDemo)
            enterMenu()
        } else {
            sendKeyToDemo(activeDemo, button, event)
        }
    } else if event == Int32(BSP_BTN_CLICK.rawValue) {
        if button == Int32(BSP_BTN_UP.rawValue) {
            selectedDemo = (selectedDemo + demoCount - 1) % demoCount
            refreshMenu()
        } else if button == Int32(BSP_BTN_DOWN.rawValue) {
            selectedDemo = (selectedDemo + 1) % demoCount
            refreshMenu()
        } else if button == Int32(BSP_BTN_OK.rawValue) && isDemoAvailable(selectedDemo) {
            activeDemo = selectedDemo
            uiPixelMascotJump(menuMascot)
            lv_obj_delete(menuScreen)
            menuScreen = nil
            menuMascot = nil
            enterDemo(activeDemo)
        } else if button == Int32(BSP_BTN_UP.rawValue) || button == Int32(BSP_BTN_DOWN.rawValue) {
            uiPixelMascotJump(menuMascot)
        }
    }

    bsp_lvgl_unlock()
}

@_cdecl("app_main")
func appMain() {
    print("FoloToy AI Passport BSP demo starting")
    if esp_sleep_get_wakeup_cause() != ESP_SLEEP_WAKEUP_UNDEFINED {
        print("Wakeup from sleep")
    }

    _ = bsp_i2c_init()
    _ = bsp_i2c_scan()

    guard bsp_display_init() == ESP_OK, bsp_lvgl_init() != nil else {
        print("Display or LVGL initialization failed")
        return
    }
    bsp_display_backlight(100)

    buttonAvailable = swift_platform_button_init() == ESP_OK
    audioAvailable = bsp_audio_init() == ESP_OK
    batteryAvailable = bsp_battery_init() == ESP_OK

    if bsp_lvgl_lock(1000) {
        enterMenu()
        bsp_lvgl_unlock()
    }

    print("FoloToy AI Passport ready")
}
