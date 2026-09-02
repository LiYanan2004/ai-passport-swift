final class LVAudioViewController: LVViewController {
    private var statusLabel: LVLabel?
    private var mascot: LVContainer?
    private var timer: LVTimer?

    override func viewDidLoad() {
        super.viewDidLoad()
        guard let view else { return }
        uiPixelScreenConfigure(view, title: "AUDIO")

        let panel = uiPixelPanelCreate(view, 18, 62, 204, 168, LVColor.paper._hexValue)
        let record = uiPixelPanelCreate(panel, 58, 12, 72, 72, LVColor.ink._hexValue)
        let disc = LVContainer(parent: record)
        disc?.setSize(width: 36, height: 36)
        disc?.setCornerRadius(LV_RADIUS_CIRCLE)
        disc?.setBackgroundColor(LVColor.red._hexValue)
        disc?.setBorderWidth(0)
        disc?.center()

        statusLabel = uiPixelLabel(panel, "OK: 1kHz TONE\nUP: RECORD + PLAY", LVFont.montserrat14, LVColor.ink._hexValue)
        statusLabel?.setTextAlignmentCenter()
        statusLabel?.setWidth(176)
        statusLabel?.align(.bottomCenter, verticalOffset: -9)
        mascot = uiPixelMascotCreate(view, 101, 238)
    }

    override func viewWillAppear() {
        super.viewWillAppear()
        swift_platform_audio_start()
        timer = LVTimer(period: 100) { [self] in
            refreshStatus()
        }
        refreshStatus()
    }

    override func viewWillDisappear() {
        super.viewWillDisappear()
        timer?.invalidate()
        timer = nil
        swift_platform_audio_stop()
    }

    override func viewDidDisappear() {
        super.viewDidDisappear()
        statusLabel = nil
        mascot = nil
    }

    override func receiveButton(_ button: Int32, event: Int32) {
        guard event == Int32(BSP_BTN_CLICK.rawValue) else {
            super.receiveButton(button, event: event)
            return
        }
        if button == Int32(BSP_BTN_OK.rawValue) {
            swift_platform_audio_request_tone()
            uiPixelMascotJump(mascot)
        } else if button == Int32(BSP_BTN_UP.rawValue) {
            swift_platform_audio_request_recording()
            uiPixelMascotJump(mascot)
        } else {
            super.receiveButton(button, event: event)
        }
    }

    fileprivate func refreshStatus() {
        guard let statusLabel else { return }
        switch swift_platform_audio_state() {
        case SWIFT_AUDIO_PLAYING_TONE: statusLabel.text = "playing 1kHz..."
        case SWIFT_AUDIO_RECORDING: statusLabel.text = "recording 3s...\nspeak now"
        case SWIFT_AUDIO_PLAYING_RECORDING: statusLabel.text = "playing back..."
        case SWIFT_AUDIO_COMPLETE: statusLabel.text = "done. OK: tone\nUP: record"
        case SWIFT_AUDIO_FAILED: statusLabel.text = "audio operation failed"
        default: break
        }
    }
}
