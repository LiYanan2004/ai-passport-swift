private struct MenuItem {
    let title: String
    var isAvailable: Bool
    let viewController: LVViewController
}

private var menuScreen: LVObject?
private var menuMascot: LVContainer?
private var menuCards: [LVContainer?] = [nil, nil, nil, nil, nil, nil, nil]
private var menuRows: [LVLabel?] = [nil, nil, nil, nil, nil, nil, nil]
private var selectedDemo = 0

private var menuItems = [
    MenuItem(title: "Display", isAvailable: true, viewController: LVDisplayViewController()),
    MenuItem(title: "Button", isAvailable: false, viewController: LVButtonViewController()),
    MenuItem(title: "Audio", isAvailable: false, viewController: LVAudioViewController()),
    MenuItem(title: "Battery", isAvailable: false, viewController: LVBatteryViewController()),
    MenuItem(title: "Wi-Fi", isAvailable: true, viewController: LVWiFiViewController()),
    MenuItem(title: "BLE", isAvailable: true, viewController: LVBluetoothViewController()),
    MenuItem(title: "Low Power", isAvailable: true, viewController: LVLowPowerViewController()),
]
private let pageRouter = LVPageRouter()

private func refreshMenu() {
    for index in menuItems.indices {
        let menuItem = menuItems[index]
        menuRows[index]?.text = menuItem.isAvailable ? menuItem.title : menuItem.title + "  [FAIL]"
        uiPixelSetSelected(menuCards[index], index == selectedDemo, menuItem.isAvailable)
        menuRows[index]?.setTextColor(menuItem.isAvailable ? LVColor.ink._hexValue : 0x7A2020)
    }
}

private func buildMenu() {
    menuScreen = LVObject(lv_obj_create(nil))
    guard let menuScreen else {
        return
    }
    uiPixelScreenConfigure(menuScreen, title: "FoloToy")

    for index in menuItems.indices {
        let horizontalOffset = Int32((index % 2) * 112)
        let verticalOffset = Int32((index / 2) * 47)
        let card = uiPixelPanelCreate(menuScreen, 11 + horizontalOffset, 52 + verticalOffset, 102, 40, LVColor.paper._hexValue)
        let row = LVLabel(parent: card, text: "")
        LVFont.montserrat14.apply(to: row)
        row?.setTextAlignmentCenter()
        row?.center()
        menuCards[index] = card
        menuRows[index] = row
    }

    menuMascot = uiPixelMascotCreate(menuScreen, 101, 242)
    refreshMenu()
    lv_screen_load(menuScreen.opaquePointer)
}

// MARK: - MAIN

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

    menuItems[1].isAvailable = swift_platform_button_init() == ESP_OK
    menuItems[2].isAvailable = bsp_audio_init() == ESP_OK
    menuItems[3].isAvailable = bsp_battery_init() == ESP_OK

    if bsp_lvgl_lock(1000) {
        buildMenu()
        bsp_lvgl_unlock()
    }

    print("FoloToy AI Passport ready")
}

// MARK: - 处理按钮事件

@_cdecl("swift_main_button_event")
func swiftMainButtonEvent(_ button: Int32, _ event: Int32) {
    guard bsp_lvgl_lock(500) else {
        return
    }

    if pageRouter.hasActiveViewController {
        if button == Int32(BSP_BTN_OK.rawValue) && event == Int32(BSP_BTN_LONG.rawValue) {
            pageRouter.dismiss()
            buildMenu()
        } else {
            pageRouter.dispatchButton(button, event: event)
        }
    } else if event == Int32(BSP_BTN_CLICK.rawValue) {
        if button == Int32(BSP_BTN_UP.rawValue) {
            selectedDemo = (selectedDemo + menuItems.count - 1) % menuItems.count
            refreshMenu()
        } else if button == Int32(BSP_BTN_DOWN.rawValue) {
            selectedDemo = (selectedDemo + 1) % menuItems.count
            refreshMenu()
        } else if button == Int32(BSP_BTN_OK.rawValue) && menuItems[selectedDemo].isAvailable {
            uiPixelMascotJump(menuMascot)
            menuScreen?.delete()
            menuScreen = nil
            menuMascot = nil
            pageRouter.show(menuItems[selectedDemo].viewController)
        } else if button == Int32(BSP_BTN_UP.rawValue) || button == Int32(BSP_BTN_DOWN.rawValue) {
            uiPixelMascotJump(menuMascot)
        }
    }

    bsp_lvgl_unlock()
}