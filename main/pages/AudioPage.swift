private var audioScreen: OpaquePointer?
private var audioStatusLabel: OpaquePointer?
private var audioMascot: OpaquePointer?
private var audioTimer: OpaquePointer?

private func refreshAudioStatus() {
    guard let audioStatusLabel else { return }
    switch swift_platform_audio_state() {
    case SWIFT_AUDIO_PLAYING_TONE:
        lv_label_set_text(audioStatusLabel, "playing 1kHz...")
    case SWIFT_AUDIO_RECORDING:
        lv_label_set_text(audioStatusLabel, "recording 3s...\nspeak now")
    case SWIFT_AUDIO_PLAYING_RECORDING:
        lv_label_set_text(audioStatusLabel, "playing back...")
    case SWIFT_AUDIO_COMPLETE:
        lv_label_set_text(audioStatusLabel, "done. OK: tone\nUP: record")
    case SWIFT_AUDIO_FAILED:
        lv_label_set_text(audioStatusLabel, "audio operation failed")
    default:
        break
    }
}

private func audioTimerTick(_ timer: OpaquePointer?) {
    _ = timer
    refreshAudioStatus()
}

func enterAudioPage() {
    audioScreen = uiPixelScreenCreate("AUDIO")
    guard let audioScreen else { return }
    let panel = uiPixelPanelCreate(audioScreen, 18, 62, 204, 168, uiPaper)
    let record = uiPixelPanelCreate(panel, 58, 12, 72, 72, uiInk)
    let disc = lv_obj_create(record)
    lv_obj_set_size(disc, 36, 36)
    lv_obj_set_style_radius(disc, LV_RADIUS_CIRCLE, 0)
    lv_obj_set_style_bg_color(disc, lv_color_hex(uiRed), 0)
    lv_obj_set_style_border_width(disc, 0, 0)
    lv_obj_center(disc)

    audioStatusLabel = uiPixelLabel(panel, "OK: 1kHz TONE\nUP: RECORD + PLAY", swift_lvgl_font_montserrat_14(), uiInk)
    if let audioStatusLabel {
        lv_obj_set_style_text_align(audioStatusLabel, LV_TEXT_ALIGN_CENTER, 0)
        lv_obj_set_width(audioStatusLabel, 176)
        lv_obj_align(audioStatusLabel, LV_ALIGN_BOTTOM_MID, 0, -9)
    }
    audioMascot = uiPixelMascotCreate(audioScreen, 101, 238)
    swift_platform_audio_start()
    audioTimer = lv_timer_create(audioTimerTick, 100, nil)
    refreshAudioStatus()
    lv_screen_load(audioScreen)
}

func exitAudioPage() {
    if let audioTimer { lv_timer_delete(audioTimer) }
    audioTimer = nil
    swift_platform_audio_stop()
    if let audioScreen { lv_obj_delete(audioScreen) }
    audioScreen = nil
    audioStatusLabel = nil
    audioMascot = nil
}

func handleAudioPageKey(_ button: Int32, _ event: Int32) {
    guard event == Int32(BSP_BTN_CLICK.rawValue) else { return }
    if button == Int32(BSP_BTN_OK.rawValue) {
        swift_platform_audio_request_tone()
        uiPixelMascotJump(audioMascot)
    } else if button == Int32(BSP_BTN_UP.rawValue) {
        swift_platform_audio_request_recording()
        uiPixelMascotJump(audioMascot)
    }
}
