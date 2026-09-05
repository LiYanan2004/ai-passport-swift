enum WiFiStorage {
    case flash
    case memory

    var espStorage: wifi_storage_t {
        switch self {
        case .flash: return WIFI_STORAGE_FLASH
        case .memory: return WIFI_STORAGE_RAM
        }
    }
}
