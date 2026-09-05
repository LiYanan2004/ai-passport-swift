final class WiFi {
    static let shared = WiFi()

    private(set) var lastError: esp_err_t = ESP_OK

    var storage: WiFiStorage = .flash {
        didSet {
            lastError = esp_wifi_set_storage(storage.espStorage)
            if lastError != ESP_OK { storage = oldValue }
        }
    }

    var mode: WiFiMode {
        get {
            var value = WIFI_MODE_NULL
            lastError = esp_wifi_get_mode(&value)
            return WiFiMode(value) ?? .station
        }
        set {
            lastError = esp_wifi_set_mode(newValue.espMode)
        }
    }

    var isEnterpriseAuthenticationEnabled = false {
        didSet {
            lastError = isEnterpriseAuthenticationEnabled
                ? esp_wifi_sta_enterprise_enable()
                : esp_wifi_sta_enterprise_disable()
            if lastError != ESP_OK { isEnterpriseAuthenticationEnabled = oldValue }
        }
    }

    var connectedAccessPoint: WiFiAccessPoint? {
        var record = wifi_ap_record_t()
        lastError = esp_wifi_sta_get_ap_info(&record)
        guard lastError == ESP_OK else { return nil }
        return accessPoint(from: record)
    }

    var scanResults: [WiFiAccessPoint]? {
        var recordCount: UInt16 = 0
        lastError = esp_wifi_scan_get_ap_num(&recordCount)
        guard lastError == ESP_OK else {
            _ = esp_wifi_clear_ap_list()
            return nil
        }
        guard recordCount > 0 else {
            _ = esp_wifi_clear_ap_list()
            return []
        }

        var records = Array(repeating: wifi_ap_record_t(), count: Int(recordCount))
        lastError = records.withUnsafeMutableBufferPointer { recordBuffer in
            esp_wifi_scan_get_ap_records(&recordCount, recordBuffer.baseAddress)
        }
        guard lastError == ESP_OK else {
            _ = esp_wifi_clear_ap_list()
            return nil
        }
        return records.prefix(Int(recordCount)).map(accessPoint(from:))
    }

    private var defaultStation: OpaquePointer?

    private init() {}

    @discardableResult
    func initializeNonvolatileStorage() -> esp_err_t {
        record(nvs_flash_init())
    }

    @discardableResult
    func initializeNetworkStack() -> esp_err_t {
        record(esp_netif_init())
    }

    @discardableResult
    func createDefaultEventLoop() -> esp_err_t {
        record(esp_event_loop_create_default())
    }

    func createDefaultStation() -> Bool {
        guard defaultStation == nil else { return true }
        defaultStation = esp_netif_create_default_wifi_sta()
        return defaultStation != nil
    }

    func destroyDefaultStation() {
        guard let defaultStation else { return }
        esp_netif_destroy_default_wifi(UnsafeMutableRawPointer(defaultStation))
        self.defaultStation = nil
    }

    @discardableResult
    func initialize() -> esp_err_t {
        var configuration = passport_wifi_default_config()
        return record(esp_wifi_init(&configuration))
    }

    @discardableResult
    func configureCountryCode(_ countryCode: StaticString) -> esp_err_t {
        record(esp_wifi_set_country_code(
            UnsafePointer<CChar>(OpaquePointer(countryCode.utf8Start)),
            true
        ))
    }

    @discardableResult
    func deinitialize() -> esp_err_t { record(esp_wifi_deinit()) }

    @discardableResult
    func start() -> esp_err_t { record(esp_wifi_start()) }

    @discardableResult
    func stop() -> esp_err_t { record(esp_wifi_stop()) }

    @discardableResult
    func connect() -> esp_err_t { record(esp_wifi_connect()) }

    @discardableResult
    func startScan(
        configuration: WiFiScanConfiguration = .defaultConfiguration,
        blocksUntilComplete: Bool = false
    ) -> esp_err_t {
        var value = wifi_scan_config_t()
        value.show_hidden = configuration.showsHiddenNetworks
        value.scan_type = configuration.scanType
        value.scan_time.active.min = configuration.minimumActiveTimeMilliseconds
        value.scan_time.active.max = configuration.maximumActiveTimeMilliseconds
        return record(esp_wifi_scan_start(&value, blocksUntilComplete))
    }

    @discardableResult
    func stopScan() -> esp_err_t { record(esp_wifi_scan_stop()) }

    @discardableResult
    func configure(_ configuration: WiFiPersonalStationConfiguration) -> esp_err_t {
        guard !configuration.ssid.isEmpty,
              configuration.ssid.utf8.count <= 32,
              (configuration.password?.utf8.count ?? 0) <= 63,
              configuration.bssid == nil || configuration.bssid?.count == 6 else {
            return record(ESP_ERR_INVALID_ARG)
        }
        if configuration.security == .wpa3Only,
           configuration.password?.isEmpty != false {
            return record(ESP_ERR_INVALID_ARG)
        }

        var value = wifi_config_t()
        guard copySSID(configuration.ssid, to: &value.sta.ssid),
              copyPassword(configuration.password, to: &value.sta.password),
              copyBSSID(configuration.bssid, to: &value.sta.bssid) else {
            return record(ESP_ERR_INVALID_ARG)
        }
        value.sta.channel = configuration.channel
        value.sta.bssid_set = configuration.bssid != nil
        value.sta.pmf_cfg.capable = true
        value.sta.pmf_cfg.required = configuration.security == .wpa3Only
        value.sta.threshold.authmode = authenticationMode(
            security: configuration.security,
            usesPassword: configuration.password?.isEmpty == false
        )
        value.sta.scan_method = WIFI_ALL_CHANNEL_SCAN
        value.sta.sae_pwe_h2e = WPA3_SAE_PWE_BOTH

        isEnterpriseAuthenticationEnabled = false
        return record(esp_wifi_set_config(WIFI_IF_STA, &value))
    }

    @discardableResult
    func configure(_ configuration: WiFiEnterpriseTLSStationConfiguration) -> esp_err_t {
        guard !configuration.ssid.isEmpty,
              configuration.ssid.utf8.count <= 32,
              (configuration.identity?.utf8.count ?? 0) <= 127,
              !configuration.caCertificate.isEmpty,
              !configuration.clientCertificate.isEmpty,
              !configuration.privateKey.isEmpty,
              configuration.privateKey.count <= 4_096,
              configuration.caCertificate.count <= Int32.max,
              configuration.clientCertificate.count <= Int32.max,
              (configuration.privateKeyPassword?.utf8.count ?? 0) <= Int32.max,
              configuration.bssid == nil || configuration.bssid?.count == 6 else {
            return record(ESP_ERR_INVALID_ARG)
        }

        var value = wifi_config_t()
        guard copySSID(configuration.ssid, to: &value.sta.ssid),
              copyBSSID(configuration.bssid, to: &value.sta.bssid) else {
            return record(ESP_ERR_INVALID_ARG)
        }
        value.sta.channel = configuration.channel
        value.sta.bssid_set = configuration.bssid != nil
        value.sta.pmf_cfg.capable = true
        value.sta.threshold.authmode = WIFI_AUTH_WPA2_ENTERPRISE
        value.sta.scan_method = WIFI_ALL_CHANNEL_SCAN

        isEnterpriseAuthenticationEnabled = false
        var error = esp_wifi_set_config(WIFI_IF_STA, &value)
        guard error == ESP_OK else { return record(error) }
        if let identity = configuration.identity {
            let identityBytes = Array(identity.utf8)
            error = identityBytes.withUnsafeBufferPointer { identityBuffer in
                esp_eap_client_set_identity(identityBuffer.baseAddress, Int32(identityBuffer.count))
            }
            guard error == ESP_OK else { return record(error) }
        }
        error = configuration.caCertificate.withUnsafeBufferPointer { certificateBuffer in
            esp_eap_client_set_ca_cert(
                certificateBuffer.baseAddress,
                Int32(certificateBuffer.count)
            )
        }
        guard error == ESP_OK else { return record(error) }
        error = setEnterpriseCertificateAndKey(configuration)
        guard error == ESP_OK else { return record(error) }
        // EAP-TLS credentials must not leave PEAP, TTLS, or FAST available for
        // negotiation. The ESP-IDF enterprise example likewise selects TLS
        // before enabling the enterprise station.
        error = esp_eap_client_set_eap_methods(ESP_EAP_TYPE_TLS)
        guard error == ESP_OK else { return record(error) }
        isEnterpriseAuthenticationEnabled = true
        return lastError
    }

    private func record(_ error: esp_err_t) -> esp_err_t {
        lastError = error
        return error
    }

    private func authenticationMode(
        security: WiFiPersonalSecurity,
        usesPassword: Bool
    ) -> wifi_auth_mode_t {
        switch security {
        case .wpa3Only: return WIFI_AUTH_WPA3_PSK
        case .wpa2OrWpa3: return usesPassword ? WIFI_AUTH_WPA2_PSK : WIFI_AUTH_OPEN
        }
    }

    private func setEnterpriseCertificateAndKey(
        _ configuration: WiFiEnterpriseTLSStationConfiguration
    ) -> esp_err_t {
        configuration.clientCertificate.withUnsafeBufferPointer { clientCertificateBuffer in
            configuration.privateKey.withUnsafeBufferPointer { privateKeyBuffer in
                if let privateKeyPassword = configuration.privateKeyPassword {
                    var passwordBytes = Array(privateKeyPassword.utf8)
                    passwordBytes.append(0)
                    return passwordBytes.withUnsafeBufferPointer { passwordBuffer in
                        esp_eap_client_set_certificate_and_key(
                            clientCertificateBuffer.baseAddress,
                            Int32(clientCertificateBuffer.count),
                            privateKeyBuffer.baseAddress,
                            Int32(privateKeyBuffer.count),
                            passwordBuffer.baseAddress,
                            Int32(passwordBuffer.count - 1)
                        )
                    }
                }
                return esp_eap_client_set_certificate_and_key(
                    clientCertificateBuffer.baseAddress,
                    Int32(clientCertificateBuffer.count),
                    privateKeyBuffer.baseAddress,
                    Int32(privateKeyBuffer.count),
                    nil,
                    0
                )
            }
        }
    }

    private func copySSID<T>(_ ssid: String, to destination: inout T) -> Bool {
        copy(Array(ssid.utf8), to: &destination, permitsFullCapacity: true)
    }

    private func copyPassword<T>(_ password: String?, to destination: inout T) -> Bool {
        guard let password else { return true }
        return copy(Array(password.utf8), to: &destination, permitsFullCapacity: false)
    }

    private func copyBSSID<T>(_ bssid: [UInt8]?, to destination: inout T) -> Bool {
        guard let bssid else { return true }
        return copy(bssid, to: &destination, permitsFullCapacity: true)
    }

    private func copy<T>(
        _ source: [UInt8],
        to destination: inout T,
        permitsFullCapacity: Bool
    ) -> Bool {
        withUnsafeMutableBytes(of: &destination) { destinationBytes in
            let maximumCount = permitsFullCapacity
                ? destinationBytes.count
                : destinationBytes.count - 1
            guard source.count <= maximumCount,
                  let destinationAddress = destinationBytes.baseAddress else {
                return false
            }
            source.withUnsafeBytes { sourceBytes in
                if let sourceAddress = sourceBytes.baseAddress {
                    destinationAddress.copyMemory(from: sourceAddress, byteCount: sourceBytes.count)
                }
            }
            if source.count < destinationBytes.count {
                destinationAddress.advanced(by: source.count).storeBytes(
                    of: UInt8(0), as: UInt8.self
                )
            }
            return true
        }
    }

    private func accessPoint(from record: wifi_ap_record_t) -> WiFiAccessPoint {
        var record = record
        let ssid = withUnsafeBytes(of: &record.ssid) { ssidBytes in
            let length = ssidBytes.firstIndex(of: 0) ?? ssidBytes.count
            return String(decoding: ssidBytes.prefix(length), as: UTF8.self)
        }
        let bssid = withUnsafeBytes(of: &record.bssid) { bssidBytes in
            Array(bssidBytes)
        }
        return WiFiAccessPoint(
            ssid: ssid,
            signalStrength: Int32(record.rssi),
            channel: record.primary,
            bssid: bssid
        )
    }
}
