struct WiFiPersonalStationConfiguration {
    let ssid: String
    let password: String?
    let security: WiFiPersonalSecurity
    let channel: UInt8
    let bssid: [UInt8]?

    init(
        ssid: String,
        password: String? = nil,
        security: WiFiPersonalSecurity = .wpa2OrWpa3,
        channel: UInt8 = 0,
        bssid: [UInt8]? = nil
    ) {
        self.ssid = ssid
        self.password = password
        self.security = security
        self.channel = channel
        self.bssid = bssid
    }
}
