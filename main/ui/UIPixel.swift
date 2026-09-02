private let pixelSky = LVColor.sky._hexValue
private let pixelInk = LVColor.ink._hexValue
private let pixelPaper = LVColor.paper._hexValue
private let pixelGrass = LVColor.grass._hexValue
private let pixelGrassDark = LVColor.grassDark._hexValue
private let pixelOrange = LVColor.orange._hexValue

private func pixelBlock(
    _ parent: LVObject?,
    _ x: Int32,
    _ y: Int32,
    _ width: Int32,
    _ height: Int32,
    _ color: UInt32
) -> LVContainer? {
    let object = LVContainer(parent: parent)
    object?.removeScrollableFlag()
    object?.setPosition(x: x, y: y)
    object?.setSize(width: width, height: height)
    object?.setCornerRadius(0)
    object?.setBorderWidth(0)
    object?.setPadding(0)
    object?.setBackgroundColor(color)
    return object
}

private func addCloud(_ parent: LVObject?, _ x: Int32, _ y: Int32) {
    _ = pixelBlock(parent, x + 1, y + 7, 43, 10, pixelInk)
    _ = pixelBlock(parent, x + 5, y + 4, 35, 10, 0xFFFFFF)
    _ = pixelBlock(parent, x + 12, y, 10, 9, 0xFFFFFF)
    _ = pixelBlock(parent, x + 27, y + 1, 9, 8, 0xFFFFFF)
}

func uiPixelLabel(
    _ parent: LVObject?,
    _ text: UnsafePointer<CChar>?,
    _ font: LVFont,
    _ color: UInt32
) -> LVLabel? {
    let label = LVLabel(parent: parent, text: "")
    label?.setText(text)
    font.apply(to: label)
    label?.setTextColor(color)
    return label
}

func uiPixelScreenConfigure(_ screen: LVObject, title: UnsafePointer<CChar>?) {
    screen.removeScrollableFlag()
    screen.setBackgroundColor(pixelSky)
    screen.setBorderWidth(0)
    screen.setPadding(0)

    addCloud(screen, 188, 8)
    _ = pixelBlock(screen, 0, 286, 240, 34, pixelGrass)
    _ = pixelBlock(screen, 0, 286, 240, 4, 0xA7D93E)
    for x in stride(from: 0, to: 240, by: 30) {
        _ = pixelBlock(screen, Int32(x), 312, 18, 8, pixelGrassDark)
        _ = pixelBlock(screen, Int32(x + 18), 316, 12, 4, 0x75452E)
    }

    _ = pixelBlock(screen, 9, 12, 151, 33, pixelInk)
    let plate = pixelBlock(screen, 5, 8, 151, 33, pixelPaper)
    plate?.setBorderColor(pixelInk)
    plate?.setBorderWidth(3)
    let heading = uiPixelLabel(plate, title, LVFont.montserrat20, pixelInk)
    heading?.center()
}

func uiPixelPanelCreate(
    _ parent: LVObject?,
    _ x: Int32,
    _ y: Int32,
    _ width: Int32,
    _ height: Int32,
    _ color: UInt32
) -> LVContainer? {
    _ = pixelBlock(parent, x + 5, y + 6, width, height, pixelInk)
    let panel = pixelBlock(parent, x, y, width, height, color)
    panel?.setBorderColor(pixelInk)
    panel?.setBorderWidth(4)
    panel?.setPadding(7)
    return panel
}

func uiPixelMascotCreate(_ parent: LVObject?, _ x: Int32, _ y: Int32) -> LVContainer? {
    let mascot = LVContainer(parent: parent)
    mascot?.removeScrollableFlag()
    mascot?.setPosition(x: x, y: y)
    mascot?.setSize(width: 38, height: 48)
    mascot?.setBackgroundOpacity(UInt8(LV_OPA_TRANSP.rawValue))
    mascot?.setBorderWidth(0)
    mascot?.setPadding(0)

    _ = pixelBlock(mascot, 18, 0, 3, 6, pixelInk)
    _ = pixelBlock(mascot, 16, 0, 7, 3, pixelOrange)
    _ = pixelBlock(mascot, 3, 6, 32, 24, pixelInk)
    _ = pixelBlock(mascot, 0, 12, 5, 10, 0x7557D9)
    _ = pixelBlock(mascot, 33, 12, 5, 10, 0x7557D9)
    _ = pixelBlock(mascot, 7, 10, 24, 16, 0xB9F3FF)
    let leftEye = pixelBlock(mascot, 11, 14, 4, 6, 0x294B7A)
    let rightEye = pixelBlock(mascot, 23, 14, 4, 6, 0x294B7A)
    _ = pixelBlock(mascot, 16, 22, 7, 2, 0x7557D9)
    _ = pixelBlock(mascot, 10, 29, 18, 4, pixelOrange)
    _ = pixelBlock(mascot, 8, 33, 22, 11, 0x7557D9)
    _ = pixelBlock(mascot, 3, 35, 5, 7, 0xB9F3FF)
    _ = pixelBlock(mascot, 30, 35, 5, 7, 0xB9F3FF)
    _ = pixelBlock(mascot, 8, 44, 9, 4, pixelInk)
    _ = pixelBlock(mascot, 21, 44, 9, 4, pixelInk)
    LVMascotAnimation.startBlink(leftEye)
    LVMascotAnimation.startBlink(rightEye)
    return mascot
}

func uiPixelMascotJump(_ mascot: LVObject?) {
    guard let mascot else {
        return
    }
    LVMascotAnimation.jump(mascot)
}

func uiPixelSetSelected(_ panel: LVObject?, _ selected: Bool, _ enabled: Bool) {
    let color: UInt32 = enabled ? (selected ? LVColor.yellow._hexValue : pixelPaper) : 0x78909C
    panel?.setBackgroundColor(color)
    panel?.setBorderColor(selected ? 0xFFFFFF : pixelInk)
}
