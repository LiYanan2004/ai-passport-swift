import EmbeddedSwiftUI
import LVGLRendererAdaptor

private var tiboResetRefreshTimer: LVGLTimer?

struct LiveTiboResetTrackerView: View {
    @State private var resetSnapshot = TiboResetMonitor.shared.snapshot()
    @State private var wifiConnectionState = WiFiConnectionController.shared.connectionState

    private static let refreshPeriod: UInt32 = 1_000

    var body: some View {
        VStack(spacing: 6) {
            HStack {
                Text("Tibo Tracker")
                Spacer()
                LiveConnectivityStatusView()
                    .frame(width: 64, height: 64)
            }

            Spacer()
            TiboResetStatusSummaryView(resetSnapshot: resetSnapshot)
            Spacer()
        }
        .padding(12)
        .onPhysicalButton(.ok) {
            _ = TiboResetMonitor.shared.start()
            TiboResetMonitor.shared.requestRefresh()
        }
        .onAppear(perform: startRefreshing)
        .onDisappear(perform: stopRefreshing)
    }

    private func startRefreshing() {
        guard tiboResetRefreshTimer == nil else { return }
        let resetSnapshotBinding = $resetSnapshot
        let wifiConnectionStateBinding = $wifiConnectionState
        tiboResetRefreshTimer = LVGLTimer(period: Self.refreshPeriod) {
            let nextResetSnapshot = TiboResetMonitor.shared.snapshot()
            if nextResetSnapshot != resetSnapshotBinding.wrappedValue {
                resetSnapshotBinding.wrappedValue = nextResetSnapshot
            }

            let nextWiFiConnectionState = WiFiConnectionController.shared.connectionState
            if nextWiFiConnectionState != wifiConnectionStateBinding.wrappedValue {
                wifiConnectionStateBinding.wrappedValue = nextWiFiConnectionState
            } else if nextWiFiConnectionState == .connected {
                // Let the first connected-state render release its temporary
                // display-list storage before reserving the HTTPS task stack.
                _ = TiboResetMonitor.shared.start()
            }
        }
    }

    private func stopRefreshing() {
        tiboResetRefreshTimer?.invalidate()
        tiboResetRefreshTimer = nil
    }
}

extension Color {
    static let secondary = Color(red: 154 / 255, green: 164 / 255, blue: 185 / 255)
}

private struct TiboResetStatusSummaryView: View {
    let resetSnapshot: CodexResetQuery

    var body: some View {
        VStack(spacing: 4) {
            Image(avatarAssetName)
                .clipShape(Circle())

            Text(statusText)
                .font(.system(size: 18))
                .foregroundColor(statusColor)

            if let nextResetText {
                Text(nextResetText)
                    .font(.system(size: 12))
                    .foregroundColor(Color.secondary)
            } else if let lastResetText = resetSnapshot.lastResetText {
                Text("LAST RESET: " + lastResetText)
                    .font(.system(size: 12))
                    .foregroundColor(Color.secondary)
            }
        }
    }

    private var statusText: String {
        switch resetSnapshot.status {
        case .waitingForData:
            return "CHECKING TIBO"
        case .confirmed:
            return "RESET CONFIRMED"
        case .announced:
            return resetSnapshot.scheduledReset != nil ? "RESET ANNOUNCED" : "RESET WATCH"
        case .normal:
            return "NO RESET YET"
        case .unavailable:
            return "DATA UNAVAILABLE"
        }
    }

    private var nextResetText: String? {
        if let scheduledForText = resetSnapshot.scheduledReset?.scheduledForText {
            return "NEXT  " + scheduledForText
        }
        if let activeWatch = resetSnapshot.activeWatch {
            if let resetChancePercent = activeWatch.resetChancePercent,
                let forecastText = activeWatch.forecastText
            {
                return "NEXT  \(resetChancePercent)%  " + forecastText
            }
            if let forecastText = activeWatch.forecastText {
                return "NEXT  " + forecastText
            }
        }
        return nil
    }

    private var avatarAssetName: StaticString {
        switch resetSnapshot.status {
        case .confirmed:
            return "tibo-reset-confirmed"
        case .announced:
            return "tibo-reset-announced"
        case .waitingForData, .normal, .unavailable:
            return "tibo-reset-idle"
        }
    }

    private var statusColor: Color {
        switch resetSnapshot.status {
        case .confirmed:
            return Color.green
        case .announced:
            return Color(red: 255 / 255, green: 116 / 255, blue: 90 / 255)
        case .normal:
            return Color(red: 78 / 255, green: 175 / 255, blue: 255 / 255)
        case .waitingForData:
            return Color.secondary
        case .unavailable:
            return Color.red
        }
    }
}
