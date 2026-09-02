final class LVWiFiViewController: LVViewController {
    private var statusLabel: LVLabel?
    private var resultsLabel: LVLabel?
    private var timer: LVTimer?

    override func viewDidLoad() {
        super.viewDidLoad()
        guard let view else {
            return
        }
        uiPixelScreenConfigure(view, title: "WI-FI SCAN")

        let panel = uiPixelPanelCreate(view, 12, 54, 216, 190, LVColor.paper._hexValue)
        statusLabel = uiPixelLabel(
            panel,
            "Starting Wi-Fi...",
            LVFont.montserrat14,
            LVColor.skyDark._hexValue
        )
        statusLabel?.setWidth(190)
        statusLabel?.align(.topLeft, horizontalOffset: 2, verticalOffset: 2)

        resultsLabel = uiPixelLabel(
            panel,
            "RSSI  SSID  CHANNEL",
            LVFont.montserrat14,
            LVColor.ink._hexValue
        )
        resultsLabel?.setWidth(190)
        resultsLabel?.align(.topLeft, horizontalOffset: 2, verticalOffset: 35)
        _ = uiPixelMascotCreate(view, 101, 246)
    }

    override func viewWillAppear() {
        super.viewWillAppear()
        timer = LVTimer(period: 100) { [self] in
            refresh()
        }
        swift_platform_wifi_start()
    }

    override func viewWillDisappear() {
        super.viewWillDisappear()
        if let timer {
            timer.invalidate()
        }
        timer = nil
        swift_platform_wifi_stop()
    }

    override func viewDidDisappear() {
        super.viewDidDisappear()
        statusLabel = nil
        resultsLabel = nil
    }

    override func receiveButton(_ button: Int32, event: Int32) {
        guard button == Int32(BSP_BTN_OK.rawValue), event == Int32(BSP_BTN_CLICK.rawValue) else {
            super.receiveButton(button, event: event)
            return
        }

        resultsLabel?.text = "RSSI  SSID  CHANNEL"
        swift_platform_wifi_rescan()
    }

    fileprivate func refresh() {
        guard let statusLabel else {
            return
        }

        switch swift_platform_wifi_state() {
        case SWIFT_WIFI_STARTING:
            statusLabel.text = "Starting Wi-Fi..."
        case SWIFT_WIFI_SCANNING:
            statusLabel.text = "Scanning 2.4 GHz..."
        case SWIFT_WIFI_FAILED:
            statusLabel.text = "Wi-Fi failed:"
            if let error = swift_platform_wifi_error() {
                resultsLabel?.text = String(cString: error)
            }
        default:
            guard let results = swift_platform_wifi_results(), results.pointee != 0 else {
                return
            }
            statusLabel.text = "Scan complete  |  OK: RESCAN"
            resultsLabel?.text = String(cString: results)
        }
    }
}
