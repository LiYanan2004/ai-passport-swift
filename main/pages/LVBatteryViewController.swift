final class LVBatteryViewController: LVViewController {

    private var socText: LVLabel?
    private var millivoltsText: LVLabel?
    private var timer: LVTimer?

    override func viewDidLoad() {
        super.viewDidLoad()
        guard let view else {
            return
        }
        uiPixelScreenConfigure(view, title: "BATTERY")

        let panel = uiPixelPanelCreate(view, 24, 67, 192, 157, LVColor.yellow._hexValue)

        socText = LVLabel(parent: panel, text: "-- %")
        socText?.font = LVFont.montserrat20
        socText?.textColor = LVColor.ink
        socText?.align(.topCenter, verticalOffset: 12)

        let implementationText = LVLabel(parent: panel, text: "MORE Embedded Swift")
        implementationText?.font = LVFont.montserrat14
        implementationText?.textColor = .red
        implementationText?.align(.topCenter, verticalOffset: 43)

        millivoltsText = LVLabel(parent: panel, text: "-- mV")
        millivoltsText?.font = LVFont.montserrat14
        millivoltsText?.textColor = LVColor.ink
        millivoltsText?.align(.topCenter, verticalOffset: 64)

        let battery = uiPixelPanelCreate(panel, 38, 96, 100, 38, LVColor.grass._hexValue)
        battery?.setBorderWidth(4)
        _ = uiPixelMascotCreate(view, 101, 238)
    }

    override func viewWillAppear() {
        super.viewWillAppear()
        updateLabels()
        timer = LVTimer(period: 1000) { [self] in
            updateLabels()
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
        socText = nil
        millivoltsText = nil
    }

    fileprivate func updateLabels() {
        guard let socText, let millivoltsText else {
            return
        }

        let soc = bsp_battery_soc()
        let millivolts = bsp_battery_mv()
        socText.value = (number: soc, unit: "%")
        millivoltsText.value = (number: millivolts, unit: "mV")
        socText.textColor = soc >= 0 && soc < 20 ? .batteryCritical : .batteryNormal
    }
}
