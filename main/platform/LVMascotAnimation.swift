enum LVMascotAnimation {
    static func startBlink(_ eye: LVObject?) {
        guard let eye else { return }
        passport_lvgl_mascot_start_blink(eye.opaquePointer)
    }

    static func jump(_ mascot: LVObject?) {
        guard let mascot else { return }
        passport_lvgl_mascot_jump(mascot.opaquePointer)
    }
}
