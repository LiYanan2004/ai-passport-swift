enum LVAlignment {
    case automatic
    case topLeft
    case topCenter
    case topRight
    case bottomLeft
    case bottomCenter
    case bottomRight
    case leftCenter
    case rightCenter
    case center

    var value: lv_align_t {
        switch self {
        case .automatic: return LV_ALIGN_DEFAULT
        case .topLeft: return LV_ALIGN_TOP_LEFT
        case .topCenter: return LV_ALIGN_TOP_MID
        case .topRight: return LV_ALIGN_TOP_RIGHT
        case .bottomLeft: return LV_ALIGN_BOTTOM_LEFT
        case .bottomCenter: return LV_ALIGN_BOTTOM_MID
        case .bottomRight: return LV_ALIGN_BOTTOM_RIGHT
        case .leftCenter: return LV_ALIGN_LEFT_MID
        case .rightCenter: return LV_ALIGN_RIGHT_MID
        case .center: return LV_ALIGN_CENTER
        }
    }
}
