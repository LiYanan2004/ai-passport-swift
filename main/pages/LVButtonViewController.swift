final class LVButtonViewController: LVViewController {
    private var millivoltsLabel: LVLabel?
    private var logLabels: [LVLabel?] = []
    private var timer: LVTimer?

    override func viewDidLoad() {
        super.viewDidLoad()
        guard let view else {
            return
        }
        uiPixelScreenConfigure(view, title: "BUTTON / ADC")

        let panel = uiPixelPanelCreate(view, 18, 58, 204, 184, LVColor.paper._hexValue)
        millivoltsLabel = uiPixelLabel(panel, "-- mV", LVFont.montserrat20, LVColor.skyDark._hexValue)
        millivoltsLabel?.align(.topCenter, verticalOffset: 8)

        logLabels = (0..<6).map { _ in LVLabel(parent: panel, text: "") }
        configureLogLabels()
        _ = uiPixelMascotCreate(view, 101, 238)
    }

    override func viewWillAppear() {
        super.viewWillAppear()
        timer = LVTimer(period: 100) { [self] in
            refresh()
        }
    }

    override func viewWillDisappear() {
        super.viewWillDisappear()
        if let timer {
            timer.invalidate()
        }
        timer = nil
    }

    override func viewDidDisappear() {
        super.viewDidDisappear()
        millivoltsLabel = nil
        logLabels = []
    }

    override func receiveButton(_ button: Int32, event: Int32) {
        shiftLog()
        setLatestLog(button, event)
    }

    fileprivate func refresh() {
        guard let millivoltsLabel else {
            return
        }
        let millivolts = bsp_button_read_mv()
        if millivolts < 0 {
            millivoltsLabel.text = "ADC read failed"
        } else {
            millivoltsLabel.value = (number: millivolts, unit: "mV")
        }
    }

    private func configureLogLabels() {
        let offsets: [Int32] = [54, 71, 88, 105, 122, 139]
        for (index, label) in logLabels.enumerated() {
            label?.setColor(.ink)
            label?.align(.topLeft, horizontalOffset: 9, verticalOffset: offsets[index])
            label?.text = index == 0 ? "press any key..." : ""
        }
    }

    private func shiftLog() {
        guard logLabels.count == 6 else {
            return
        }
        for index in 0..<5 {
            logLabels[index]?.text = logLabels[index + 1]?.text ?? ""
        }
    }

    private func setLatestLog(_ button: Int32, _ event: Int32) {
        guard let label = logLabels.last ?? nil else {
            return
        }
        let buttonName = button == Int32(BSP_BTN_UP.rawValue) ? "UP" :
            button == Int32(BSP_BTN_DOWN.rawValue) ? "DOWN" : "OK"
        let eventName = event == 0 ? "PRESS" : event == 1 ? "CLICK" :
            event == 2 ? "DOUBLE" : "LONG"
        label.text = "\(buttonName): \(eventName)"
    }
}
