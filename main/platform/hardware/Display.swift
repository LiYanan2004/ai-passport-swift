final class Display {
    static let shared = Display()

    var brightness: Int = 100 {
        didSet {
            let normalizedBrightness = min(max(brightness, 0), 100)
            if brightness != normalizedBrightness {
                brightness = normalizedBrightness
            }
            bsp_display_backlight(UInt8(brightness))
        }
    }

    private init() {}

    func initialize() -> Bool {
        guard bsp_display_init() == ESP_OK, bsp_lvgl_init() != nil else {
            return false
        }
        bsp_display_backlight(UInt8(brightness))
        return true
    }
}
