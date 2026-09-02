final class LVBluetoothViewController: LVViewController {
    private var statusLabel: LVLabel?
    private var timer: LVTimer?

    override func viewDidLoad() {
        super.viewDidLoad()
        guard let view else {
            return
        }
        uiPixelScreenConfigure(view, title: "BLUETOOTH LE")
        let panel = uiPixelPanelCreate(view, 22, 58, 196, 180, LVColor.paper._hexValue)
        statusLabel = uiPixelLabel(panel, "Starting NimBLE...", LVFont.montserrat14, LVColor.ink._hexValue)
        statusLabel?.setWidth(168)
        statusLabel?.setTextAlignmentCenter()
        statusLabel?.center()
        _ = uiPixelMascotCreate(view, 101, 244)
    }

    override func viewWillAppear() {
        super.viewWillAppear()
        timer = LVTimer(period: 100) { [self] in
            refresh()
        }
        swift_platform_ble_start()
    }

    override func viewWillDisappear() {
        super.viewWillDisappear()
        if let timer {
            timer.invalidate()
        }
        timer = nil
        swift_platform_ble_stop()
    }

    override func viewDidDisappear() {
        super.viewDidDisappear()
        statusLabel = nil
    }

    override func receiveButton(_ button: Int32, event: Int32) {
        guard button == Int32(BSP_BTN_OK.rawValue), event == Int32(BSP_BTN_CLICK.rawValue) else {
            super.receiveButton(button, event: event)
            return
        }
        swift_platform_ble_restart_advertising()
    }

    fileprivate func refresh() {
        guard let statusLabel else { return }

        switch swift_platform_ble_state() {
        case SWIFT_BLE_STARTING:
            statusLabel.text = "Starting NimBLE..."
        case SWIFT_BLE_ADVERTISING:
            statusLabel.text =
                "ADVERTISING\n\nName: FoloPassport\n\nUse a BLE scanner\non your phone.\n\nOK: RESTART ADV"
        case SWIFT_BLE_FAILED:
            statusLabel.value = (number: swift_platform_ble_error(), unit: "BLE error")
        default:
            break
        }
    }
}
