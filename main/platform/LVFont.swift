struct LVFont {
    private let descriptor: UnsafePointer<lv_font_t>

    private init(_ pointer: UnsafePointer<lv_font_t>) {
        self.descriptor = pointer
    }

    private static var montserrat14Descriptor = lv_font_montserrat_14
    private static var montserrat20Descriptor = lv_font_montserrat_20

    func apply(to object: LVObject?) {
        object?.setFont(descriptor)
    }
}

extension LVFont {
    static let montserrat14 = LVFont(UnsafePointer(&montserrat14Descriptor))
    static let montserrat20 = LVFont(UnsafePointer(&montserrat20Descriptor))
}
