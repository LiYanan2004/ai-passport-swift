final class LVLowPowerViewController: LVViewController {
    private var lowPowerStatusLabel: LVLabel?
    private var lowPowerCards: (LVContainer?, LVContainer?) = (nil, nil)
    private var lowPowerMascot: LVContainer?
    private var lowPowerTimer: LVTimer?
    private var lowPowerSelectedIndex: Int32 = 0

    private func refreshLowPowerSelection() {
        uiPixelSetSelected(lowPowerCards.0, lowPowerSelectedIndex == 0, true)
        uiPixelSetSelected(lowPowerCards.1, lowPowerSelectedIndex == 1, true)
    }

    private func refreshLowPowerStatus() {
        guard let lowPowerStatusLabel else { return }
        switch swift_platform_power_state() {
        case SWIFT_POWER_LIGHT_PREPARING:
            lowPowerStatusLabel.text = "LIGHT SLEEP: 2 SEC\nTimer wakeup"
        case SWIFT_POWER_LIGHT_WOKE:
            lowPowerStatusLabel.text = "LIGHT WAKE: TIMER\nUP/DOWN: SELECT  OK: RUN"
        case SWIFT_POWER_DEEP_PREPARING:
            lowPowerStatusLabel.text = "DEEP SLEEP: 5 SEC\nApplication will restart"
        case SWIFT_POWER_FAILED:
            lowPowerStatusLabel.text = "Sleep failed:"
        default:
            break
        }
    }

    private func addLowPowerCard(
        _ panel: LVObject?,
        _ verticalOffset: Int32,
        _ title: UnsafePointer<CChar>?
    ) -> LVContainer? {
        let card = uiPixelPanelCreate(panel, 7, verticalOffset, 176, 42, LVColor.paper._hexValue)
        let label = uiPixelLabel(card, title, LVFont.montserrat14, LVColor.ink._hexValue)
        label?.center()
        return card
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        guard let view else { return }
        uiPixelScreenConfigure(view, title: "LOW POWER")
        let panel = uiPixelPanelCreate(view, 14, 54, 212, 190, LVColor.paper._hexValue)
        lowPowerStatusLabel = uiPixelLabel(
            panel,
            swift_platform_power_initial_status(),
            LVFont.montserrat14,
            LVColor.ink._hexValue
        )
        if let lowPowerStatusLabel {
            lowPowerStatusLabel.setWidth(184)
            lowPowerStatusLabel.setTextAlignmentCenter()
            lowPowerStatusLabel.align(.topCenter, verticalOffset: 1)
        }
        lowPowerCards = (
            addLowPowerCard(panel, 56, "LIGHT SLEEP  |  2 SEC"),
            addLowPowerCard(panel, 110, "DEEP SLEEP   |  5 SEC")
        )
        lowPowerSelectedIndex = 0
        refreshLowPowerSelection()
        lowPowerMascot = uiPixelMascotCreate(view, 101, 246)
    }

    override func viewWillAppear() {
        super.viewWillAppear()
        if !swift_platform_power_start() {
            lowPowerStatusLabel?.text = "Cannot create\nsleep worker"
        }
        lowPowerTimer = LVTimer(period: 100) { [self] in
            refreshLowPowerStatus()
        }
    }

    override func viewWillDisappear() {
        super.viewWillDisappear()
        lowPowerTimer?.invalidate()
        lowPowerTimer = nil
        swift_platform_power_stop()
    }

    override func viewDidDisappear() {
        super.viewDidDisappear()
        lowPowerStatusLabel = nil
        lowPowerCards = (nil, nil)
        lowPowerMascot = nil
    }

    override func receiveButton(_ button: Int32, event: Int32) {
        guard event == Int32(BSP_BTN_CLICK.rawValue) else {
            super.receiveButton(button, event: event)
            return
        }
        if button == Int32(BSP_BTN_UP.rawValue) || button == Int32(BSP_BTN_DOWN.rawValue) {
            lowPowerSelectedIndex = (lowPowerSelectedIndex + 1) % 2
            refreshLowPowerSelection()
            uiPixelMascotJump(lowPowerMascot)
        } else if button == Int32(BSP_BTN_OK.rawValue) {
            if lowPowerSelectedIndex == 0 {
                swift_platform_power_run_light_sleep()
            } else {
                swift_platform_power_run_deep_sleep()
            }
        } else {
            super.receiveButton(button, event: event)
        }
    }
}
