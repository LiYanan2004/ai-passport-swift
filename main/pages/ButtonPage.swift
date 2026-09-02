private var buttonScreen: OpaquePointer?
private var buttonMillivoltsLabel: OpaquePointer?
private var buttonLogLabels: (OpaquePointer?, OpaquePointer?, OpaquePointer?, OpaquePointer?, OpaquePointer?, OpaquePointer?) = (nil, nil, nil, nil, nil, nil)
private var buttonTimer: OpaquePointer?

private func buttonTimerTick(_ timer: OpaquePointer?) {
    _ = timer
    guard let buttonMillivoltsLabel else {
        return
    }
    let millivolts = bsp_button_read_mv()
    if millivolts < 0 {
        lv_label_set_text(buttonMillivoltsLabel, "ADC read failed")
    } else {
        swift_lvgl_label_set_value(buttonMillivoltsLabel, millivolts, "mV")
    }
}

private func shiftButtonLog() {
    let labels = buttonLogLabels
    if let first = labels.0, let second = labels.1, let third = labels.2,
       let fourth = labels.3, let fifth = labels.4, let sixth = labels.5 {
        lv_label_set_text(first, lv_label_get_text(second))
        lv_label_set_text(second, lv_label_get_text(third))
        lv_label_set_text(third, lv_label_get_text(fourth))
        lv_label_set_text(fourth, lv_label_get_text(fifth))
        lv_label_set_text(fifth, lv_label_get_text(sixth))
    }
}

private func setLatestButtonLog(_ button: Int32, _ event: Int32) {
    guard let label = buttonLogLabels.5 else {
        return
    }
    switch button {
    case Int32(BSP_BTN_UP.rawValue):
        switch event {
        case 0: lv_label_set_text(label, "UP: PRESS")
        case 1: lv_label_set_text(label, "UP: CLICK")
        case 2: lv_label_set_text(label, "UP: DOUBLE")
        default: lv_label_set_text(label, "UP: LONG")
        }
    case Int32(BSP_BTN_DOWN.rawValue):
        switch event {
        case 0: lv_label_set_text(label, "DOWN: PRESS")
        case 1: lv_label_set_text(label, "DOWN: CLICK")
        case 2: lv_label_set_text(label, "DOWN: DOUBLE")
        default: lv_label_set_text(label, "DOWN: LONG")
        }
    default:
        switch event {
        case 0: lv_label_set_text(label, "OK: PRESS")
        case 1: lv_label_set_text(label, "OK: CLICK")
        case 2: lv_label_set_text(label, "OK: DOUBLE")
        default: lv_label_set_text(label, "OK: LONG")
        }
    }
}

private func configureButtonLogLabel(_ label: OpaquePointer?, _ verticalOffset: Int32, _ text: UnsafePointer<CChar>?) {
    lv_obj_set_style_text_color(label, lv_color_hex(UInt32(UI_INK)), 0)
    lv_obj_align(label, LV_ALIGN_TOP_LEFT, 9, verticalOffset)
    lv_label_set_text(label, text)
}

@_cdecl("demo_button_enter")
func demoButtonEnter() {
    buttonScreen = uiPixelScreenCreate("BUTTON / ADC")
    guard let buttonScreen else {
        return
    }
    let panel = uiPixelPanelCreate(buttonScreen, 18, 58, 204, 184, UInt32(UI_PAPER))
    buttonMillivoltsLabel = uiPixelLabel(panel, "-- mV", swift_lvgl_font_montserrat_20(), UInt32(UI_SKY_DARK))
    if let buttonMillivoltsLabel {
        lv_obj_align(buttonMillivoltsLabel, LV_ALIGN_TOP_MID, 0, 8)
    }

    let labels = (
        lv_label_create(panel), lv_label_create(panel), lv_label_create(panel),
        lv_label_create(panel), lv_label_create(panel), lv_label_create(panel)
    )
    buttonLogLabels = labels
    configureButtonLogLabel(labels.0, 54, "press any key...")
    configureButtonLogLabel(labels.1, 71, "")
    configureButtonLogLabel(labels.2, 88, "")
    configureButtonLogLabel(labels.3, 105, "")
    configureButtonLogLabel(labels.4, 122, "")
    configureButtonLogLabel(labels.5, 139, "")

    _ = uiPixelMascotCreate(buttonScreen, 101, 238)
    buttonTimer = lv_timer_create(buttonTimerTick, 100, nil)
    lv_screen_load(buttonScreen)
}

@_cdecl("demo_button_exit")
func demoButtonExit() {
    if let buttonTimer {
        lv_timer_delete(buttonTimer)
    }
    buttonTimer = nil
    if let buttonScreen {
        lv_obj_delete(buttonScreen)
    }
    buttonScreen = nil
    buttonMillivoltsLabel = nil
    buttonLogLabels = (nil, nil, nil, nil, nil, nil)
}

@_cdecl("demo_button_key")
func demoButtonKey(_ button: Int32, _ event: Int32) {
    shiftButtonLog()
    setLatestButtonLog(button, event)
}
