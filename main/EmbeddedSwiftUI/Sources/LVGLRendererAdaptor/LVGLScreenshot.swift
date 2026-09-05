/// Captures RGB565 pixels in system-heap storage outside LVGL's bounded pool.
public enum LVGLScreenshot {
    /// The callback runs after unlocking. Pixel storage is valid only for the call.
    @discardableResult
    public static func capture(
        handler: passport_ui_screenshot_handler_t,
        context: UnsafeMutableRawPointer? = nil
    ) -> Bool {
        guard bsp_lvgl_lock(1000) else { return false }
        var isLocked = true
        defer { if isLocked { bsp_lvgl_unlock() } }
        guard let screen = lv_screen_active() else { return false }
        lv_obj_update_layout(screen)
        let width = lv_obj_get_width(screen)
        let height = lv_obj_get_height(screen)
        guard width > 0, height > 0 else { return false }
        let stride = lv_draw_buf_width_to_stride(UInt32(width), LV_COLOR_FORMAT_RGB565)
        let storageSize = UInt64(stride) * UInt64(height) + UInt64(LV_DRAW_BUF_ALIGN)
        guard storageSize <= UInt64(UInt32.max), storageSize <= UInt64(Int.max),
           let storage = malloc(Int(storageSize)) else {
            return false
        }
        defer {
            free(storage)
        }

        var drawBuffer = lv_draw_buf_t()
        guard lv_draw_buf_init(
            &drawBuffer, UInt32(width), UInt32(height), LV_COLOR_FORMAT_RGB565,
            UInt32(LV_STRIDE_AUTO), storage, UInt32(storageSize)
        ) == LV_RESULT_OK else { return false }
        let result = lv_snapshot_take_to_draw_buf(screen, LV_COLOR_FORMAT_RGB565, &drawBuffer)
        bsp_lvgl_unlock()
        isLocked = false
        guard result == LV_RESULT_OK else { return false }
        let byteCount = Int(drawBuffer.header.stride) * Int(drawBuffer.header.h)
        handler(drawBuffer.data, byteCount, UInt32(drawBuffer.header.w),
                UInt32(drawBuffer.header.h), UInt32(drawBuffer.header.stride), context)
        return true
    }
}

/// Preserve the screenshot entry point used by the existing BLE transport.
@_cdecl("passport_ui_take_screenshot")
public func captureLVGLScreenshot(
    _ handler: passport_ui_screenshot_handler_t?, _ context: UnsafeMutableRawPointer?
) -> Bool {
    guard let handler else { return false }
    return LVGLScreenshot.capture(handler: handler, context: context)
}
