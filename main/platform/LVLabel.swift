final class LVLabel: LVObject {
    var font: LVFont? {
        didSet {
            guard let font else { return }
            font.apply(to: self)
        }
    }

    var text: String {
        get {
            guard let currentText = lv_label_get_text(opaquePointer) else { return "" }
            return String(cString: currentText)
        }
        set {
            newValue.withCString { lv_label_set_text(opaquePointer, $0) }
        }
    }

    var textColor: LVColor? {
        didSet {
            guard let textColor else { return }
            setTextColor(textColor._hexValue)
        }
    }

    var value: (number: Int32, unit: String)? {
        didSet {
            guard let value else { return }
            value.unit.withCString { passport_lvgl_label_set_value(opaquePointer, value.number, $0) }
        }
    }

    init?(parent: LVObject?, text: String = "") {
        super.init(lv_label_create(parent?.opaquePointer))
        self.text = text
    }

    func setColor(_ color: LVColor) {
        textColor = color
    }

    func setText(_ text: UnsafePointer<CChar>?) {
        lv_label_set_text(opaquePointer, text)
    }

    func setTextAlignmentCenter() {
        lv_obj_set_style_text_align(opaquePointer, LV_TEXT_ALIGN_CENTER, 0)
    }
}
