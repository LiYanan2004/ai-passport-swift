struct WiFiEnterpriseTLSStationConfiguration {
    let ssid: String
    let identity: String?
    let caCertificate: [UInt8]
    let clientCertificate: [UInt8]
    let privateKey: [UInt8]
    let privateKeyPassword: String?
    let channel: UInt8
    let bssid: [UInt8]?

    init(
        ssid: String,
        identity: String? = nil,
        caCertificate: [UInt8],
        clientCertificate: [UInt8],
        privateKey: [UInt8],
        privateKeyPassword: String? = nil,
        channel: UInt8 = 0,
        bssid: [UInt8]? = nil
    ) {
        self.ssid = ssid
        self.identity = identity
        self.caCertificate = caCertificate
        self.clientCertificate = clientCertificate
        self.privateKey = privateKey
        self.privateKeyPassword = privateKeyPassword
        self.channel = channel
        self.bssid = bssid
    }
}
