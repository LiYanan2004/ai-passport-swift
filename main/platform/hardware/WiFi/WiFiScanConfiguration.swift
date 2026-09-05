struct WiFiScanConfiguration {
    var showsHiddenNetworks = false
    var scanType: wifi_scan_type_t = WIFI_SCAN_TYPE_ACTIVE
    var minimumActiveTimeMilliseconds: UInt32 = 0
    var maximumActiveTimeMilliseconds: UInt32 = 0

    static var defaultConfiguration: WiFiScanConfiguration {
        WiFiScanConfiguration()
    }
}
