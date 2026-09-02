struct LVColor {
    let red: UInt8
    let green: UInt8
    let blue: UInt8

    init(red: Double, green: Double, blue: Double) {
        self.red = UInt8(red * 255.0)
        self.green = UInt8(green * 255.0)
        self.blue = UInt8(blue * 255.0)
    }

    init(hex: UInt32) {
        self.red = UInt8((hex >> 16) & 0xFF)
        self.green = UInt8((hex >> 8) & 0xFF)
        self.blue = UInt8(hex & 0xFF)
    }

    var _hexValue: UInt32 {
        (UInt32(red) << 16) | (UInt32(green) << 8) | UInt32(blue)
    }
}

extension LVColor {
    static let black = LVColor(hex: 0x000000)
    static let white = LVColor(hex: 0xFFFFFF)
    static let pureRed = LVColor(hex: 0xFF0000)
    static let pureGreen = LVColor(hex: 0x00FF00)
    static let pureBlue = LVColor(hex: 0x0000FF)
    static let sky = LVColor(red: 22 / 255, green: 137 / 255, blue: 232 / 255)
    static let skyDark = LVColor(red: 8 / 255, green: 114 / 255, blue: 201 / 255)
    static let ink = LVColor(red: 23 / 255, green: 32 / 255, blue: 42 / 255)
    static let paper = LVColor(red: 244 / 255, green: 244 / 255, blue: 234 / 255)
    static let grass = LVColor(red: 130 / 255, green: 190 / 255, blue: 45 / 255)
    static let grassDark = LVColor(red: 85 / 255, green: 149 / 255, blue: 29 / 255)
    static let yellow = LVColor(red: 255 / 255, green: 217 / 255, blue: 40 / 255)
    static let orange = LVColor(red: 255 / 255, green: 178 / 255, blue: 62 / 255)
    static let red = LVColor(red: 228 / 255, green: 59 / 255, blue: 47 / 255)
    static let batteryCritical = LVColor(hex: 0xFF5A5A)
    static let batteryNormal = LVColor(hex: 0x39FF88)
    static let muted = LVColor(red: 217 / 255, green: 231 / 255, blue: 236 / 255)
}
