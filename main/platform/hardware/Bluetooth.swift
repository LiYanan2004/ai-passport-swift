enum BluetoothEvent {
    case starting
    case advertising
    case connected
    case disconnected
    case stopped
    case failed(Int32)
}

final class Bluetooth {
    static let shared = Bluetooth()

    private static let hostStopTimeoutMicroseconds: Int64 = 5_000_000
    // BLE_GAP_CONN_MODE_UND keeps the peripheral visible and lets the Mac
    // central connect to the Agent Monitor GATT service.
    private static let undirectedConnectableAdvertisingMode = UInt8(BLE_GAP_CONN_MODE_UND)
    private static let generalDiscoverableMode = UInt8(BLE_GAP_DISC_MODE_GEN)

    var isEnabled = false {
        didSet {
            guard isEnabled != oldValue else { return }
            if isEnabled {
                start()
            } else {
                stop()
            }
        }
    }

    var eventHandler: ((BluetoothEvent) -> Void)?

    var isAdvertising: Bool {
        isInitialized && ble_gap_adv_active() != 0
    }

    private(set) var isConnected = false
    private(set) var lastError: Int32?

    var deviceName: String {
        AgentMonitorBLETransport.shared.deviceName
    }

    var hasBoundMac: Bool {
        AgentMonitorBLETransport.shared.hasBoundMac
    }

    var isPairingOpen: Bool {
        AgentMonitorBLETransport.shared.isPairingOpen
    }

    var pairingCode: String? {
        AgentMonitorBLETransport.shared.pairingCode
    }

    private var isInitialized = false
    private var shouldAdvertise = false
    private var isHostStopped = false

    private init() {}

    @discardableResult
    func restartAdvertising() -> Int32 {
        guard isInitialized, !isConnected else { return ESP_ERR_INVALID_STATE }
        _ = ble_gap_adv_stop()
        return advertise()
    }

    @discardableResult
    func beginPairing() -> Int32 {
        guard isInitialized, !isConnected else {
            return ESP_ERR_INVALID_STATE
        }

        let pairingResult = AgentMonitorBLETransport.shared.beginPairing()
        guard pairingResult == 0 else {
            return pairingResult
        }
        return restartAdvertising()
    }

    func cancelPairing() {
        AgentMonitorBLETransport.shared.cancelPairing()
        guard isInitialized, !isConnected else {
            return
        }
        _ = ble_gap_adv_stop()
    }

    fileprivate func didStopHost() {
        isHostStopped = true
    }

    fileprivate func didReset(reason: Int32) {
        lastError = reason
        eventHandler?(.failed(reason))
    }

    fileprivate func didSynchronize() {
        isConnected = false
        guard shouldAdvertise else { return }
        _ = advertise()
    }

    fileprivate func didReceiveGapEvent(_ event: UnsafeMutablePointer<ble_gap_event>?) -> Int32 {
        let callbackResult = AgentMonitorBLETransport.shared.gapCallbackResult(event)
        switch AgentMonitorBLETransport.shared.handleGapEvent(event) {
        case .securing:
            break
        case .disconnected:
            isConnected = false
            eventHandler?(.disconnected)
            if shouldAdvertise {
                _ = advertise()
            }
        case .resumeAdvertising:
            if shouldAdvertise, !isConnected {
                _ = advertise()
            }
        case .secureOwnerConnected:
            isConnected = true
            lastError = nil
            eventHandler?(.connected)
        case .securityFailed:
            isConnected = false
            eventHandler?(.disconnected)
        case .ignore:
            break
        }
        return callbackResult
    }

