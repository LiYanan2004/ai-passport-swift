final class DeviceConnectivityMonitor {
    static let shared = DeviceConnectivityMonitor()

    private static let taskName = StaticString("connectivity")
    private static let taskStackDepth: UInt32 = 3_072
    private static let taskPriority: UInt32 = 3

    private var cachedSnapshot = DeviceConnectivitySnapshot.unavailable

    #if ESP_PLATFORM
        private var workerTask: TaskHandle_t?
    #endif

    private init() {}

    @discardableResult
    func start() -> Bool {
        #if ESP_PLATFORM
            guard workerTask == nil else { return true }

            var createdTask: TaskHandle_t?
            let result = xTaskCreate(
                swiftConnectivityMonitorTask,
                UnsafePointer<CChar>(OpaquePointer(Self.taskName.utf8Start)),
                Self.taskStackDepth,
                nil,
                Self.taskPriority,
                &createdTask
            )
            guard result == pdPASS else { return false }
            workerTask = createdTask
        #endif
        return true
    }

    func snapshot() -> DeviceConnectivitySnapshot {
        #if ESP_PLATFORM
            vPortEnterCritical()
            let snapshot = cachedSnapshot
            vPortExitCritical()
            return snapshot
        #else
            return cachedSnapshot
        #endif
    }

    #if ESP_PLATFORM
        fileprivate func runWorker() {
            updateSnapshot()

            if !Battery.shared.initialize() {
                print("Battery data unavailable")
            }

            while true {
                updateSnapshot()
                vTaskDelay(TickType_t(CONFIG_FREERTOS_HZ))
            }
        }

        private func updateSnapshot() {
            let nextSnapshot = Self.readDeviceSnapshot()
            vPortEnterCritical()
            cachedSnapshot = nextSnapshot
            vPortExitCritical()
        }

        private static func readDeviceSnapshot() -> DeviceConnectivitySnapshot {
            let batteryPercent = Battery.shared.stateOfCharge
            return DeviceConnectivitySnapshot(
                batteryLevel: batteryPercent >= 0 ? Double(batteryPercent) / 100 : 0,
                bluetoothStatus: readBluetoothStatus(),
                wifiSignalStrength: readWiFiSignalStrength()
            )
        }

        private static func readBluetoothStatus() -> BluetoothStatus {
            guard esp_bt_controller_get_status() == ESP_BT_CONTROLLER_STATUS_ENABLED else {
                return .poweredOff
            }
            guard ble_hs_synced() != 0 else { return .poweredOn }

            var isConnected = false
            withUnsafeMutablePointer(to: &isConnected) { isConnectedPointer in
                ble_gap_conn_foreach_handle(
                    { _, context in
                        context?.assumingMemoryBound(to: Bool.self).pointee = true
                        return 0
                    },
                    isConnectedPointer
                )
            }
            return isConnected ? .connected : .poweredOn
        }

        private static func readWiFiSignalStrength() -> Int {
            guard WiFiConnectionController.shared.connectionState == .connected else {
                return 0
            }
            guard let accessPoint = WiFi.shared.connectedAccessPoint else {
                return 0
            }
            return DeviceConnectivitySnapshot.wifiSignalStrength(
                rssi: accessPoint.signalStrength
            )
        }
    #endif
}

enum BluetoothStatus: Equatable, Sendable {
    case poweredOff
    case poweredOn
    case connected
}

struct DeviceConnectivitySnapshot: Equatable {
    let batteryLevel: Double
    let bluetoothStatus: BluetoothStatus
    let wifiSignalStrength: Int

    static let unavailable = DeviceConnectivitySnapshot(
        batteryLevel: 0,
        bluetoothStatus: .poweredOff,
        wifiSignalStrength: 0
    )

    static func wifiSignalStrength(rssi: Int32) -> Int {
        switch rssi {
        case -55...Int32.max:
            return 4
        case -67 ... -56:
            return 3
        case -75 ... -68:
            return 2
        case -85 ... -76:
            return 1
        default:
            return 0
        }
    }
}

#if ESP_PLATFORM
    @_cdecl("swift_connectivity_monitor_task")
    private func swiftConnectivityMonitorTask(_ argument: UnsafeMutableRawPointer?) {
        _ = argument
        DeviceConnectivityMonitor.shared.runWorker()
    }
#endif
