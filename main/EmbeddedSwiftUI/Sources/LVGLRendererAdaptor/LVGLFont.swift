/// Selects one of the statically linked Montserrat bitmap faces.
public enum LVGLFont {
    public static func pointer(pointSize: Int32) -> UnsafePointer<lv_font_t> {
        switch pointSize {
        case 12: return swift_lv_font_montserrat_12
        case 14: return swift_lv_font_montserrat_14
        case 16: return swift_lv_font_montserrat_16
        case 18: return swift_lv_font_montserrat_18
        case 20: return swift_lv_font_montserrat_20
        case 24: return swift_lv_font_montserrat_24
        case 28: return swift_lv_font_montserrat_28
        default: return swift_lv_font_montserrat_16
        }
    }
}
