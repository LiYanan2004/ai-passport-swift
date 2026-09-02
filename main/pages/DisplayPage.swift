private var displayScreen: OpaquePointer?
private var displaySwatch: OpaquePointer?
private var displayInfo: OpaquePointer?
private var displayMascot: OpaquePointer?
private var displayColorIndex: Int32 = 0
private var displayBacklightIndex: Int32 = 0

private func refreshDisplayPage() {
    guard let displaySwatch, let displayInfo else {
        return
    }

    switch displayColorIndex {
    case 0:
        lv_obj_set_style_bg_color(displaySwatch, lv_color_hex(0xFF0000), 0)
        lv_obj_set_style_text_color(displayInfo, lv_color_black(), 0)
        switch displayBacklightIndex {
        case 0: lv_label_set_text(displayInfo, "RED\n\nBACKLIGHT 100%\n\nOK: NEXT COLOR\nUP/DOWN: LIGHT")
        case 1: lv_label_set_text(displayInfo, "RED\n\nBACKLIGHT 50%\n\nOK: NEXT COLOR\nUP/DOWN: LIGHT")
        default: lv_label_set_text(displayInfo, "RED\n\nBACKLIGHT 10%\n\nOK: NEXT COLOR\nUP/DOWN: LIGHT")
        }
    case 1:
        lv_obj_set_style_bg_color(displaySwatch, lv_color_hex(0x00FF00), 0)
        lv_obj_set_style_text_color(displayInfo, lv_color_black(), 0)
        switch displayBacklightIndex {
        case 0: lv_label_set_text(displayInfo, "GREEN\n\nBACKLIGHT 100%\n\nOK: NEXT COLOR\nUP/DOWN: LIGHT")
        case 1: lv_label_set_text(displayInfo, "GREEN\n\nBACKLIGHT 50%\n\nOK: NEXT COLOR\nUP/DOWN: LIGHT")
        default: lv_label_set_text(displayInfo, "GREEN\n\nBACKLIGHT 10%\n\nOK: NEXT COLOR\nUP/DOWN: LIGHT")
        }
    case 2:
        lv_obj_set_style_bg_color(displaySwatch, lv_color_hex(0x0000FF), 0)
        lv_obj_set_style_text_color(displayInfo, lv_color_white(), 0)
        switch displayBacklightIndex {
        case 0: lv_label_set_text(displayInfo, "BLUE\n\nBACKLIGHT 100%\n\nOK: NEXT COLOR\nUP/DOWN: LIGHT")
        case 1: lv_label_set_text(displayInfo, "BLUE\n\nBACKLIGHT 50%\n\nOK: NEXT COLOR\nUP/DOWN: LIGHT")
        default: lv_label_set_text(displayInfo, "BLUE\n\nBACKLIGHT 10%\n\nOK: NEXT COLOR\nUP/DOWN: LIGHT")
        }
    case 3:
        lv_obj_set_style_bg_color(displaySwatch, lv_color_hex(0xFFFFFF), 0)
        lv_obj_set_style_text_color(displayInfo, lv_color_black(), 0)
        switch displayBacklightIndex {
        case 0: lv_label_set_text(displayInfo, "WHITE\n\nBACKLIGHT 100%\n\nOK: NEXT COLOR\nUP/DOWN: LIGHT")
        case 1: lv_label_set_text(displayInfo, "WHITE\n\nBACKLIGHT 50%\n\nOK: NEXT COLOR\nUP/DOWN: LIGHT")
        default: lv_label_set_text(displayInfo, "WHITE\n\nBACKLIGHT 10%\n\nOK: NEXT COLOR\nUP/DOWN: LIGHT")
        }
    default:
        lv_obj_set_style_bg_color(displaySwatch, lv_color_hex(0x000000), 0)
        lv_obj_set_style_text_color(displayInfo, lv_color_white(), 0)
        switch displayBacklightIndex {
        case 0: lv_label_set_text(displayInfo, "BLACK\n\nBACKLIGHT 100%\n\nOK: NEXT COLOR\nUP/DOWN: LIGHT")
        case 1: lv_label_set_text(displayInfo, "BLACK\n\nBACKLIGHT 50%\n\nOK: NEXT COLOR\nUP/DOWN: LIGHT")
        default: lv_label_set_text(displayInfo, "BLACK\n\nBACKLIGHT 10%\n\nOK: NEXT COLOR\nUP/DOWN: LIGHT")
        }
    }
}

private func applyDisplayBacklight() {
    switch displayBacklightIndex {
    case 0: bsp_display_backlight(100)
    case 1: bsp_display_backlight(50)
    default: bsp_display_backlight(10)
    }
}

func enterDisplayPage() {
    displayColorIndex = 0
    displayBacklightIndex = 0
    applyDisplayBacklight()

    displayScreen = uiPixelScreenCreate("DISPLAY")
    guard let displayScreen else {
        return
    }
    displaySwatch = uiPixelPanelCreate(displayScreen, 18, 58, 204, 188, 0xFF0000)
    displayInfo = uiPixelLabel(displaySwatch, "", swift_lvgl_font_montserrat_14(), uiInk)
    if let displayInfo {
        lv_obj_set_style_text_align(displayInfo, LV_TEXT_ALIGN_CENTER, 0)
        lv_obj_center(displayInfo)
    }
    displayMascot = uiPixelMascotCreate(displayScreen, 101, 238)
    refreshDisplayPage()
    lv_screen_load(displayScreen)
}

func exitDisplayPage() {
    bsp_display_backlight(100)
    if let displayScreen {
        lv_obj_delete(displayScreen)
    }
    displayScreen = nil
    displaySwatch = nil
    displayInfo = nil
    displayMascot = nil
}

func handleDisplayPageKey(_ button: Int32, _ event: Int32) {
    guard event == Int32(BSP_BTN_CLICK.rawValue) else {
        return
    }
    if button == Int32(BSP_BTN_OK.rawValue) {
        displayColorIndex = (displayColorIndex + 1) % 5
        uiPixelMascotJump(displayMascot)
    } else {
        displayBacklightIndex = button == Int32(BSP_BTN_UP.rawValue)
            ? (displayBacklightIndex + 2) % 3
            : (displayBacklightIndex + 1) % 3
        applyDisplayBacklight()
    }
    refreshDisplayPage()
}