    private func start() {
        guard !isInitialized else { return }

        lastError = nil
        isConnected = false
        eventHandler?(.starting)
        let nvsError = nvs_flash_init()
        guard nvsError == ESP_OK else {
            lastError = nvsError
            eventHandler?(.failed(nvsError))
            return
        }

        let initializationError = nimble_port_init()
        guard initializationError == ESP_OK else {
            lastError = initializationError
            eventHandler?(.failed(initializationError))
            return
        }

        ble_svc_gap_init()
        ble_svc_gatt_init()
        let securityError = AgentMonitorBLETransport.shared.configureSecurity()
        guard securityError == 0 else {
            _ = nimble_port_deinit()
            lastError = Int32(securityError)
            eventHandler?(.failed(Int32(securityError)))
            return
        }
        let serviceError = AgentMonitorBLETransport.shared.registerService()
        guard serviceError == 0 else {
            _ = nimble_port_deinit()
            lastError = Int32(serviceError)
            eventHandler?(.failed(Int32(serviceError)))
            return
        }
        isInitialized = true
        isHostStopped = false
        shouldAdvertise = true
        ble_hs_cfg.reset_cb = swiftBluetoothReset
        ble_hs_cfg.sync_cb = swiftBluetoothSynchronized
        nimble_port_freertos_init(swiftBluetoothHostTask)
    }

    private func stop() {
        shouldAdvertise = false
        isConnected = false
        guard isInitialized else {
            eventHandler?(.stopped)
            return
        }

        _ = ble_gap_adv_stop()
        let stopResult = nimble_port_stop()
        guard stopResult == 0 else {
            lastError = Int32(stopResult)
            eventHandler?(.failed(Int32(stopResult)))
            return
        }

        let deadline = esp_timer_get_time() + Bluetooth.hostStopTimeoutMicroseconds
        while !isHostStopped, esp_timer_get_time() < deadline {
            vTaskDelay(1)
        }
        guard isHostStopped else {
            lastError = ESP_ERR_TIMEOUT
            eventHandler?(.failed(ESP_ERR_TIMEOUT))
            return
        }

        _ = nimble_port_deinit()
        isInitialized = false
        eventHandler?(.stopped)
    }

    private func advertise() -> Int32 {
        guard AgentMonitorBLETransport.shared.shouldAdvertise else {
            return ESP_OK
        }

        var addressType: UInt8 = 0
        var result = ble_hs_util_ensure_addr(0)
        if result == 0 {
            result = ble_hs_id_infer_auto(0, &addressType)
        }
        guard result == 0 else {
            eventHandler?(.failed(Int32(result)))
            return Int32(result)
        }

        result = AgentMonitorBLETransport.shared.configureAdvertisingFields()
        guard result == 0 else {
            lastError = Int32(result)
            eventHandler?(.failed(Int32(result)))
            return Int32(result)
        }

        result = AgentMonitorBLETransport.shared.prepareAdvertising()
        guard result == 0 else {
            lastError = Int32(result)
            eventHandler?(.failed(Int32(result)))
            return Int32(result)
        }

        var parameters = ble_gap_adv_params()
        parameters.conn_mode = Bluetooth.undirectedConnectableAdvertisingMode
        parameters.disc_mode = Bluetooth.generalDiscoverableMode
        parameters.filter_policy = AgentMonitorBLETransport.shared.advertisingFilterPolicy
        result = ble_gap_adv_start(
            addressType,
            nil,
            Int32.max,
            &parameters,
            swiftBluetoothGapEvent,
            nil
        )
        if result == 0 {
            eventHandler?(.advertising)
        } else {
            lastError = Int32(result)
            eventHandler?(.failed(Int32(result)))
        }
        return Int32(result)
    }
}

@_cdecl("swift_bluetooth_host_task")
private func swiftBluetoothHostTask(_ argument: UnsafeMutableRawPointer?) {
    _ = argument
    nimble_port_run()
    Bluetooth.shared.didStopHost()
    nimble_port_freertos_deinit()
}

@_cdecl("swift_bluetooth_reset")
private func swiftBluetoothReset(_ reason: Int32) {
    Bluetooth.shared.didReset(reason: reason)
}

@_cdecl("swift_bluetooth_synchronized")
private func swiftBluetoothSynchronized() {
    Bluetooth.shared.didSynchronize()
}

@_cdecl("swift_bluetooth_gap_event")
private func swiftBluetoothGapEvent(
    _ event: UnsafeMutablePointer<ble_gap_event>?,
    _ argument: UnsafeMutableRawPointer?
) -> Int32 {
    _ = argument
    return Bluetooth.shared.didReceiveGapEvent(event)
}
