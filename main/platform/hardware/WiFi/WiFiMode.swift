enum WiFiMode {
    case station
    case accessPoint
    case stationAndAccessPoint
    case nan

    var espMode: wifi_mode_t {
        switch self {
        case .station: return WIFI_MODE_STA
        case .accessPoint: return WIFI_MODE_AP
        case .stationAndAccessPoint: return WIFI_MODE_APSTA
        case .nan: return WIFI_MODE_NAN
        }
    }

    init?(_ value: wifi_mode_t) {
        switch value {
        case WIFI_MODE_STA: self = .station
        case WIFI_MODE_AP: self = .accessPoint
        case WIFI_MODE_APSTA: self = .stationAndAccessPoint
        case WIFI_MODE_NAN: self = .nan
        default: return nil
        }
    }
}
