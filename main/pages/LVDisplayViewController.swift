final class LVDisplayViewController: LVViewController {
    private var displaySwatch: LVContainer?
    private var displayInfo: LVLabel?
    private var displayMascot: LVContainer?
    private var displayColorIndex: Int32 = 0
    private var displayBacklightIndex: Int32 = 0

    private func refreshDisplayPage() {
        guard let displaySwatch, let displayInfo else {
            return
        }

        switch displayColorIndex {
        case 0:
            displaySwatch.setBackgroundColor(LVColor.pureRed._hexValue)
            displayInfo.setColor(.black)
            switch displayBacklightIndex {
            case 0: displayInfo.text = "RED\n\nBACKLIGHT 100%\n\nOK: NEXT COLOR\nUP/DOWN: LIGHT"
            case 1: displayInfo.text = "RED\n\nBACKLIGHT 50%\n\nOK: NEXT COLOR\nUP/DOWN: LIGHT"
            default: displayInfo.text = "RED\n\nBACKLIGHT 10%\n\nOK: NEXT COLOR\nUP/DOWN: LIGHT"
            }
        case 1:
            displaySwatch.setBackgroundColor(LVColor.pureGreen._hexValue)
            displayInfo.setColor(.black)
            switch displayBacklightIndex {
            case 0: displayInfo.text = "GREEN\n\nBACKLIGHT 100%\n\nOK: NEXT COLOR\nUP/DOWN: LIGHT"
            case 1: displayInfo.text = "GREEN\n\nBACKLIGHT 50%\n\nOK: NEXT COLOR\nUP/DOWN: LIGHT"
            default: displayInfo.text = "GREEN\n\nBACKLIGHT 10%\n\nOK: NEXT COLOR\nUP/DOWN: LIGHT"
            }
        case 2:
            displaySwatch.setBackgroundColor(LVColor.pureBlue._hexValue)
            displayInfo.setColor(.white)
            switch displayBacklightIndex {
            case 0: displayInfo.text = "BLUE\n\nBACKLIGHT 100%\n\nOK: NEXT COLOR\nUP/DOWN: LIGHT"
            case 1: displayInfo.text = "BLUE\n\nBACKLIGHT 50%\n\nOK: NEXT COLOR\nUP/DOWN: LIGHT"
            default: displayInfo.text = "BLUE\n\nBACKLIGHT 10%\n\nOK: NEXT COLOR\nUP/DOWN: LIGHT"
            }
        case 3:
            displaySwatch.setBackgroundColor(LVColor.white._hexValue)
            displayInfo.setColor(.black)
            switch displayBacklightIndex {
            case 0: displayInfo.text = "WHITE\n\nBACKLIGHT 100%\n\nOK: NEXT COLOR\nUP/DOWN: LIGHT"
            case 1: displayInfo.text = "WHITE\n\nBACKLIGHT 50%\n\nOK: NEXT COLOR\nUP/DOWN: LIGHT"
            default: displayInfo.text = "WHITE\n\nBACKLIGHT 10%\n\nOK: NEXT COLOR\nUP/DOWN: LIGHT"
            }
        default:
            displaySwatch.setBackgroundColor(LVColor.black._hexValue)
            displayInfo.setColor(.white)
            switch displayBacklightIndex {
            case 0: displayInfo.text = "BLACK\n\nBACKLIGHT 100%\n\nOK: NEXT COLOR\nUP/DOWN: LIGHT"
            case 1: displayInfo.text = "BLACK\n\nBACKLIGHT 50%\n\nOK: NEXT COLOR\nUP/DOWN: LIGHT"
            default: displayInfo.text = "BLACK\n\nBACKLIGHT 10%\n\nOK: NEXT COLOR\nUP/DOWN: LIGHT"
            }
        }
    }

    private func applyDisplayBacklight() {
        switch displayBacklightIndex {
        case 0: bsp_display_backlight(100)
        case 1: bsp_display_backlight(50)
        default: bsp_display_backlight(10)
        }
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        guard let view else { return }
        displayColorIndex = 0
        displayBacklightIndex = 0

        uiPixelScreenConfigure(view, title: "DISPLAY")
        displaySwatch = uiPixelPanelCreate(view, 18, 58, 204, 188, LVColor.pureRed._hexValue)
        displayInfo = uiPixelLabel(displaySwatch, "", LVFont.montserrat14, LVColor.ink._hexValue)
        if let displayInfo {
            displayInfo.setTextAlignmentCenter()
            displayInfo.center()
        }
        displayMascot = uiPixelMascotCreate(view, 101, 238)
        refreshDisplayPage()
    }

    override func viewWillAppear() {
        super.viewWillAppear()
        applyDisplayBacklight()
    }

    override func viewWillDisappear() {
        super.viewWillDisappear()
        bsp_display_backlight(100)
    }

    override func viewDidDisappear() {
        super.viewDidDisappear()
        displaySwatch = nil
        displayInfo = nil
        displayMascot = nil
    }

    override func receiveButton(_ button: Int32, event: Int32) {
        guard event == Int32(BSP_BTN_CLICK.rawValue) else {
            super.receiveButton(button, event: event)
            return
        }
        if button == Int32(BSP_BTN_OK.rawValue) {
            displayColorIndex = (displayColorIndex + 1) % 5
            uiPixelMascotJump(displayMascot)
        } else {
            guard button == Int32(BSP_BTN_UP.rawValue) || button == Int32(BSP_BTN_DOWN.rawValue) else {
                super.receiveButton(button, event: event)
                return
            }
            displayBacklightIndex = button == Int32(BSP_BTN_UP.rawValue)
            ? (displayBacklightIndex + 2) % 3
            : (displayBacklightIndex + 1) % 3
            applyDisplayBacklight()
        }
        refreshDisplayPage()
    }
}
