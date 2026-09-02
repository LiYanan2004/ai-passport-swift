private let pixelSky = UInt32(UI_SKY)
private let pixelInk = UInt32(UI_INK)
private let pixelPaper = UInt32(UI_PAPER)
private let pixelGrass = UInt32(UI_GRASS)
private let pixelGrassDark = UInt32(UI_GRASS_DARK)
private let pixelOrange = UInt32(UI_ORANGE)

private func pixelBlock(
    _ parent: OpaquePointer?,
    _ x: Int32,
    _ y: Int32,
    _ width: Int32,
    _ height: Int32,
    _ color: UInt32
) -> OpaquePointer? {
    let object = lv_obj_create(parent)
    lv_obj_remove_flag(object, LV_OBJ_FLAG_SCROLLABLE)
    lv_obj_set_pos(object, x, y)
    lv_obj_set_size(object, width, height)
    lv_obj_set_style_radius(object, 0, 0)
    lv_obj_set_style_border_width(object, 0, 0)
    lv_obj_set_style_pad_all(object, 0, 0)
    lv_obj_set_style_bg_color(object, lv_color_hex(color), 0)
    return object
}

private func addCloud(_ parent: OpaquePointer?, _ x: Int32, _ y: Int32) {
    _ = pixelBlock(parent, x + 1, y + 7, 43, 10, pixelInk)
    _ = pixelBlock(parent, x + 5, y + 4, 35, 10, 0xFFFFFF)
    _ = pixelBlock(parent, x + 12, y, 10, 9, 0xFFFFFF)
    _ = pixelBlock(parent, x + 27, y + 1, 9, 8, 0xFFFFFF)
}

@_cdecl("ui_pixel_label")
func uiPixelLabel(
    _ parent: OpaquePointer?,
    _ text: UnsafePointer<CChar>?,
    _ font: UnsafePointer<lv_font_t>?,
    _ color: UInt32
) -> OpaquePointer? {
    let label = lv_label_create(parent)
    lv_label_set_text(label, text)
    lv_obj_set_style_text_font(label, font, 0)
    lv_obj_set_style_text_color(label, lv_color_hex(color), 0)
    return label
}

@_cdecl("ui_pixel_screen_create")
func uiPixelScreenCreate(_ title: UnsafePointer<CChar>?) -> OpaquePointer? {
    let screen = lv_obj_create(nil)
    lv_obj_remove_flag(screen, LV_OBJ_FLAG_SCROLLABLE)
    lv_obj_set_style_bg_color(screen, lv_color_hex(pixelSky), 0)
    lv_obj_set_style_border_width(screen, 0, 0)
    lv_obj_set_style_pad_all(screen, 0, 0)

    addCloud(screen, 188, 8)
    _ = pixelBlock(screen, 0, 286, 240, 34, pixelGrass)
    _ = pixelBlock(screen, 0, 286, 240, 4, 0xA7D93E)
    for x in stride(from: 0, to: 240, by: 30) {
        _ = pixelBlock(screen, Int32(x), 312, 18, 8, pixelGrassDark)
        _ = pixelBlock(screen, Int32(x + 18), 316, 12, 4, 0x75452E)
    }

    _ = pixelBlock(screen, 9, 12, 151, 33, pixelInk)
    let plate = pixelBlock(screen, 5, 8, 151, 33, pixelPaper)
    lv_obj_set_style_border_color(plate, lv_color_hex(pixelInk), 0)
    lv_obj_set_style_border_width(plate, 3, 0)
    let heading = uiPixelLabel(plate, title, swift_lvgl_font_montserrat_20(), pixelInk)
    lv_obj_center(heading)
    return screen
}

@_cdecl("ui_pixel_panel_create")
func uiPixelPanelCreate(
    _ parent: OpaquePointer?,
    _ x: Int32,
    _ y: Int32,
    _ width: Int32,
    _ height: Int32,
    _ color: UInt32
) -> OpaquePointer? {
    _ = pixelBlock(parent, x + 5, y + 6, width, height, pixelInk)
    let panel = pixelBlock(parent, x, y, width, height, color)
    lv_obj_set_style_border_color(panel, lv_color_hex(pixelInk), 0)
    lv_obj_set_style_border_width(panel, 4, 0)
    lv_obj_set_style_pad_all(panel, 7, 0)
    return panel
}

@_cdecl("ui_pixel_mascot_create")
func uiPixelMascotCreate(_ parent: OpaquePointer?, _ x: Int32, _ y: Int32) -> OpaquePointer? {
    let mascot = lv_obj_create(parent)
    lv_obj_remove_flag(mascot, LV_OBJ_FLAG_SCROLLABLE)
    lv_obj_set_pos(mascot, x, y)
    lv_obj_set_size(mascot, 38, 48)
    lv_obj_set_style_bg_opa(mascot, UInt8(LV_OPA_TRANSP.rawValue), 0)
    lv_obj_set_style_border_width(mascot, 0, 0)
    lv_obj_set_style_pad_all(mascot, 0, 0)

    _ = pixelBlock(mascot, 18, 0, 3, 6, pixelInk)
    _ = pixelBlock(mascot, 16, 0, 7, 3, pixelOrange)
    _ = pixelBlock(mascot, 3, 6, 32, 24, pixelInk)
    _ = pixelBlock(mascot, 0, 12, 5, 10, 0x7557D9)
    _ = pixelBlock(mascot, 33, 12, 5, 10, 0x7557D9)
    _ = pixelBlock(mascot, 7, 10, 24, 16, 0xB9F3FF)
    let leftEye = pixelBlock(mascot, 11, 14, 4, 6, 0x294B7A)
    let rightEye = pixelBlock(mascot, 23, 14, 4, 6, 0x294B7A)
    _ = pixelBlock(mascot, 16, 22, 7, 2, 0x7557D9)
    _ = pixelBlock(mascot, 10, 29, 18, 4, pixelOrange)
    _ = pixelBlock(mascot, 8, 33, 22, 11, 0x7557D9)
    _ = pixelBlock(mascot, 3, 35, 5, 7, 0xB9F3FF)
    _ = pixelBlock(mascot, 30, 35, 5, 7, 0xB9F3FF)
    _ = pixelBlock(mascot, 8, 44, 9, 4, pixelInk)
    _ = pixelBlock(mascot, 21, 44, 9, 4, pixelInk)
    swift_lvgl_mascot_start_blink(leftEye)
    swift_lvgl_mascot_start_blink(rightEye)
    return mascot
}

@_cdecl("ui_pixel_mascot_jump")
func uiPixelMascotJump(_ mascot: OpaquePointer?) {
    guard let mascot else {
        return
    }
    swift_lvgl_mascot_jump(mascot)
}

@_cdecl("ui_pixel_set_selected")
func uiPixelSetSelected(_ panel: OpaquePointer?, _ selected: Bool, _ enabled: Bool) {
    let color: UInt32 = enabled ? (selected ? UInt32(UI_YELLOW) : pixelPaper) : 0x78909C
    lv_obj_set_style_bg_color(panel, lv_color_hex(color), 0)
    lv_obj_set_style_border_color(panel, lv_color_hex(selected ? 0xFFFFFF : pixelInk), 0)
}
