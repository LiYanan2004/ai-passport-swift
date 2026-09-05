final class WiFiConnectionController {
    private enum WiFiLifecycleState: Equatable {
        case stopped
        case initialized
        case started
        case stopping
    }

    static let shared: WiFiConnectionController = WiFiConnectionController()

    private static let connectionAttemptTimerName: StaticString = "wifi_retry"
    private static let countryCode: StaticString = "CN"
    private static let nextCandidateDelayMicroseconds: UInt64 = 0
    private static let authenticationRetryDelayMicroseconds: UInt64 = 750_000
    private static let authenticationRetryLimit = 2

    private var wifiEventHandler: UnsafeMutableRawPointer?
    private var ipEventHandler: UnsafeMutableRawPointer?
    private var connectionAttemptTimer: OpaquePointer?
    private var candidateSelector = WiFiCandidateSelector()
    private var reconnectTimer = WiFiReconnectTimer()
    private var connectionCandidates: [WiFiConnectionCandidate] = []
    private var lifecycleState: WiFiLifecycleState = .stopped
    private var resourceState: WiFiResourceState = []
    private var operationFlags: WiFiOperationFlags = []
    private var authenticationRetryCount = 0
    private var lastError: esp_err_t = ESP_OK

    private(set) var scanState: WiFiScanState = .idle
    private(set) var connectionState: WiFiConnectionState = .disconnected
    private(set) var scanResults = ""
    private(set) var connectedSSID = ""

    private init() {}

    var errorDescription: String {
        guard let errorName = esp_err_to_name(lastError) else {
            return "Unknown error"
        }
        return String(cString: errorName)
    }

    func start() {
        guard lifecycleState != .initialized, lifecycleState != .started else {
            return
        }

        lifecycleState = .stopped
        scanState = .starting
        connectionState = .disconnected
        lastError = ESP_OK
        operationFlags = []
        authenticationRetryCount = 0
        reconnectTimer.reset()
        scanResults = ""
        connectedSSID = ""
        candidateSelector.reset(candidateCount: 0)
        connectionCandidates = []

        // A credentials-free build is the safe default for development and
        // factory verification. Leave the radio untouched until a local
        // credentials file is supplied, avoiding an unnecessary Wi-Fi stack
        // allocation on a board that only needs the display at boot.
        guard credentialCount > 0 else {
            scanState = .ready
            scanResults = "No Wi-Fi credentials configured"
            lastError = ESP_OK
            return
        }

        var error = prepareNVS()
        guard error == ESP_OK else {
            failStartup(error)
            return
        }
        error = prepareNetwork()
        guard error == ESP_OK else {
            failStartup(error)
            return
        }

        guard WiFi.shared.createDefaultStation() else {
            failStartup(ESP_ERR_NO_MEM)
            return
        }

        error = WiFi.shared.initialize()
        guard error == ESP_OK else {
            failStartup(error)
            return
        }
        lifecycleState = .initialized

        // ESP-IDF starts in world-safe mode, which scans only channels 1–11.
        // The product's China deployment requires channels 12 and 13 before a
        // first association can receive the AP's 802.11d country information.
        error = WiFi.shared.configureCountryCode(WiFiConnectionController.countryCode)
        guard error == ESP_OK else {
            failStartup(error)
            return
        }

        error = esp_event_handler_instance_register(
            WIFI_EVENT,
            ESP_EVENT_ANY_ID,
            swiftWiFiEventHandler,
            nil,
            &wifiEventHandler
        )
        guard error == ESP_OK else {
            failStartup(error)
            return
        }

        error = esp_event_handler_instance_register(
            IP_EVENT,
            Int32(IP_EVENT_STA_GOT_IP.rawValue),
            swiftIPEventHandler,
            nil,
            &ipEventHandler
        )
        guard error == ESP_OK else {
            failStartup(error)
            return
        }

        var connectionAttemptTimerArguments = esp_timer_create_args_t()
        connectionAttemptTimerArguments.callback = swiftWiFiConnectCurrentCandidate
        connectionAttemptTimerArguments.name = UnsafePointer<CChar>(
            OpaquePointer(WiFiConnectionController.connectionAttemptTimerName.utf8Start)
        )
        error = esp_timer_create(&connectionAttemptTimerArguments, &connectionAttemptTimer)
        guard error == ESP_OK else {
            failStartup(error)
            return
        }

        WiFi.shared.storage = .memory
        error = WiFi.shared.lastError
        guard error == ESP_OK else {
            failStartup(error)
            return
        }
        WiFi.shared.mode = .station
        error = WiFi.shared.lastError
        guard error == ESP_OK else {
            failStartup(error)
            return
        }
        error = WiFi.shared.start()
        guard error == ESP_OK else {
            failStartup(error)
            return
        }

        lifecycleState = .started
        scanState = .idle
        if credentialCount == 0 {
            lastError = ESP_ERR_NOT_FOUND
            scanResults = "No Wi-Fi credentials configured"
        } else {
            scheduleConnectionAttempt(after: 1)
        }
    }

    private func stop() {
        releaseResources()
        scanState = .idle
    }

    func rescan() {
        guard lifecycleState == .started else {
            lastError = ESP_ERR_INVALID_STATE
            scanState = .failed
            return
        }
        if connectionState == .connecting {
            operationFlags.insert(.rescanAfterConnection)
            return
        }
        guard scanState != .scanning else {
            return
        }
        reconnectTimer.reset()
        _ = startScan(selectCandidates: connectionState == .disconnected)
    }

    func getRSSI() -> Int32? {
        guard connectionState == .connected else {
            return nil
        }
        return WiFi.shared.connectedAccessPoint?.signalStrength
    }

    fileprivate func handleWiFiEvent(_ eventID: Int32, eventData: UnsafeMutableRawPointer?) {
        if eventID == WIFI_EVENT_STA_START.rawValue {
            if credentialCount > 0 {
                scheduleConnectionAttempt(after: 1)
            }
        } else if eventID == WIFI_EVENT_SCAN_DONE.rawValue {
            handleScanCompleted()
        } else if eventID == WIFI_EVENT_STA_DISCONNECTED.rawValue {
            handleDisconnected(eventData)
        }
    }

    fileprivate func handleIPEvent(_ eventID: Int32) {
        guard eventID == IP_EVENT_STA_GOT_IP.rawValue else {
            return
        }
        if let candidateIndex = candidateSelector.candidateIndex,
           candidateIndex < connectionCandidates.count,
           let credential = credential(at: connectionCandidates[candidateIndex].credentialIndex) {
            connectedSSID = credential.ssid
        }
        connectionState = .connected
        authenticationRetryCount = 0
        reconnectTimer.reset()
        print("Wi-Fi connected: SSID=\(connectedSSID)")
        if operationFlags.contains(.rescanAfterConnection) {
            operationFlags.remove(.rescanAfterConnection)
            rescan()
        }
    }

    fileprivate func connectCurrentCandidate() {
        guard lifecycleState == .started, scanState != .scanning else {
            return
        }
        guard credentialCount > 0 else {
            return
        }
        guard operationFlags.contains(.candidatesScanned) else {
            if startScan(selectCandidates: true) != ESP_OK {
                scheduleRetry()
            }
            return
        }

        while let candidateIndex = candidateSelector.candidateIndex,
              candidateIndex < connectionCandidates.count {
            let candidate = connectionCandidates[candidateIndex]
            guard let credential = credential(at: candidate.credentialIndex) else {
                _ = candidateSelector.advance()
                continue
            }
            print("Wi-Fi candidate \(candidateIndex + 1)/\(connectionCandidates.count): channel=\(candidate.channel)")
            var error = applyCredential(
                credential,
                channel: candidate.channel,
                bssid: nil
            )
            if error == ESP_OK {
                connectionState = .connecting
                error = WiFi.shared.connect()
            }
            if error == ESP_OK {
                lastError = ESP_OK
                return
            }
            let errorName = esp_err_to_name(error).map { String(cString: $0) } ?? "unknown"
            print("Wi-Fi candidate \(candidateIndex + 1) setup failed: \(errorName)")
            lastError = error
            connectionState = .disconnected
            _ = candidateSelector.advance()
        }

        connectionState = .disconnected
        operationFlags.remove(.candidatesScanned)
        scheduleRetry()
    }

    private var credentialCount: Int {
        WiFiCredentials.all.count
    }

    private func credential(at index: Int) -> WiFiCredential? {
        guard index >= 0, index < credentialCount else {
            return nil
        }
        return WiFiCredentials.all[index]
    }

    private func prepareNVS() -> esp_err_t {
        guard !resourceState.contains(.nvsReady) else {
            return ESP_OK
        }
        let error = WiFi.shared.initializeNonvolatileStorage()
        if error == ESP_OK || error == ESP_ERR_INVALID_STATE {
            resourceState.insert(.nvsReady)
            return ESP_OK
        }
        return error
    }

    private func prepareNetwork() -> esp_err_t {
        if !resourceState.contains(.networkReady) {
            let error = WiFi.shared.initializeNetworkStack()
            guard error == ESP_OK || error == ESP_ERR_INVALID_STATE else {
                return error
            }
            resourceState.insert(.networkReady)
        }
        if !resourceState.contains(.eventLoopReady) {
            let error = WiFi.shared.createDefaultEventLoop()
            guard error == ESP_OK || error == ESP_ERR_INVALID_STATE else {
                return error
            }
            resourceState.insert(.eventLoopReady)
        }
        return ESP_OK
    }

    private func failStartup(_ error: esp_err_t) {
        lastError = error
        scanState = .failed
        releaseResources()
    }

    private func releaseResources() {
        let wasInitialized = lifecycleState == .initialized || lifecycleState == .started
        let wasStarted = lifecycleState == .started
        lifecycleState = .stopping
        if let connectionAttemptTimer {
            _ = esp_timer_stop(connectionAttemptTimer)
            _ = esp_timer_delete(connectionAttemptTimer)
            self.connectionAttemptTimer = nil
        }
        if wasStarted {
            _ = WiFi.shared.stopScan()
            _ = WiFi.shared.stop()
        }
        if let wifiEventHandler {
            _ = esp_event_handler_instance_unregister(
                WIFI_EVENT,
                ESP_EVENT_ANY_ID,
                wifiEventHandler
            )
            self.wifiEventHandler = nil
        }
        if let ipEventHandler {
            _ = esp_event_handler_instance_unregister(
                IP_EVENT,
                Int32(IP_EVENT_STA_GOT_IP.rawValue),
                ipEventHandler
            )
            self.ipEventHandler = nil
        }
        if wasInitialized {
            WiFi.shared.isEnterpriseAuthenticationEnabled = false
            _ = WiFi.shared.deinitialize()
        }
        WiFi.shared.destroyDefaultStation()
        candidateSelector.reset(candidateCount: 0)
        connectionCandidates = []
        operationFlags = []
        authenticationRetryCount = 0
        reconnectTimer.reset()
        connectionState = .disconnected
        connectedSSID = ""
        lifecycleState = .stopped
    }

    private func scheduleConnectionAttempt(after delayMicroseconds: UInt64) {
        guard let connectionAttemptTimer, lifecycleState != .stopping else {
            return
        }
        _ = esp_timer_stop(connectionAttemptTimer)
        _ = esp_timer_start_once(connectionAttemptTimer, delayMicroseconds)
    }

    private func scheduleRetry() {
        let delayMicroseconds = reconnectTimer.nextFireDelayMicroseconds()
        print("Wi-Fi retry in \(delayMicroseconds / 1_000_000) seconds")
        scheduleConnectionAttempt(after: delayMicroseconds)
    }

    private func startScan(selectCandidates: Bool) -> esp_err_t {
        var configuration = WiFiScanConfiguration()
        configuration.showsHiddenNetworks = true
        if selectCandidates {
            configuration.scanType = WIFI_SCAN_TYPE_ACTIVE
            configuration.minimumActiveTimeMilliseconds = 0
            // Enterprise access points can omit a probe response during a
            // short dwell interval. Use a 120 ms active dwell interval.
            configuration.maximumActiveTimeMilliseconds = 120
        }
        let error = WiFi.shared.startScan(configuration: configuration)
        if error == ESP_OK {
            if selectCandidates {
                operationFlags.insert(.scanSelectsCandidates)
            } else {
                operationFlags.remove(.scanSelectsCandidates)
            }
            scanState = .scanning
            if selectCandidates {
                connectionState = .connecting
            }
        } else {
            if selectCandidates {
                operationFlags.remove(.candidatesScanned)
            }
            lastError = error
            scanState = .failed
            let errorName = esp_err_to_name(error).map { String(cString: $0) } ?? "unknown"
            print("Wi-Fi scan start failed: \(errorName)")
        }
        return error
    }

    private func handleScanCompleted() {
        guard scanState == .scanning else {
            return
        }
        let selectsCandidates = operationFlags.contains(.scanSelectsCandidates)
        let error = collectScanResults(selectCandidates: selectsCandidates)
        if error != ESP_OK {
            lastError = error
            scanState = .failed
        }
        guard connectionState != .connected else {
            return
        }
        if error == ESP_OK, candidateSelector.hasCandidate {
            scheduleConnectionAttempt(after: WiFiConnectionController.nextCandidateDelayMicroseconds)
        } else {
            operationFlags.remove(.candidatesScanned)
            connectionState = .disconnected
            scheduleRetry()
        }
    }

    private func collectScanResults(selectCandidates: Bool) -> esp_err_t {
        guard let accessPoints = WiFi.shared.scanResults else {
            return WiFi.shared.lastError
        }
        guard !accessPoints.isEmpty else {
            var configuredSSIDs: [String] = []
            for credential in WiFiCredentials.all {
                configuredSSIDs.append(credential.ssid)
            }
            scanResults = KnownWiFiScanFormatter.format(
                configuredSSIDs: configuredSSIDs,
                visibleAccessPoints: []
            )
            prepareCandidates(from: [], selectCandidates: selectCandidates)
            scanState = .ready
            return ESP_OK
        }

        var configuredSSIDs: [String] = []
        for credential in WiFiCredentials.all {
            configuredSSIDs.append(credential.ssid)
        }
        let visibleAccessPoints = accessPoints.map {
            KnownWiFiAccessPoint(
                ssid: $0.ssid,
                rssi: Int($0.signalStrength),
                channel: Int($0.channel)
            )
        }
        scanResults = KnownWiFiScanFormatter.format(
            configuredSSIDs: configuredSSIDs,
            visibleAccessPoints: visibleAccessPoints
        )
        prepareCandidates(from: accessPoints, selectCandidates: selectCandidates)
        if selectCandidates {
            print("Wi-Fi scan complete: accessPoints=\(accessPoints.count) hasCandidate=\(candidateSelector.hasCandidate)")
        }
        scanState = .ready
        return ESP_OK
    }

    private func prepareCandidates(
        from accessPoints: [WiFiAccessPoint],
        selectCandidates: Bool
    ) {
        guard selectCandidates else {
            return
        }
        connectionCandidates = []
        for credentialIndex in 0..<credentialCount {
            guard let credential = credential(at: credentialIndex),
                  credential.ssid.utf8.count <= 32 else {
                continue
            }
            for accessPoint in accessPoints where matchesSSID(
                credential.ssid,
                accessPoint: accessPoint
            ) {
                // Some enterprise WLAN controllers advertise BSSIDs that cannot
                // accept a direct association. Keep each discovered channel, but
                // let the Wi-Fi driver select the valid AP within that channel.
                guard !connectionCandidates.contains(where: {
                    $0.credentialIndex == credentialIndex &&
                        $0.channel == accessPoint.channel
                }) else {
                    continue
                }
                connectionCandidates.append(
                    WiFiConnectionCandidate(
                        credentialIndex: credentialIndex,
                        channel: accessPoint.channel
                    )
                )
            }
        }
        if connectionCandidates.isEmpty {
            // A hidden SSID, a missed probe response, or a briefly suppressed
            // enterprise AP is absent from scan records even though the Wi-Fi
            // driver can still discover it during esp_wifi_connect(). Retain
            // every configured credential as an unpinned fallback candidate.
            for credentialIndex in 0..<credentialCount where credential(at: credentialIndex) != nil {
                connectionCandidates.append(
                    WiFiConnectionCandidate(
                        credentialIndex: credentialIndex,
                        channel: 0
                    )
                )
            }
            print("Wi-Fi scan found no configured SSID; trying unpinned known networks")
        }
        candidateSelector.reset(candidateCount: connectionCandidates.count)
        operationFlags.insert(.candidatesScanned)
        authenticationRetryCount = 0
    }

    private func handleDisconnected(_ eventData: UnsafeMutableRawPointer?) {
        let wasConnected = connectionState == .connected
        let reason = eventData?
            .assumingMemoryBound(to: wifi_event_sta_disconnected_t.self)
            .pointee.reason
        print("Wi-Fi disconnected: reason=\(reason.map { Int($0) } ?? -1) connected=\(wasConnected)")
        connectionState = .disconnected
        connectedSSID = ""
        if wasConnected {
            operationFlags.remove(.candidatesScanned)
        }
        guard lifecycleState != .stopping else {
            return
        }
        if scanState == .scanning {
            operationFlags.insert(.scanSelectsCandidates)
            return
        }

        let isAuthenticationFailure = reason.map {
            $0 == UInt8(WIFI_REASON_AUTH_FAIL.rawValue) ||
                $0 == UInt8(WIFI_REASON_AUTH_EXPIRE.rawValue)
        } ?? false
        if !wasConnected,
           isAuthenticationFailure,
           authenticationRetryCount < WiFiConnectionController.authenticationRetryLimit {
            authenticationRetryCount += 1
            scheduleConnectionAttempt(
                after: WiFiConnectionController.authenticationRetryDelayMicroseconds
            )
            return
        }
        authenticationRetryCount = 0
        if !wasConnected, !candidateSelector.advance() {
            operationFlags.remove(.candidatesScanned)
            scheduleRetry()
            return
        }
        scheduleConnectionAttempt(after: WiFiConnectionController.nextCandidateDelayMicroseconds)
    }

    private func applyCredential(
        _ credential: WiFiCredential,
        channel: UInt8,
        bssid: [UInt8]?
    ) -> esp_err_t {
        if credential.authentication == .personal {
            return WiFi.shared.configure(
                WiFiPersonalStationConfiguration(
                    ssid: credential.ssid,
                    password: credential.password,
                    security: credential.personalSecurity,
                    channel: channel,
                    bssid: bssid
                )
            )
        }

        guard let caCertificate = credential.caCertificate,
              let clientCertificate = credential.clientCertificate,
              let privateKey = credential.privateKey else {
            return ESP_ERR_INVALID_ARG
        }
        return WiFi.shared.configure(
            WiFiEnterpriseTLSStationConfiguration(
                ssid: credential.ssid,
                identity: credential.eapIdentity,
                caCertificate: caCertificate,
                clientCertificate: clientCertificate,
                privateKey: privateKey,
                privateKeyPassword: credential.privateKeyPassword,
                channel: channel,
                bssid: bssid
            )
        )
    }

    private func matchesSSID(
        _ credentialSSID: String,
        accessPoint: WiFiAccessPoint
    ) -> Bool {
        let credentialBytes = Array(credentialSSID.utf8)
        let accessPointBytes = Array(accessPoint.ssid.utf8)
        guard credentialBytes.count == accessPointBytes.count else {
            return false
        }
        for index in credentialBytes.indices
        where credentialBytes[index] != accessPointBytes[index] {
            return false
        }
        return true
    }
}

@_cdecl("swift_wifi_event_handler")
func swiftWiFiEventHandler(
    _ eventHandlerArgument: UnsafeMutableRawPointer?,
    _ eventBase: UnsafePointer<CChar>?,
    _ eventID: Int32,
    _ eventData: UnsafeMutableRawPointer?
) {
    _ = eventHandlerArgument
    _ = eventBase
    WiFiConnectionController.shared.handleWiFiEvent(eventID, eventData: eventData)
}

@_cdecl("swift_ip_event_handler")
func swiftIPEventHandler(
    _ eventHandlerArgument: UnsafeMutableRawPointer?,
    _ eventBase: UnsafePointer<CChar>?,
    _ eventID: Int32,
    _ eventData: UnsafeMutableRawPointer?
) {
    _ = eventHandlerArgument
    _ = eventBase
    _ = eventData
    WiFiConnectionController.shared.handleIPEvent(eventID)
}

@_cdecl("swift_wifi_connect_current_candidate")
func swiftWiFiConnectCurrentCandidate(_ argument: UnsafeMutableRawPointer?) {
    _ = argument
    WiFiConnectionController.shared.connectCurrentCandidate()
}
