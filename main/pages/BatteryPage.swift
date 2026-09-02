private var screen: OpaquePointer?
private var socLabel: OpaquePointer?
private var millivoltsLabel: OpaquePointer?
private var timer: OpaquePointer?

private func updateBatteryLabels() {
    guard let socLabel, let millivoltsLabel else {
        return
    }

    let soc = bsp_battery_soc()
    let millivolts = bsp_battery_mv()

    swift_lvgl_label_set_value(socLabel, soc, "%")
    swift_lvgl_label_set_value(millivoltsLabel, millivolts, "mV")

    let color = (soc >= 0 && soc < 20) ? UInt32(0xFF5A5A) : UInt32(0x39FF88)
    lv_obj_set_style_text_color(socLabel, lv_color_hex(color), 0)
}

private func batteryTimerTick(_ timer: OpaquePointer?) {
    _ = timer
    updateBatteryLabels()
}

@_cdecl("demo_battery_enter")
func demoBatteryEnter() {
    screen = uiPixelScreenCreate("BATTERY")
    guard let screen else {
        return
    }

    let panel = uiPixelPanelCreate(screen, 24, 67, 192, 157, UInt32(UI_YELLOW))

    socLabel = uiPixelLabel(panel, "-- %", swift_lvgl_font_montserrat_20(), UInt32(UI_INK))
    if let socLabel {
        lv_obj_align(socLabel, LV_ALIGN_TOP_MID, 0, 12)
    }

    let implementationLabel = uiPixelLabel(panel, "Embedded Swift", swift_lvgl_font_montserrat_14(), 0x6B7280)
    lv_obj_align(implementationLabel, LV_ALIGN_TOP_MID, 0, 43)

    millivoltsLabel = lv_label_create(panel)
    if let millivoltsLabel {
        lv_obj_set_style_text_color(millivoltsLabel, lv_color_hex(UInt32(UI_INK)), 0)
        lv_obj_align(millivoltsLabel, LV_ALIGN_TOP_MID, 0, 64)
        lv_label_set_text(millivoltsLabel, "-- mV")
    }

    let battery = uiPixelPanelCreate(panel, 38, 96, 100, 38, UInt32(UI_GRASS))
    lv_obj_set_style_border_width(battery, 4, 0)
    _ = uiPixelMascotCreate(screen, 101, 238)

    updateBatteryLabels()
    timer = lv_timer_create(batteryTimerTick, 1000, nil)
    lv_screen_load(screen)
}

@_cdecl("demo_battery_exit")
func demoBatteryExit() {
    if let timer {
        lv_timer_delete(timer)
    }
    timer = nil

    if let screen {
        lv_obj_delete(screen)
    }
    screen = nil
    socLabel = nil
    millivoltsLabel = nil
}

@_cdecl("demo_battery_key")
func demoBatteryKey(_ button: Int32, _ event: Int32) {
    _ = button
    _ = event
}
