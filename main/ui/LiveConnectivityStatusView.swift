import EmbeddedSwiftUI
import LVGLRendererAdaptor

private var connectivityStatusRefreshTimer: LVGLTimer?

struct LiveConnectivityStatusView: View {
    @State private var deviceSnapshot = DeviceConnectivityMonitor.shared.snapshot()
    @State private var wifiConnectionState = WiFiConnectionController.shared.connectionState

    private static let statusUpdatePeriod: UInt32 = 1_000

    var body: some View {
        ConnectivityStatusView(
            batteryLevel: deviceSnapshot.batteryLevel,
            bluetoothStatus: deviceSnapshot.bluetoothStatus,
            wifiSignalStrength: deviceSnapshot.wifiSignalStrength,
            wifiConnectionState: wifiConnectionState
        )
        .onAppear {
            startRefreshing()
        }
        .onDisappear {
            stopRefreshing()
        }
    }

    private func startRefreshing() {
        guard connectivityStatusRefreshTimer == nil else { return }
        let deviceSnapshotBinding = $deviceSnapshot
        let wifiConnectionStateBinding = $wifiConnectionState
        connectivityStatusRefreshTimer = LVGLTimer(period: Self.statusUpdatePeriod) {
            let nextSnapshot = DeviceConnectivityMonitor.shared.snapshot()
            if nextSnapshot != deviceSnapshotBinding.wrappedValue {
                deviceSnapshotBinding.wrappedValue = nextSnapshot
            }
            let nextWiFiConnectionState = WiFiConnectionController.shared.connectionState
            if nextWiFiConnectionState != wifiConnectionStateBinding.wrappedValue {
                wifiConnectionStateBinding.wrappedValue = nextWiFiConnectionState
            }
        }
    }

    private func stopRefreshing() {
        connectivityStatusRefreshTimer?.invalidate()
        connectivityStatusRefreshTimer = nil
    }
}

extension LiveConnectivityStatusView {
    struct ConnectivityStatusView: View {
        let batteryLevel: Double
        let bluetoothStatus: BluetoothStatus
        let wifiSignalStrength: Int
        let wifiConnectionState: WiFiConnectionState

        private static let wifiActiveOpacity = 1.0
        private static let wifiInactiveOpacity = 0.45

        init(
            batteryLevel: Double,
            bluetoothStatus: BluetoothStatus,
            wifiSignalStrength: Int,
            wifiConnectionState: WiFiConnectionState = .disconnected
        ) {
            self.batteryLevel =
                batteryLevel.isFinite
                ? min(max(batteryLevel, 0), 1)
                : 0
            self.bluetoothStatus = bluetoothStatus
            self.wifiSignalStrength = min(max(wifiSignalStrength, 0), 4)
            self.wifiConnectionState = wifiConnectionState
        }

        var body: some View {
            ZStack {
                BatteryLevelArc(level: 1)
                    .fill(.white)
                    .opacity(0.5)

                BatteryLevelArc(level: batteryLevel)
                    .fill(.white)

                BluetoothSymbol()
                    .fill(bluetoothColor)
                    .opacity(bluetoothStatus == .poweredOff ? 0.5 : 1)

                ForEach(0..<4) { index in
                    WiFiDot(
                        index: index,
                        isConnecting: wifiConnectionState == .connecting,
                        opacity: wifiDotOpacity(for: index)
                    )
                }
            }
        }

        private func wifiDotOpacity(for index: Int) -> Double {
            let isActive = wifiConnectionState == .connected && index < wifiSignalStrength
            return isActive ? Self.wifiActiveOpacity : Self.wifiInactiveOpacity
        }

        private var bluetoothColor: Color {
            switch bluetoothStatus {
            case .connected:
                return Color(red: 0, green: 0.48, blue: 1)
            case .poweredOff, .poweredOn:
                return .white
            }
        }

        struct WiFiDot: View {
            @State private var isAnimationActive = false

            private static let connectingAnimationDelay = 0.13
            private static let connectingAnimationDuration = 0.26

            let index: Int
            let isConnecting: Bool
            let opacity: Double

            var body: some View {
                ConnectivityWiFiDot(index: index)
                    .fill(.white)
                    .opacity(isConnecting && isAnimationActive ? 1 : opacity)
                    .animation(
                        isConnecting
                            ? .easeInOut(duration: Self.connectingAnimationDuration)
                                .repeatForever(autoreverses: true)
                                .delay(Double(index) * Self.connectingAnimationDelay)
                            : nil,
                        value: isConnecting && isAnimationActive
                    )
                    .onAppear {
                        guard !isAnimationActive else { return }
                        isAnimationActive = true
                    }
            }
        }
    }

    struct ConnectivityWiFiDot: Shape {
        let index: Int

        func path(in rect: ShapeRect) -> Path {
            let diameter = min(rect.width, rect.height) * 11 / 180
            let horizontalOffset = (Float(index) - 1.5) * rect.width * 26 / 180
            let verticalOffset = rect.height * (index == 0 || index == 3 ? 69 : 78) / 180
            return Path { path in
                path.addEllipse(
                    in: ShapeRect(
                        x: rect.x + rect.width / 2 + horizontalOffset - diameter / 2,
                        y: rect.y + rect.height / 2 + verticalOffset - diameter / 2,
                        width: diameter,
                        height: diameter
                    ))
            }
        }
    }
}
