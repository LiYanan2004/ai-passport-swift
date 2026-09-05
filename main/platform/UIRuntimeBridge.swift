private struct PassportUIInput {
    let button: Int32
    let event: Int32
}

private var passportInputQueue: QueueHandle_t?

@_cdecl("swift_passport_enqueue_input")
private func swiftPassportEnqueueInput(
    _ button: bsp_btn_t,
    _ event: bsp_btn_ev_t,
    _ context: UnsafeMutableRawPointer?
) {
    _ = context
    guard let passportInputQueue else { return }
    var input = PassportUIInput(
        button: Int32(button.rawValue),
        event: Int32(event.rawValue)
    )
    withUnsafePointer(to: &input) { inputPointer in
        _ = passport_queue_send(passportInputQueue, inputPointer)
    }
}

@_cdecl("passport_ui_initialize_input")
func passportUIInitializeInput() -> Bool {
    guard passportInputQueue == nil else { return true }
    guard let queue = passport_queue_create(
        16,
        UBaseType_t(MemoryLayout<PassportUIInput>.size)
    ) else {
        return false
    }
    passportInputQueue = queue
    return bsp_button_init(swiftPassportEnqueueInput, nil) == ESP_OK
}

@_cdecl("passport_ui_poll_input")
func passportUIPollInput(
    _ button: UnsafeMutablePointer<Int32>?,
    _ event: UnsafeMutablePointer<Int32>?
) -> Bool {
    guard let passportInputQueue, let button, let event else { return false }
    var input = PassportUIInput(button: 0, event: 0)
    let received = withUnsafeMutablePointer(to: &input) { inputPointer in
        passport_queue_receive(passportInputQueue, inputPointer)
    }
    guard received == pdTRUE else { return false }
    button.pointee = input.button
    event.pointee = input.event
    return true
}

@_cdecl("passport_ui_report_runtime")
func passportUIReportRuntime() {
    let stackMinimumFree = uxTaskGetStackHighWaterMark(nil)
    let heapFree = esp_get_free_heap_size()
    let heapMinimum = esp_get_minimum_free_heap_size()
    let largestInternalBlock = heap_caps_get_largest_free_block(
        UInt32(MALLOC_CAP_INTERNAL | MALLOC_CAP_8BIT)
    )
    print(
        "UI alive: stack minimum free=\(stackMinimumFree) bytes, " +
            "heap free=\(heapFree) bytes, heap minimum=\(heapMinimum) bytes, " +
            "largest internal block=\(largestInternalBlock) bytes"
    )
}
