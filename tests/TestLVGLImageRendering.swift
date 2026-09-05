#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif
import EmbeddedSwiftUI
import LVGLRendererAdaptor

private let rootGeometry = RootGeometry(
    screenSize: EmbeddedSize(width: 64, height: 64)
)

private var contentWidth = 0
private var contentHeight = 0
private var topRowWidth = 0
private var middleRowWidth = 0

private func check(_ condition: @autoclosure () -> Bool) {
    precondition(condition())
}

private func recordSnapshot(
    _ pixels: UnsafePointer<UInt8>?,
    _ byteCount: Int,
    _ width: UInt32,
    _ height: UInt32,
    _ stride: UInt32,
    _ context: UnsafeMutableRawPointer?
) {
    precondition(context == nil)
    guard let pixels else { preconditionFailure("Missing snapshot pixels") }
    var minimumX = Int(width)
    var minimumY = Int(height)
    var maximumX = -1
    var maximumY = -1
    var rowWidths = [Int](repeating: 0, count: Int(height))
    for y in 0..<Int(height) {
        for x in 0..<Int(width) {
            let offset = y * Int(stride) + x * 2
            guard offset + 1 < byteCount,
               pixels[offset] != 0 || pixels[offset + 1] != 0 else {
                continue
            }
            minimumX = min(minimumX, x)
            minimumY = min(minimumY, y)
            maximumX = max(maximumX, x)
            maximumY = max(maximumY, y)
            rowWidths[y] += 1
        }
    }
    contentWidth = maximumX >= minimumX ? maximumX - minimumX + 1 : 0
    contentHeight = maximumY >= minimumY ? maximumY - minimumY + 1 : 0
    topRowWidth = contentHeight > 0 ? rowWidths[minimumY] : 0
    middleRowWidth = contentHeight > 0 ? rowWidths[(minimumY + maximumY) / 2] : 0
}

private func imageNode(in screen: OpaquePointer, clipped: Bool) -> OpaquePointer {
    let root = lv_obj_get_child(screen, 0)!
    let first = lv_obj_get_child(root, 0)!
    if clipped {
        let frame = lv_obj_get_child(first, 0)!
        return lv_obj_get_child(frame, 0)!
    }
    return lv_obj_get_child(first, 0)!
}

@main
struct TestLVGLImageRendering {
    static func main() {
        lv_init()
        guard let display = lv_display_create(64, 64),
           let screen = lv_obj_create(nil),
           let source = lv_draw_buf_create(32, 32, LV_COLOR_FORMAT_RGB565, 0),
           let sourcePixels = source.pointee.data else {
            preconditionFailure("LVGL setup failed")
        }
        memset(sourcePixels, 0xFF, Int(source.pointee.data_size))
        lv_screen_load(screen)
        lv_obj_remove_style_all(screen)
        lv_obj_set_size(screen, 64, 64)

        var renderer = _DisplayListRenderer(backend: LVGLRenderBackend(
            imageResolver: { _ in UnsafeRawPointer(source) }
        ))
        let square = Image("test-image")
            .resizable()
            .frame(width: 24, height: 20)
        check(renderer.render(square, in: screen, rootGeometry: rootGeometry))
        lv_obj_update_layout(screen)
        let squareImage = imageNode(in: screen, clipped: false)
        let squareSource = lv_image_get_src(squareImage)!
            .assumingMemoryBound(to: lv_image_dsc_t.self)
        check(squareSource.pointee.header.w == 24)
        check(squareSource.pointee.header.h == 20)
        check(lv_image_get_scale_x(squareImage) == 256)
        check(lv_image_get_scale_y(squareImage) == 256)
        check(passport_ui_take_screenshot(recordSnapshot, nil))
        check(contentWidth == 24 && contentHeight == 20)
        renderer.unmount()

        let circle = Image("test-image")
            .resizable()
            .frame(width: 24, height: 24)
            .clipShape(Circle())
        check(renderer.render(circle, in: screen, rootGeometry: rootGeometry))
        lv_obj_update_layout(screen)
        let circleImage = imageNode(in: screen, clipped: true)
        let circleSource = lv_image_get_src(circleImage)!
            .assumingMemoryBound(to: lv_image_dsc_t.self)
        check(circleSource.pointee.header.w == 24)
        check(circleSource.pointee.header.h == 24)
        check(lv_image_get_scale_x(circleImage) == 256)
        check(lv_image_get_scale_y(circleImage) == 256)
        check(lv_obj_get_style_radius(circleImage, LV_PART_MAIN) == LV_RADIUS_CIRCLE)
        check(passport_ui_take_screenshot(recordSnapshot, nil))
        check(contentWidth == 24 && contentHeight == 24)
        check(topRowWidth < middleRowWidth / 2)
        renderer.unmount()

        lv_draw_buf_destroy(source)
        lv_obj_delete(screen)
        lv_display_delete(display)
        print("LVGL resized image and circle clip tests: PASS")
    }
}
