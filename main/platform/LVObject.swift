class LVObject {

    let opaquePointer: OpaquePointer

    init(_ opaquePointer: OpaquePointer?) {
        guard let opaquePointer else {
            preconditionFailure("LVGL object allocation failed")
        }
        self.opaquePointer = opaquePointer
    }
    
    func removeScrollableFlag() {
        lv_obj_remove_flag(opaquePointer, LV_OBJ_FLAG_SCROLLABLE)
    }
    
    func setPosition(x: Int32, y: Int32) {
        lv_obj_set_pos(opaquePointer, x, y)
    }
    
    func setSize(width: Int32, height: Int32) {
        lv_obj_set_size(opaquePointer, width, height)
    }
    
    func setWidth(_ width: Int32) {
        lv_obj_set_width(opaquePointer, width)
    }
    
    func center() {
        lv_obj_center(opaquePointer)
    }
    
    func setBorderWidth(_ width: Int32) {
        lv_obj_set_style_border_width(opaquePointer, width, 0)
    }
    
    func setCornerRadius(_ radius: Int32) {
        lv_obj_set_style_radius(opaquePointer, radius, 0)
    }
    
    func setPadding(_ padding: Int32) {
        lv_obj_set_style_pad_all(opaquePointer, padding, 0)
    }
    
    func setBackgroundOpacity(_ opacity: UInt8) {
        lv_obj_set_style_bg_opa(opaquePointer, opacity, 0)
    }
    
    func align(_ alignment: LVAlignment, horizontalOffset: Int32 = 0, verticalOffset: Int32 = 0) {
        lv_obj_align(opaquePointer, alignment.value, horizontalOffset, verticalOffset)
    }
    
    func setBackgroundColor(_ color: UInt32) {
        lv_obj_set_style_bg_color(opaquePointer, lv_color_hex(color), 0)
    }
    
    func setTextColor(_ color: UInt32) {
        lv_obj_set_style_text_color(opaquePointer, lv_color_hex(color), 0)
    }
    
    func setBorderColor(_ color: UInt32) {
        lv_obj_set_style_border_color(opaquePointer, lv_color_hex(color), 0)
    }
    
    func setFont(_ font: UnsafePointer<lv_font_t>) {
        lv_obj_set_style_text_font(opaquePointer, font, 0)
    }
    
    func delete() {
        lv_obj_delete(opaquePointer)
    }
    
}
