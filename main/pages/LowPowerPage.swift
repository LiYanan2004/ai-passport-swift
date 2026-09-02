private var lowPowerScreen: OpaquePointer?
private var lowPowerStatusLabel: OpaquePointer?
private var lowPowerCards: (OpaquePointer?, OpaquePointer?) = (nil, nil)
private var lowPowerMascot: OpaquePointer?
private var lowPowerTimer: OpaquePointer?
private var lowPowerSelectedIndex: Int32 = 0

private func refreshLowPowerSelection() {
    uiPixelSetSelected(lowPowerCards.0, lowPowerSelectedIndex == 0, true)
    uiPixelSetSelected(lowPowerCards.1, lowPowerSelectedIndex == 1, true)
}

private func refreshLowPowerStatus() {
    guard let lowPowerStatusLabel else { return }
    switch swift_platform_power_state() {
    case SWIFT_POWER_LIGHT_PREPARING:
        lv_label_set_text(lowPowerStatusLabel, "LIGHT SLEEP: 2 SEC\nTimer wakeup")
    case SWIFT_POWER_LIGHT_WOKE:
        lv_label_set_text(lowPowerStatusLabel, "LIGHT WAKE: TIMER\nUP/DOWN: SELECT  OK: RUN")
    case SWIFT_POWER_DEEP_PREPARING:
        lv_label_set_text(lowPowerStatusLabel, "DEEP SLEEP: 5 SEC\nApplication will restart")
    case SWIFT_POWER_FAILED:
        lv_label_set_text(lowPowerStatusLabel, "Sleep failed:")
    default:
        break
    }
}

private func lowPowerTimerTick(_ timer: OpaquePointer?) {
    _ = timer
    refreshLowPowerStatus()
}

private func addLowPowerCard(_ panel: OpaquePointer?, _ verticalOffset: Int32, _ title: UnsafePointer<CChar>?) -> OpaquePointer? {
    let card = uiPixelPanelCreate(panel, 7, verticalOffset, 176, 42, UInt32(UI_PAPER))
    let label = uiPixelLabel(card, title, swift_lvgl_font_montserrat_14(), UInt32(UI_INK))
    lv_obj_center(label)
    return card
}

@_cdecl("demo_low_power_enter")
func demoLowPowerEnter() {
    lowPowerScreen = uiPixelScreenCreate("LOW POWER")
    guard let lowPowerScreen else { return }
    let panel = uiPixelPanelCreate(lowPowerScreen, 14, 54, 212, 190, UInt32(UI_PAPER))
    lowPowerStatusLabel = uiPixelLabel(panel, swift_platform_power_initial_status(), swift_lvgl_font_montserrat_14(), UInt32(UI_INK))
    if let lowPowerStatusLabel {
        lv_obj_set_width(lowPowerStatusLabel, 184)
        lv_obj_set_style_text_align(lowPowerStatusLabel, LV_TEXT_ALIGN_CENTER, 0)
        lv_obj_align(lowPowerStatusLabel, LV_ALIGN_TOP_MID, 0, 1)
    }
    lowPowerCards = (
        addLowPowerCard(panel, 56, "LIGHT SLEEP  |  2 SEC"),
        addLowPowerCard(panel, 110, "DEEP SLEEP   |  5 SEC")
    )
    lowPowerSelectedIndex = 0
    refreshLowPowerSelection()
    lowPowerMascot = uiPixelMascotCreate(lowPowerScreen, 101, 246)
    if !swift_platform_power_start() {
        if let lowPowerStatusLabel { lv_label_set_text(lowPowerStatusLabel, "Cannot create\nsleep worker") }
    }
    lowPowerTimer = lv_timer_create(lowPowerTimerTick, 100, nil)
    lv_screen_load(lowPowerScreen)
}

@_cdecl("demo_low_power_exit")
func demoLowPowerExit() {
    if let lowPowerTimer { lv_timer_delete(lowPowerTimer) }
    lowPowerTimer = nil
    swift_platform_power_stop()
    if let lowPowerScreen { lv_obj_delete(lowPowerScreen) }
    lowPowerScreen = nil
    lowPowerStatusLabel = nil
    lowPowerCards = (nil, nil)
    lowPowerMascot = nil
}

@_cdecl("demo_low_power_key")
func demoLowPowerKey(_ button: Int32, _ event: Int32) {
    guard event == Int32(BSP_BTN_CLICK.rawValue) else { return }
    if button == Int32(BSP_BTN_UP.rawValue) || button == Int32(BSP_BTN_DOWN.rawValue) {
        lowPowerSelectedIndex = (lowPowerSelectedIndex + 1) % 2
        refreshLowPowerSelection()
        uiPixelMascotJump(lowPowerMascot)
    } else if button == Int32(BSP_BTN_OK.rawValue) {
        if lowPowerSelectedIndex == 0 { swift_platform_power_run_light_sleep() }
        else { swift_platform_power_run_deep_sleep() }
    }
}
