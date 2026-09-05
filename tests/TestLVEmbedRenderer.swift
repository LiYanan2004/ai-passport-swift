#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif
import EmbeddedSwiftUI
import LVGLRendererAdaptor

private let testRootGeometry = RootGeometry(
    screenSize: EmbeddedSize(width: 240, height: 320)
)

private extension _DisplayListRenderer {
    mutating func render<Content: View>(
        _ content: Content,
        in parent: Backend.Node,
        animation: Animation? = nil
    ) -> Bool {
        render(content, in: parent, rootGeometry: testRootGeometry, animation: animation)
    }

    mutating func render<Content: View>(
        _ content: Content,
        in parent: Backend.Node,
        transaction: Transaction
    ) -> Bool {
        render(content, in: parent, rootGeometry: testRootGeometry, transaction: transaction)
    }
}

private var snapshotWidth: UInt32 = 0
private var snapshotHeight: UInt32 = 0
private var snapshotStride: UInt32 = 0
private var snapshotByteCount = 0
private var snapshotNonzeroByteCount = 0
private var snapshotChecksum: UInt64 = 0
private var snapshotContentWidth = 0
private var snapshotContentHeight = 0
private var snapshotTopRowWidth = 0
private var snapshotMiddleRowWidth = 0

private func recordSnapshot(
    _ pixels: UnsafePointer<UInt8>?,
    _ byteCount: Int,
    _ width: UInt32,
    _ height: UInt32,
    _ stride: UInt32,
    _ context: UnsafeMutableRawPointer?
) {
    precondition(pixels != nil)
    precondition(test_lvgl_lock_depth() == 0)
    precondition(context == nil)
    snapshotWidth = width
    snapshotHeight = height
    snapshotStride = stride
    snapshotByteCount = byteCount
    snapshotNonzeroByteCount = 0
    snapshotChecksum = 14695981039346656037
    snapshotContentWidth = 0
    snapshotContentHeight = 0
    snapshotTopRowWidth = 0
    snapshotMiddleRowWidth = 0
    if let pixels {
        for index in 0..<byteCount {
            snapshotChecksum = (snapshotChecksum ^ UInt64(pixels[index])) &* 1099511628211
        }
        for index in 0..<byteCount where pixels[index] != 0 {
            snapshotNonzeroByteCount += 1
        }
        var minimumX = Int(width)
        var minimumY = Int(height)
        var maximumX = -1
        var maximumY = -1
        var rowWidths = [Int](repeating: 0, count: Int(height))
        for y in 0..<Int(height) {
            for x in 0..<Int(width) {
                let offset = y * Int(stride) + x * 2
                guard pixels[offset] != 0 || pixels[offset + 1] != 0 else { continue }
                minimumX = min(minimumX, x)
                minimumY = min(minimumY, y)
                maximumX = max(maximumX, x)
                maximumY = max(maximumY, y)
                rowWidths[y] += 1
            }
        }
        if maximumX >= minimumX, maximumY >= minimumY {
            snapshotContentWidth = maximumX - minimumX + 1
            snapshotContentHeight = maximumY - minimumY + 1
            snapshotTopRowWidth = rowWidths[minimumY]
            snapshotMiddleRowWidth = rowWidths[(minimumY + maximumY) / 2]
        }
    }
}

private struct EmptyDataShape: Shape {
    func path(in rect: ShapeRect) -> Path { Path() }
}

private struct TriangleClip: Shape {
    func path(in rect: ShapeRect) -> Path {
        Path { path in
            path.move(to: ShapePoint(x: rect.x + rect.width / 2, y: rect.y))
            path.addLine(to: ShapePoint(x: rect.x + rect.width, y: rect.y + rect.height))
            path.addLine(to: ShapePoint(x: rect.x, y: rect.y + rect.height))
            path.closeSubpath()
        }
    }
}

private struct DiagonalLayout: Layout {
    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: LayoutSubviews,
        cache: inout Void
    ) -> EmbeddedSize {
        proposal.replacingUnspecifiedDimensions()
    }

    func placeSubviews(
        in bounds: EmbeddedRect,
        proposal: ProposedViewSize,
        subviews: LayoutSubviews,
        cache: inout Void
    ) {
        for index in subviews.indices {
            subviews[index].place(
                at: EmbeddedPoint(
                    x: Int32(index * 12),
                    y: Int32(index * 10)
                ),
                proposal: .unspecified
            )
        }
    }
}

private final class OffsetAnimationModel {
    var x: Int32 = 0
}

private struct OffsetAnimationView: View {
    let model: OffsetAnimationModel

    var body: some View {
        VStack(spacing: 8) {
            VStack(spacing: 2) {
                Text("ANIMATION")
                Text("CENTERED")
            }
                .frame(width: 100, height: 40)
                .background(Color.green)
                .offset(x: Double(model.x))
            Text("STATIONARY")
        }
        .animation(.linear(duration: 0.1), value: model.x)
    }
}

private final class SizeAnimationModel {
    var expanded = false
}

private struct SizeAnimationView: View {
    let model: SizeAnimationModel

    var body: some View {
        Text("SIZE")
            .frame(
                width: model.expanded ? 140 : 80,
                height: model.expanded ? 60 : 30
            )
            .background(model.expanded ? Color.purple : Color.green)
    }
}

private final class OpacityAnimationModel {
    var opacity = 0.25
}

private struct OpacityAnimationView: View {
    let model: OpacityAnimationModel

    var body: some View {
        Text("OPACITY ANIMATION")
            .frame(width: 120, height: 40)
            .opacity(model.opacity)
            .animation(.linear(duration: 0.1), value: model.opacity)
    }
}

private final class RotationAnimationModel {
    var angle = Angle.zero
}

private struct RotationAnimationView: View {
    let model: RotationAnimationModel

    var body: some View {
        Text("ROTATION ANIMATION")
            .frame(width: 120, height: 40)
            .rotationEffect(model.angle)
            .animation(.linear(duration: 0.1), value: model.angle)
    }
}

private final class CircleScaleAnimationModel {
    var scale = 1.18
    var opacity = 1.0
}

private struct CircleScaleAnimationView: View {
    let model: CircleScaleAnimationModel

    var body: some View {
        Circle()
            .fill(.red)
            .frame(width: 22, height: 22)
            .scaleEffect(model.scale)
            .opacity(model.opacity)
            .offset(x: -8)
    }
}

private func findScaleNode(_ object: OpaquePointer) -> OpaquePointer? {
    let scaleX = lv_obj_get_style_transform_scale_x(object, LV_PART_MAIN)
    let scaleY = lv_obj_get_style_transform_scale_y(object, LV_PART_MAIN)
    if scaleX != 256 || scaleY != 256 {
        return object
    }
    for index in 0..<lv_obj_get_child_count(object) {
        if let child = lv_obj_get_child(object, Int32(index)),
           let match = findScaleNode(child) {
            return match
        }
    }
    return nil
}

private final class ZIndexAnimationModel {
    var isSwapped = false
    var repeatsForever = false
}

private struct ZIndexAnimationView: View {
    let model: ZIndexAnimationModel

    var body: some View {
        ZStack {
            Text("A")
                .frame(width: 20, height: 20)
                .offset(x: model.isSwapped ? 20 : -20)
                .zIndex(model.isSwapped ? 0 : 1)
            Text("B")
                .frame(width: 20, height: 20)
                .offset(x: model.isSwapped ? -20 : 20)
                .zIndex(model.isSwapped ? 1 : 0)
        }
        .animation(
            model.repeatsForever
                ? .linear(duration: 0.1).repeatForever(autoreverses: true)
                : .linear(duration: 0.1),
            value: model.isSwapped
        )
    }
}

private struct StatefulLaunchView: View {
    @State private var appeared = false

    var body: some View {
        Text("STATEFUL")
            .offset(x: appeared ? 40 : 0)
            .onAppear {
                withAnimation(
                    .linear(duration: 0.1)
                        .repeatForever(autoreverses: true)
                ) {
                    appeared = true
                }
            }
    }
}

private final class ConditionalOpacityAnimationModel {
    var isConnecting = false
    var isSignalActive = false
}

private struct ConditionalOpacityAnimationView: View {
    let model: ConditionalOpacityAnimationModel

    var body: some View {
        Text("signal")
            .opacity(model.isConnecting || model.isSignalActive ? 1 : 0.45)
            .animation(
                model.isConnecting
                    ? .linear(duration: 0.1).repeatForever(autoreverses: true)
                    : nil,
                value: model.isConnecting
            )
    }
}

private final class IdentityModel {
    var firstBranch = true
    var events: [String] = []
}

private struct IdentityLifecycleView: View {
    let model: IdentityModel
    var body: some View {
        if model.firstBranch {
            Text("A").onAppear { model.events.append("A+") }
                .onDisappear { model.events.append("A-") }
        } else {
            Text("B").onAppear { model.events.append("B+") }
                .onDisappear { model.events.append("B-") }
        }
    }
}

private struct IdentityScrollView: View {
    let model: IdentityModel
    var body: some View {
        VStack(spacing: 0) {
            if model.firstBranch {
                ScrollView { ForEach(0..<12) { Text("A \($0)") } }
                    .frame(width: 100, height: 50)
            }
            ScrollView { ForEach(0..<12) { Text("B \($0)") } }
                .frame(width: 100, height: 50)
        }
    }
}

private final class ScopedAnimationModel {
    var expanded = false
}

private struct ScopedAnimationView: View {
    let model: ScopedAnimationModel
    var body: some View {
        VStack(spacing: 0) {
            Text("FAST").frame(width: model.expanded ? 100 : 20, height: 10)
                .animation(.linear(duration: 0.1), value: model.expanded)
            Text("SLOW").frame(width: model.expanded ? 100 : 20, height: 10)
                .animation(.linear(duration: 0.5), value: model.expanded)
        }
    }
}

@main
struct TestLVEmbedRenderer {
    static func main() {
        check(LVGLRendererAdaptor.PhysicalButton(bspValue: 0) == .up)
        check(LVGLRendererAdaptor.PhysicalButton(bspValue: 1) == .down)
        check(LVGLRendererAdaptor.PhysicalButton(bspValue: 2) == .ok)
        check(LVGLRendererAdaptor.PhysicalButton(bspValue: 3) == nil)

        lv_init()
        var selfInvalidatingTimer: LVGLTimer?
        var timerInvocationCount = 0
        selfInvalidatingTimer = LVGLTimer(period: 1) {
            timerInvocationCount += 1
            selfInvalidatingTimer?.invalidate()
            selfInvalidatingTimer = nil
        }
        check(selfInvalidatingTimer != nil)
        lv_tick_inc(2)
        _ = lv_timer_handler()
        check(timerInvocationCount == 1)

        guard let display = lv_display_create(240, 320), let screen = lv_obj_create(nil) else {
            preconditionFailure("LVGL initialization failed")
        }
        lv_screen_load(screen)
        lv_obj_remove_style_all(screen)
        lv_obj_set_size(screen, 240, 320)
        let statefulController = LVGLHostingController(
            display: display,
            safeAreaInsets: EdgeInsets(top: 7, leading: 5, bottom: 11, trailing: 13)
        ) {
            StatefulLaunchView()
        }
        check(statefulController.present())
        let initialHostedScreen = lv_display_get_screen_active(display)!
        let initialContentRoot = lv_obj_get_child(initialHostedScreen, 0)!
        check(lv_obj_get_x(initialContentRoot) == 5)
        check(lv_obj_get_y(initialContentRoot) == 7)
        check(lv_obj_get_width(initialContentRoot) == 222)
        check(lv_obj_get_height(initialContentRoot) == 302)
        check(statefulController.needsRender)
        check(statefulController.render(
            transaction: _consumePendingTransaction() ?? Transaction()
        ))
        check(!statefulController.needsRender)
        check(lv_anim_count_running() > 0)
        lv_display_set_resolution(display, 180, 220)
        check(statefulController.needsRender)
        check(statefulController.render())
        check(!statefulController.needsRender)
        check(lv_anim_count_running() > 0)
        let resizedScreen = lv_display_get_screen_active(display)!
        let resizedRoot = lv_obj_get_child(resizedScreen, 0)!
        check(lv_obj_get_x(resizedRoot) == 5)
        check(lv_obj_get_y(resizedRoot) == 7)
        check(lv_obj_get_width(resizedRoot) == 162)
        check(lv_obj_get_height(resizedRoot) == 202)
        statefulController.unmount()
        lv_display_set_resolution(display, 240, 320)
        lv_screen_load(screen)

        var renderer = _DisplayListRenderer(backend: LVGLRenderBackend())
        let aligned = Text("A").font(.system(size: 20)).padding(4).background(Color.red)
            .frame(width: 100, height: 60, alignment: .bottomTrailing)
        check(renderer.render(aligned, in: screen))
        lv_obj_update_layout(screen)
        let root = lv_obj_get_child(screen, 0)!
        let frame = lv_obj_get_child(root, 0)!
        let background = lv_obj_get_child(frame, 0)!
        let padding = lv_obj_get_child(background, 0)!
        let label = lv_obj_get_child(padding, 0)!
        check(lv_obj_get_width(frame) == 100 && lv_obj_get_height(frame) == 60)
        check(lv_obj_get_x(background) + lv_obj_get_width(background) == 100)
        check(lv_obj_get_y(background) + lv_obj_get_height(background) == 60)
        check(lv_obj_get_width(padding) == lv_obj_get_width(label) + 8)
        check(lv_obj_get_height(padding) == lv_obj_get_height(label) + 8)
        check(lv_obj_get_style_text_font(label, LV_PART_MAIN) == LVGLFont.pointer(pointSize: 20))
        check(lv_color_to_u32(lv_obj_get_style_bg_color(background, LV_PART_MAIN)) == lv_color_to_u32(lv_color_hex(0xFF0000)))
        check(lv_obj_has_flag(frame, LV_OBJ_FLAG_OVERFLOW_VISIBLE))
        check(test_lv_obj_get_ext_draw_size(frame) >= 320)
        renderer.unmount()

        let customLayout = DiagonalLayout {
            Text("A")
            Text("B")
        }
        check(renderer.render(
            customLayout,
            in: screen,
            size: RenderSize(width: 80, height: 60)
        ))
        lv_obj_update_layout(screen)
        let customRoot = lv_obj_get_child(screen, 0)!
        let customContainer = lv_obj_get_child(customRoot, 0)!
        check(lv_obj_get_child_count(customContainer) == 2)
        check(lv_obj_get_x(lv_obj_get_child(customContainer, 0)!) == 0)
        check(lv_obj_get_y(lv_obj_get_child(customContainer, 0)!) == 0)
        check(lv_obj_get_x(lv_obj_get_child(customContainer, 1)!) == 12)
        check(lv_obj_get_y(lv_obj_get_child(customContainer, 1)!) == 10)
        renderer.unmount()

        let offsetInsideBackground = Text("OFFSET")
            .frame(width: 150, height: 44)
            .offset(x: 30, y: 80)
            .background(Color.purple)
        check(renderer.render(offsetInsideBackground, in: screen))
        lv_obj_update_layout(screen)
        let offsetBackgroundRoot = lv_obj_get_child(screen, 0)!
        let fixedBackground = lv_obj_get_child(offsetBackgroundRoot, 0)!
        let fixedOffsetContainer = lv_obj_get_child(fixedBackground, 0)!
        let translatedContent = lv_obj_get_child(fixedOffsetContainer, 0)!
        check(lv_obj_get_width(fixedBackground) == 150 && lv_obj_get_height(fixedBackground) == 44)
        check(lv_obj_get_width(fixedOffsetContainer) == 150 && lv_obj_get_height(fixedOffsetContainer) == 44)
        check(lv_obj_get_width(translatedContent) == 150 && lv_obj_get_height(translatedContent) == 44)
        check(lv_obj_get_style_translate_x(fixedBackground, LV_PART_MAIN) == 0)
        check(lv_obj_get_style_translate_y(fixedBackground, LV_PART_MAIN) == 0)
        check(lv_obj_get_style_translate_x(fixedOffsetContainer, LV_PART_MAIN) == 0)
        check(lv_obj_get_style_translate_y(fixedOffsetContainer, LV_PART_MAIN) == 0)
        check(lv_obj_get_style_translate_x(translatedContent, LV_PART_MAIN) == 30)
        check(lv_obj_get_style_translate_y(translatedContent, LV_PART_MAIN) == 80)
        renderer.unmount()

        let scaled = Text("SCALE")
            .frame(width: 80, height: 40)
            .scaleEffect(x: 1.5, y: 0.5, anchor: .topLeading)
        check(renderer.render(scaled, in: screen))
        lv_obj_update_layout(screen)
        let scaleRoot = lv_obj_get_child(screen, 0)!
        let scaleContainer = lv_obj_get_child(scaleRoot, 0)!
        check(lv_obj_get_style_transform_scale_x(scaleContainer, LV_PART_MAIN) == 384)
        check(lv_obj_get_style_transform_scale_y(scaleContainer, LV_PART_MAIN) == 128)
        check(lv_obj_get_style_transform_pivot_x(scaleContainer, LV_PART_MAIN) == 0)
        check(lv_obj_get_style_transform_pivot_y(scaleContainer, LV_PART_MAIN) == 0)
        check(lv_obj_has_flag(scaleContainer, LV_OBJ_FLAG_OVERFLOW_VISIBLE))
        check(test_lv_obj_get_ext_draw_size(scaleContainer) < 320)
        renderer.unmount()

        let rotated = Text("ROTATION")
            .frame(width: 80, height: 40)
            .rotationEffect(.degrees(22), anchor: .bottomTrailing)
        check(renderer.render(rotated, in: screen))
        lv_obj_update_layout(screen)
        let rotationRoot = lv_obj_get_child(screen, 0)!
        let rotationContainer = lv_obj_get_child(rotationRoot, 0)!
        check(lv_obj_get_style_transform_rotation(rotationContainer, LV_PART_MAIN) == 220)
        check(lv_obj_get_style_transform_pivot_x(rotationContainer, LV_PART_MAIN) == 80)
        check(lv_obj_get_style_transform_pivot_y(rotationContainer, LV_PART_MAIN) == 40)
        check(lv_obj_has_flag(rotationContainer, LV_OBJ_FLAG_OVERFLOW_VISIBLE))
        check(test_lv_obj_get_ext_draw_size(rotationContainer) < 320)
        renderer.unmount()

        let scaledOverflow = Text("OVERFLOW")
            .frame(width: 80, height: 40)
            .offset(x: 100)
            .scaleEffect(1.2)
        check(renderer.render(scaledOverflow, in: screen))
        lv_obj_update_layout(screen)
        let scaledOverflowRoot = lv_obj_get_child(screen, 0)!
        let scaledOverflowContainer = lv_obj_get_child(scaledOverflowRoot, 0)!
        check(lv_obj_has_flag(scaledOverflowContainer, LV_OBJ_FLAG_OVERFLOW_VISIBLE))
        check(test_lv_obj_get_ext_draw_size(scaledOverflowContainer) >= 100)
        renderer.unmount()

        let translucent = Text("OPACITY")
            .frame(width: 80, height: 40)
            .opacity(0.5)
        check(renderer.render(translucent, in: screen))
        let opacityRoot = lv_obj_get_child(screen, 0)!
        let opacityContainer = lv_obj_get_child(opacityRoot, 0)!
        check(lv_obj_get_style_opa_layered(opacityContainer, LV_PART_MAIN) == 128)
        check(lv_obj_has_flag(opacityContainer, LV_OBJ_FLAG_OVERFLOW_VISIBLE))
        check(test_lv_obj_get_ext_draw_size(opacityContainer) < 320)
        renderer.unmount()

        let translucentOverflow = Text("OPACITY OVERFLOW")
            .frame(width: 80, height: 40)
            .offset(x: 100)
            .opacity(0.5)
        check(renderer.render(translucentOverflow, in: screen))
        lv_obj_update_layout(screen)
        let translucentOverflowRoot = lv_obj_get_child(screen, 0)!
        let translucentOverflowContainer = lv_obj_get_child(translucentOverflowRoot, 0)!
        check(lv_obj_has_flag(translucentOverflowContainer, LV_OBJ_FLAG_OVERFLOW_VISIBLE))
        check(test_lv_obj_get_ext_draw_size(translucentOverflowContainer) >= 100)
        renderer.unmount()

        let nestedOpacity = Text("NESTED OPACITY")
            .opacity(0.5)
            .opacity(0.4)
        check(renderer.render(nestedOpacity, in: screen))
        let nestedOpacityRoot = lv_obj_get_child(screen, 0)!
        let outerOpacityContainer = lv_obj_get_child(nestedOpacityRoot, 0)!
        let innerOpacityContainer = lv_obj_get_child(outerOpacityContainer, 0)!
        check(lv_obj_get_style_opa_layered(outerOpacityContainer, LV_PART_MAIN) == 102)
        check(lv_obj_get_style_opa_layered(innerOpacityContainer, LV_PART_MAIN) == 128)
        renderer.unmount()

        for (opacity, expected) in [
            (-1.0, UInt8(0)),
            (Double.nan, UInt8(0)),
            (2.0, UInt8(255)),
        ] {
            check(renderer.render(Text("BOUNDED OPACITY").opacity(opacity), in: screen))
            let boundedOpacityRoot = lv_obj_get_child(screen, 0)!
            let boundedOpacityContainer = lv_obj_get_child(boundedOpacityRoot, 0)!
            check(lv_obj_get_style_opa_layered(boundedOpacityContainer, LV_PART_MAIN) == expected)
            renderer.unmount()
        }

        let clippingScroll = ScrollView { Text("clipped") }.frame(width: 80, height: 40)
        check(renderer.render(clippingScroll, in: screen))
        let clippingScrollRoot = lv_obj_get_child(screen, 0)!
        let clippingScrollNode = findScrollable(clippingScrollRoot)!
        check(!lv_obj_has_flag(clippingScrollNode, LV_OBJ_FLAG_OVERFLOW_VISIBLE))
        check(test_lv_obj_get_ext_draw_size(clippingScrollNode) < 320)
        renderer.unmount()

        let clippedContent = Text("CLIPPED")
            .frame(width: 64, height: 48)
            .clipped()
        check(renderer.render(clippedContent, in: screen))
        lv_obj_update_layout(screen)
        let clippedRoot = lv_obj_get_child(screen, 0)!
        let clipContainer = lv_obj_get_child(clippedRoot, 0)!
        check(lv_obj_get_width(clipContainer) == 64 && lv_obj_get_height(clipContainer) == 48)
        check(!lv_obj_has_flag(clipContainer, LV_OBJ_FLAG_OVERFLOW_VISIBLE))
        check(!lv_obj_get_style_clip_corner(clipContainer, LV_PART_MAIN))
        renderer.unmount()

        let roundedClipContent = Color.blue
            .frame(width: 64, height: 48)
            .clipShape(RoundedRectangle(cornerRadius: 8))
        check(renderer.render(roundedClipContent, in: screen))
        lv_obj_update_layout(screen)
        let roundedClipRoot = lv_obj_get_child(screen, 0)!
        let roundedClipContainer = lv_obj_get_child(roundedClipRoot, 0)!
        check(lv_obj_get_width(roundedClipContainer) == 64
            && lv_obj_get_height(roundedClipContainer) == 48)
        check(!lv_obj_has_flag(roundedClipContainer, LV_OBJ_FLAG_OVERFLOW_VISIBLE))
        check(lv_obj_get_style_clip_corner(roundedClipContainer, LV_PART_MAIN))
        check(lv_obj_get_style_radius(roundedClipContainer, LV_PART_MAIN) == 8)
        check(passport_ui_take_screenshot(recordSnapshot, nil))
        check(snapshotNonzeroByteCount > 0)
        check(snapshotContentWidth == 64 && snapshotContentHeight == 48)
        check(snapshotTopRowWidth < snapshotMiddleRowWidth)
        renderer.unmount()

        let circleClipContent = Color.blue
            .frame(width: 64, height: 32)
            .clipShape(Circle())
        check(renderer.render(circleClipContent, in: screen))
        lv_obj_update_layout(screen)
        let circleClipRoot = lv_obj_get_child(screen, 0)!
        let circleClipContainer = lv_obj_get_child(circleClipRoot, 0)!
        check(lv_obj_get_width(circleClipContainer) == 64
            && lv_obj_get_height(circleClipContainer) == 32)
        check(!lv_obj_get_style_clip_corner(circleClipContainer, LV_PART_MAIN))
        check(lv_obj_get_style_bitmap_mask_src(circleClipContainer, LV_PART_MAIN) != nil)
        check(passport_ui_take_screenshot(recordSnapshot, nil))
        check(snapshotNonzeroByteCount > 0)
        check(snapshotContentWidth == 32 && snapshotContentHeight == 32)
        check(snapshotTopRowWidth < snapshotMiddleRowWidth)
        renderer.unmount()

        let testImageBuffer = lv_draw_buf_create(32, 32, LV_COLOR_FORMAT_RGB565, 0)!
        guard let testImageData = testImageBuffer.pointee.data else {
            fatalError("Expected image data")
        }
        for index in 0..<Int(testImageBuffer.pointee.data_size) {
            testImageData[index] = 0xFF
        }
        var imageRenderer = _DisplayListRenderer(backend: LVGLRenderBackend(
            imageResolver: { _ in UnsafeRawPointer(testImageBuffer) }
        ))
        let circleClippedImage = Image("test-image")
            .resizable()
            .frame(width: 32, height: 32)
            .clipShape(Circle())
        check(imageRenderer.render(circleClippedImage, in: screen))
        lv_obj_update_layout(screen)
        let imageClipRoot = lv_obj_get_child(screen, 0)!
        let imageClipContainer = lv_obj_get_child(imageClipRoot, 0)!
        let imageFrame = lv_obj_get_child(imageClipContainer, 0)!
        let clippedImage = lv_obj_get_child(imageFrame, 0)!
        check(!lv_obj_get_style_clip_corner(imageClipContainer, LV_PART_MAIN))
        check(!lv_obj_get_style_clip_corner(clippedImage, LV_PART_MAIN))
        check(lv_obj_get_style_radius(clippedImage, LV_PART_MAIN) == LV_RADIUS_CIRCLE)
        check(lv_obj_get_style_bitmap_mask_src(imageClipContainer, LV_PART_MAIN) == nil)
        check(lv_obj_get_style_bitmap_mask_src(clippedImage, LV_PART_MAIN) == nil)
        check(passport_ui_take_screenshot(recordSnapshot, nil))
        check(snapshotNonzeroByteCount > 0)
        check(snapshotContentWidth == 32 && snapshotContentHeight == 32)
        check(snapshotTopRowWidth < snapshotMiddleRowWidth)
        imageRenderer.unmount()

        let roundedClippedImage = Image("test-image")
            .resizable()
            .frame(width: 32, height: 32)
            .clipShape(RoundedRectangle(cornerRadius: 8))
        check(imageRenderer.render(roundedClippedImage, in: screen))
        check(passport_ui_take_screenshot(recordSnapshot, nil))
        check(snapshotNonzeroByteCount > 0)
        check(snapshotContentWidth == 32 && snapshotContentHeight == 32)
        check(snapshotTopRowWidth < snapshotMiddleRowWidth)
        imageRenderer.unmount()

        let ellipseClippedImage = Image("test-image")
            .resizable()
            .frame(width: 32, height: 24)
            .clipShape(Ellipse())
        check(imageRenderer.render(ellipseClippedImage, in: screen))
        check(passport_ui_take_screenshot(recordSnapshot, nil))
        check(snapshotNonzeroByteCount > 0)
        check(snapshotContentWidth == 32 && snapshotContentHeight == 24)
        check(snapshotTopRowWidth < snapshotMiddleRowWidth)
        imageRenderer.unmount()

        let triangleClippedImage = Image("test-image")
            .resizable()
            .frame(width: 32, height: 24)
            .clipShape(TriangleClip())
        check(imageRenderer.render(triangleClippedImage, in: screen))
        check(passport_ui_take_screenshot(recordSnapshot, nil))
        check(snapshotNonzeroByteCount > 0)
        check(snapshotContentWidth == 32 && snapshotContentHeight == 24)
        check(snapshotTopRowWidth < snapshotMiddleRowWidth)
        imageRenderer.unmount()

        lv_draw_buf_destroy(testImageBuffer)

        let ellipseClipContent = Color.blue
            .frame(width: 64, height: 32)
            .clipShape(Ellipse())
        check(renderer.render(ellipseClipContent, in: screen))
        lv_obj_update_layout(screen)
        let ellipseClipRoot = lv_obj_get_child(screen, 0)!
        let ellipseClipContainer = lv_obj_get_child(ellipseClipRoot, 0)!
        check(lv_obj_get_style_bitmap_mask_src(ellipseClipContainer, LV_PART_MAIN) != nil)
        check(passport_ui_take_screenshot(recordSnapshot, nil))
        check(snapshotNonzeroByteCount > 0)
        check(snapshotContentWidth == 64 && snapshotContentHeight == 32)
        check(snapshotTopRowWidth < snapshotMiddleRowWidth)
        renderer.unmount()

        let triangleClipContent = Color.blue
            .frame(width: 32, height: 24)
            .clipShape(TriangleClip())
        check(renderer.render(triangleClipContent, in: screen))
        lv_obj_update_layout(screen)
        let triangleClipRoot = lv_obj_get_child(screen, 0)!
        let triangleClipContainer = lv_obj_get_child(triangleClipRoot, 0)!
        check(lv_obj_get_width(triangleClipContainer) == 32
            && lv_obj_get_height(triangleClipContainer) == 24)
        check(lv_obj_get_style_bitmap_mask_src(triangleClipContainer, LV_PART_MAIN) != nil)
        check(passport_ui_take_screenshot(recordSnapshot, nil))
        check(snapshotNonzeroByteCount > 0)
        check(snapshotContentWidth == 32 && snapshotContentHeight == 24)
        check(snapshotTopRowWidth < snapshotMiddleRowWidth)
        renderer.unmount()

        let overlay = ZStack(alignment: .bottomTrailing) {
            Text("wide").frame(width: 100, height: 40)
            Text("small").frame(width: 40, height: 20)
        }
        check(renderer.render(overlay, in: screen))
        lv_obj_update_layout(screen)
        let overlayRoot = lv_obj_get_child(screen, 0)!
        let overlayNode = lv_obj_get_child(overlayRoot, 0)!
        let smallerFrame = lv_obj_get_child(overlayNode, 1)!
        check(lv_obj_get_width(overlayNode) == 100 && lv_obj_get_height(overlayNode) == 40)
        check(lv_obj_get_x(smallerFrame) == 60 && lv_obj_get_y(smallerFrame) == 20)
        renderer.unmount()

        let shapes = ZStack {
            Rectangle().fill(.blue)
            RoundedRectangle(cornerRadius: 7.5)
                .strokeBorder(
                    .yellow,
                    style: StrokeStyle(
                        lineWidth: 3,
                        lineCap: .round,
                        lineJoin: .round,
                        dash: [5, 2]
                    )
                )
            Circle().inset(by: 8.25).fill(.red)
        }
        .frame(width: 64, height: 48)
        check(renderer.render(shapes, in: screen))
        lv_obj_update_layout(screen)
        let shapeRoot = lv_obj_get_child(screen, 0)!
        let shapeFrame = lv_obj_get_child(shapeRoot, 0)!
        let shapeOverlay = lv_obj_get_child(shapeFrame, 0)!
        check(lv_obj_get_child_count(shapeOverlay) == 3)
        for index in 0..<lv_obj_get_child_count(shapeOverlay) {
            let shape = lv_obj_get_child(shapeOverlay, Int32(index))!
            if index == 2 {
                check(lv_obj_get_width(shape) == 48 && lv_obj_get_height(shape) == 48)
            } else {
                check(lv_obj_get_width(shape) == 64 && lv_obj_get_height(shape) == 48)
            }
        }
        check(passport_ui_take_screenshot(recordSnapshot, nil))
        check(snapshotNonzeroByteCount > 0)
        // Scanline Shape fills must differ from the former triangle-fan output,
        // whose shared edges left visible radial seams inside curved fills.
        check(snapshotChecksum != 17707582865143185262)
        check(!passport_ui_take_screenshot(nil, nil))
        test_lvgl_set_lock_available(false)
        check(!LVGLScreenshot.capture(handler: recordSnapshot))
        check(test_lvgl_lock_depth() == 0)
        test_lvgl_set_lock_available(true)

        check(renderer.render(Text("animated"), in: screen, animation: .easeOut(duration: 0.2)))
        check(lv_obj_get_child_count(screen) == 2)
        check(lv_anim_count_running() > 0)
        lv_tick_inc(250)
        _ = lv_timer_handler()
        check(lv_obj_get_child_count(screen) == 1)
        renderer.unmount()

        let circleModel = CircleScaleAnimationModel()
        check(renderer.render(CircleScaleAnimationView(model: circleModel), in: screen))
        circleModel.scale = 0.72
        circleModel.opacity = 0.88
        check(renderer.render(
            CircleScaleAnimationView(model: circleModel),
            in: screen,
            animation: .easeInOut(duration: 0.49)
        ))
        for step in 0...10 {
            if step > 0 {
                lv_tick_inc(49)
                _ = lv_timer_handler()
            }
            lv_obj_update_layout(screen)
            check(passport_ui_take_screenshot(recordSnapshot, nil))
            let circleRoot = lv_obj_get_child(screen, 0)!
            let scaleNode = findScaleNode(circleRoot)!
            let opacityNode = lv_obj_get_parent(scaleNode)!
            let scaleX = lv_obj_get_style_transform_scale_x(scaleNode, LV_PART_MAIN)
            let scaleY = lv_obj_get_style_transform_scale_y(scaleNode, LV_PART_MAIN)
            check(scaleX == scaleY)
            check(snapshotContentWidth == snapshotContentHeight)
            if step == 0 {
                check(test_lv_obj_get_ext_draw_size(opacityNode) >= 5)
                check(snapshotContentWidth == 26)
                check(snapshotTopRowWidth < snapshotMiddleRowWidth / 2)
            }
        }
        renderer.unmount()

        let demo = EmbeddedSwiftUIDemoView()
        check(renderer.render(demo, in: screen, size: RenderSize(width: 194, height: 202)))
        lv_obj_update_layout(screen)
        let demoRoot = lv_obj_get_child(screen, 0)!
        let demoStack = lv_obj_get_child(demoRoot, 0)!
        check(lv_obj_get_width(demoRoot) == 194 && lv_obj_get_height(demoRoot) == 202)
        check(lv_obj_get_width(demoStack) <= 194)
        check(findScrollable(demoRoot) != nil)
        let nodeCount = countNodes(screen)
        check(renderer.handlePhysicalButton(.down))
        check(countNodes(screen) == nodeCount)
        check(renderer.handlePhysicalButton(.ok))
        check(renderer.render(
            demo,
            in: screen,
            size: RenderSize(width: 194, height: 202),
            transaction: _consumePendingTransaction() ?? Transaction()
        ))
        check(countNodes(screen) == nodeCount)
        check(lv_anim_count_running() > 0)
        lv_tick_inc(400)
        _ = lv_timer_handler()
        check(passport_ui_take_screenshot(recordSnapshot, nil))
        check(snapshotNonzeroByteCount > 0)
        check(snapshotWidth == 240 && snapshotHeight == 320)
        check(snapshotStride >= snapshotWidth * 2)
        check(snapshotByteCount == Int(snapshotStride * snapshotHeight))
        renderer.unmount()
        check(lv_obj_get_child_count(screen) == 0)

        let sizeModel = SizeAnimationModel()
        let sizeView = SizeAnimationView(model: sizeModel)
        check(renderer.render(sizeView, in: screen))
        lv_obj_update_layout(screen)
        let initialSizeRoot = lv_obj_get_child(screen, 0)!
        let initialBackground = lv_obj_get_child(initialSizeRoot, 0)!
        let initialColor = lv_color_to_u32(
            lv_obj_get_style_bg_color(initialBackground, LV_PART_MAIN)
        )
        sizeModel.expanded = true
        check(renderer.render(
            sizeView,
            in: screen,
            animation: .linear(duration: 0.1)
        ))
        let sizeRoot = lv_obj_get_child(screen, 0)!
        let animatedBackground = lv_obj_get_child(sizeRoot, 0)!
        let animatedFrame = lv_obj_get_child(animatedBackground, 0)!
        check(lv_obj_get_style_width(animatedFrame, LV_PART_MAIN) == 80)
        check(lv_obj_get_style_height(animatedFrame, LV_PART_MAIN) == 30)
        check(lv_color_to_u32(
            lv_obj_get_style_bg_color(animatedBackground, LV_PART_MAIN)
        ) == initialColor)
        lv_tick_inc(50)
        _ = lv_timer_handler()
        let middleWidth = lv_obj_get_style_width(animatedFrame, LV_PART_MAIN)
        let middleHeight = lv_obj_get_style_height(animatedFrame, LV_PART_MAIN)
        check(middleWidth > 80 && middleWidth < 140)
        check(middleHeight > 30 && middleHeight < 60)
        let middleColor = lv_color_to_u32(
            lv_obj_get_style_bg_color(animatedBackground, LV_PART_MAIN)
        )
        check(middleColor != initialColor && middleColor != 0x8833ff)
        lv_tick_inc(200)
        _ = lv_timer_handler()
        check(lv_obj_get_style_width(animatedFrame, LV_PART_MAIN) == 140)
        check(lv_obj_get_style_height(animatedFrame, LV_PART_MAIN) == 60)
        check(lv_color_to_u32(
            lv_obj_get_style_bg_color(animatedBackground, LV_PART_MAIN)
        ) != initialColor)
        renderer.unmount()

        let opacityModel = OpacityAnimationModel()
        let opacityView = OpacityAnimationView(model: opacityModel)
        check(renderer.render(opacityView, in: screen))
        opacityModel.opacity = 0.75
        check(renderer.render(opacityView, in: screen))
        let animatedOpacityRoot = lv_obj_get_child(screen, 0)!
        let animatedOpacityContainer = lv_obj_get_child(animatedOpacityRoot, 0)!
        check(lv_obj_get_style_opa_layered(animatedOpacityContainer, LV_PART_MAIN) == 64)
        lv_tick_inc(50)
        _ = lv_timer_handler()
        let middleOpacity = lv_obj_get_style_opa_layered(animatedOpacityContainer, LV_PART_MAIN)
        check(middleOpacity > 120 && middleOpacity < 136)
        lv_tick_inc(60)
        _ = lv_timer_handler()
        check(lv_obj_get_style_opa_layered(animatedOpacityContainer, LV_PART_MAIN) == 191)
        renderer.unmount()

        let rotationModel = RotationAnimationModel()
        let rotationView = RotationAnimationView(model: rotationModel)
        check(renderer.render(rotationView, in: screen))
        rotationModel.angle = .degrees(90)
        check(renderer.render(rotationView, in: screen))
        let animatedRotationRoot = lv_obj_get_child(screen, 0)!
        let animatedRotationContainer = lv_obj_get_child(animatedRotationRoot, 0)!
        check(lv_obj_get_style_transform_rotation(
            animatedRotationContainer,
            LV_PART_MAIN
        ) == 0)
        lv_tick_inc(50)
        _ = lv_timer_handler()
        let middleRotation = lv_obj_get_style_transform_rotation(
            animatedRotationContainer,
            LV_PART_MAIN
        )
        check(middleRotation > 400 && middleRotation < 500)
        lv_tick_inc(60)
        _ = lv_timer_handler()
        check(lv_obj_get_style_transform_rotation(
            animatedRotationContainer,
            LV_PART_MAIN
        ) == 900)
        renderer.unmount()

        let offsetModel = OffsetAnimationModel()
        let offsetView = OffsetAnimationView(model: offsetModel)
        check(renderer.render(offsetView, in: screen))
        lv_obj_update_layout(screen)
        let firstOffsetRoot = lv_obj_get_child(screen, 0)!
        let firstOffsetStack = lv_obj_get_child(firstOffsetRoot, 0)!
        let firstStationaryLabel = lv_obj_get_child(firstOffsetStack, 1)!
        let stationaryY = lv_obj_get_y(firstStationaryLabel)
        offsetModel.x = 100
        check(renderer.render(offsetView, in: screen))
        check(lv_obj_get_child_count(screen) == 1)
        let offsetRoot = lv_obj_get_child(screen, 0)!
        let offsetStack = lv_obj_get_child(offsetRoot, 0)!
        let offsetContainer = lv_obj_get_child(offsetStack, 0)!
        let stationaryLabel = lv_obj_get_child(offsetStack, 1)!
        let offsetBackground = lv_obj_get_child(offsetContainer, 0)!
        let offsetFrame = lv_obj_get_child(offsetBackground, 0)!
        let offsetContentStack = lv_obj_get_child(offsetFrame, 0)!
        let firstOffsetLabel = lv_obj_get_child(offsetContentStack, 0)!
        let secondOffsetLabel = lv_obj_get_child(offsetContentStack, 1)!
        check(lv_obj_has_flag(offsetStack, LV_OBJ_FLAG_OVERFLOW_VISIBLE))
        check(lv_obj_has_flag(offsetContainer, LV_OBJ_FLAG_OVERFLOW_VISIBLE))
        check(lv_obj_get_y(stationaryLabel) == stationaryY)
        check(lv_obj_get_style_translate_x(offsetContainer, LV_PART_MAIN) == 0)
        check(lv_obj_get_style_translate_x(offsetBackground, LV_PART_MAIN) == 0)
        check(lv_obj_get_style_translate_x(offsetFrame, LV_PART_MAIN) == 0)
        check(lv_obj_get_style_translate_x(firstOffsetLabel, LV_PART_MAIN) == 0)
        check(lv_obj_get_style_translate_x(secondOffsetLabel, LV_PART_MAIN) == 0)
        lv_tick_inc(50)
        _ = lv_timer_handler()
        let middleTranslation = lv_obj_get_style_translate_x(offsetBackground, LV_PART_MAIN)
        check(middleTranslation > 40 && middleTranslation < 60)
        lv_tick_inc(60)
        _ = lv_timer_handler()
        check(lv_obj_get_style_translate_x(offsetContainer, LV_PART_MAIN) == 0)
        check(lv_obj_get_style_translate_x(offsetBackground, LV_PART_MAIN) == 100)
        check(lv_obj_get_y(stationaryLabel) == stationaryY)

        offsetModel.x = 200
        check(renderer.render(
            OffsetAnimationView(model: offsetModel),
            in: screen,
            animation: .timingCurve(0, 1, 1, 1, duration: 0.1)
        ))
        lv_tick_inc(50)
        _ = lv_timer_handler()
        let bezierRoot = lv_obj_get_child(screen, 0)!
        let bezierStack = lv_obj_get_child(bezierRoot, 0)!
        let bezierContainer = lv_obj_get_child(bezierStack, 0)!
        let bezierBackground = lv_obj_get_child(bezierContainer, 0)!
        check(lv_obj_get_style_translate_x(bezierContainer, LV_PART_MAIN) == 0)
        check(lv_obj_get_style_translate_x(bezierBackground, LV_PART_MAIN) >= 100)
        check(lv_obj_get_style_translate_x(bezierBackground, LV_PART_MAIN) <= 200)
        lv_tick_inc(200)
        _ = lv_timer_handler()
        check(lv_obj_get_style_translate_x(bezierContainer, LV_PART_MAIN) == 0)
        check(lv_obj_get_style_translate_x(bezierBackground, LV_PART_MAIN) == 200)

        check(renderer.render(
            Text("repeat").offset(x: 100),
            in: screen,
            animation: .linear(duration: 0.1).repeatCount(3, autoreverses: true)
        ))
        lv_tick_inc(150)
        _ = lv_timer_handler()
        lv_obj_update_layout(screen)
        check(lv_obj_get_child_count(screen) == 1)
        check(lv_anim_count_running() > 0)
        lv_tick_inc(200)
        _ = lv_timer_handler()
        check(lv_anim_count_running() == 0)

        check(renderer.render(
            Text("forever").offset(x: 160),
            in: screen,
            animation: .spring.repeatForever(autoreverses: true)
        ))
        check(lv_anim_count_running() > 0)
        lv_tick_inc(100)
        _ = lv_timer_handler()
        let springRoot = lv_obj_get_child(screen, 0)!
        let springContainer = lv_obj_get_child(springRoot, 0)!
        let springLabel = lv_obj_get_child(springContainer, 0)!
        let springTranslation = lv_obj_get_style_translate_x(springLabel, LV_PART_MAIN)
        check(springTranslation > 100 && springTranslation < 160)

        let conditionalOpacityModel = ConditionalOpacityAnimationModel()
        check(renderer.render(
            ConditionalOpacityAnimationView(model: conditionalOpacityModel),
            in: screen
        ))
        conditionalOpacityModel.isConnecting = true
        check(renderer.render(
            ConditionalOpacityAnimationView(model: conditionalOpacityModel),
            in: screen
        ))
        check(lv_anim_count_running() > 0)
        conditionalOpacityModel.isConnecting = false
        conditionalOpacityModel.isSignalActive = true
        check(renderer.render(
            ConditionalOpacityAnimationView(model: conditionalOpacityModel),
            in: screen
        ))
        check(lv_anim_count_running() == 0)

        renderer.unmount()
        check(lv_anim_count_running() == 0)

        let zIndexModel = ZIndexAnimationModel()
        let zIndexView = ZIndexAnimationView(model: zIndexModel)
        check(renderer.render(zIndexView, in: screen))
        let initialZIndexRoot = lv_obj_get_child(screen, 0)!
        let initialZIndexOverlay = lv_obj_get_child(initialZIndexRoot, 0)!
        let initialBackOffset = lv_obj_get_child(initialZIndexOverlay, 0)!
        let initialBackFrame = lv_obj_get_child(initialBackOffset, 0)!
        let initialFrontOffset = lv_obj_get_child(initialZIndexOverlay, 1)!
        let initialFrontFrame = lv_obj_get_child(initialFrontOffset, 0)!
        check(lv_obj_get_style_translate_x(initialBackFrame, LV_PART_MAIN) == 20)
        check(lv_obj_get_style_translate_x(initialFrontFrame, LV_PART_MAIN) == -20)

        zIndexModel.isSwapped = true
        check(renderer.render(zIndexView, in: screen))
        let zIndexRoot = lv_obj_get_child(screen, 0)!
        let zIndexOverlay = lv_obj_get_child(zIndexRoot, 0)!
        let reorderedBOffset = lv_obj_get_child(zIndexOverlay, 0)!
        let reorderedAOffset = lv_obj_get_child(zIndexOverlay, 1)!
        let reorderedBFrame = lv_obj_get_child(reorderedBOffset, 0)!
        let reorderedAFrame = lv_obj_get_child(reorderedAOffset, 0)!
        check(lv_obj_get_style_translate_x(reorderedBFrame, LV_PART_MAIN) == 20)
        check(lv_obj_get_style_translate_x(reorderedAFrame, LV_PART_MAIN) == -20)
        lv_tick_inc(50)
        _ = lv_timer_handler()
        check(lv_obj_get_index(reorderedBOffset) == 0)
        check(lv_obj_get_index(reorderedAOffset) == 1)
        let middleZIndexTranslation = lv_obj_get_style_translate_x(
            reorderedAFrame,
            LV_PART_MAIN
        )
        check(middleZIndexTranslation > -5 && middleZIndexTranslation < 5)
        lv_tick_inc(60)
        _ = lv_timer_handler()
        check(lv_obj_get_index(reorderedAOffset) == 0)
        check(lv_obj_get_index(reorderedBOffset) == 1)
        check(lv_obj_get_style_translate_x(reorderedAFrame, LV_PART_MAIN) == 20)

        zIndexModel.isSwapped = false
        check(renderer.render(zIndexView, in: screen))
        lv_tick_inc(100)
        zIndexModel.isSwapped = true
        check(renderer.render(zIndexView, in: screen))
        let resumedZIndexRoot = lv_obj_get_child(screen, 0)!
        let resumedZIndexOverlay = lv_obj_get_child(resumedZIndexRoot, 0)!
        let resumedBOffset = lv_obj_get_child(resumedZIndexOverlay, 0)!
        let resumedAOffset = lv_obj_get_child(resumedZIndexOverlay, 1)!
        let resumedAFrame = lv_obj_get_child(resumedAOffset, 0)!
        check(lv_obj_get_index(resumedBOffset) == 0)
        check(lv_obj_get_index(resumedAOffset) == 1)
        check(lv_obj_get_style_translate_x(resumedAFrame, LV_PART_MAIN) == -20)
        lv_tick_inc(50)
        _ = lv_timer_handler()
        check(lv_obj_get_index(resumedBOffset) == 0)
        check(lv_obj_get_index(resumedAOffset) == 1)
        let resumedMiddleTranslation = lv_obj_get_style_translate_x(
            resumedAFrame,
            LV_PART_MAIN
        )
        check(resumedMiddleTranslation > -5 && resumedMiddleTranslation < 5)
        lv_tick_inc(60)
        _ = lv_timer_handler()
        check(lv_obj_get_index(resumedAOffset) == 0)
        check(lv_obj_get_index(resumedBOffset) == 1)
        check(lv_obj_get_style_translate_x(resumedAFrame, LV_PART_MAIN) == 20)
        renderer.unmount()

        let repeatingZIndexModel = ZIndexAnimationModel()
        repeatingZIndexModel.repeatsForever = true
        let repeatingZIndexView = ZIndexAnimationView(model: repeatingZIndexModel)
        check(renderer.render(repeatingZIndexView, in: screen))
        repeatingZIndexModel.isSwapped = true
        check(renderer.render(repeatingZIndexView, in: screen))
        let repeatingZIndexRoot = lv_obj_get_child(screen, 0)!
        let repeatingZIndexOverlay = lv_obj_get_child(repeatingZIndexRoot, 0)!
        let repeatingBOffset = lv_obj_get_child(repeatingZIndexOverlay, 0)!
        let repeatingAOffset = lv_obj_get_child(repeatingZIndexOverlay, 1)!
        lv_tick_inc(50)
        _ = lv_timer_handler()
        check(lv_obj_get_index(repeatingBOffset) == 0)
        check(lv_obj_get_index(repeatingAOffset) == 1)
        lv_tick_inc(60)
        _ = lv_timer_handler()
        check(lv_obj_get_index(repeatingAOffset) == 0)
        check(lv_obj_get_index(repeatingBOffset) == 1)
        lv_tick_inc(50)
        _ = lv_timer_handler()
        check(lv_obj_get_index(repeatingAOffset) == 0)
        check(lv_obj_get_index(repeatingBOffset) == 1)
        lv_tick_inc(60)
        _ = lv_timer_handler()
        check(lv_obj_get_index(repeatingBOffset) == 0)
        check(lv_obj_get_index(repeatingAOffset) == 1)
        renderer.unmount()

        let identityModel = IdentityModel()
        check(renderer.render(IdentityLifecycleView(model: identityModel), in: screen))
        identityModel.firstBranch = false
        check(renderer.render(IdentityLifecycleView(model: identityModel), in: screen))
        check(identityModel.events == ["A+", "A-", "B+"])
        renderer.unmount()
        check(identityModel.events == ["A+", "A-", "B+", "B-"])

        identityModel.firstBranch = true
        check(renderer.render(IdentityScrollView(model: identityModel), in: screen))
        let scrollNodes = descendants(screen).filter {
            lv_obj_has_flag($0, LV_OBJ_FLAG_SCROLLABLE) && $0 != screen
        }
        check(scrollNodes.count == 2)
        lv_obj_update_layout(screen)
        lv_obj_scroll_to_y(scrollNodes[0], 32, false)
        lv_obj_scroll_to_y(scrollNodes[1], 96, false)
        identityModel.firstBranch = false
        check(renderer.render(IdentityScrollView(model: identityModel), in: screen))
        let remainingScroll = descendants(screen).first {
            lv_obj_has_flag($0, LV_OBJ_FLAG_SCROLLABLE) && $0 != screen
        }!
        check(lv_obj_get_scroll_y(remainingScroll) == 96)
        renderer.unmount()

        let scopedModel = ScopedAnimationModel()
        check(renderer.render(ScopedAnimationView(model: scopedModel), in: screen))
        scopedModel.expanded = true
        check(renderer.render(ScopedAnimationView(model: scopedModel), in: screen))
        lv_tick_inc(150)
        _ = lv_timer_handler()
        lv_obj_update_layout(screen)
        let scopedRoot = lv_obj_get_child(screen, 0)!
        let scopedStack = lv_obj_get_child(scopedRoot, 0)!
        let fastFrame = lv_obj_get_child(scopedStack, 0)!
        let slowFrame = lv_obj_get_child(scopedStack, 1)!
        check(lv_obj_get_width(fastFrame) == 100)
        check(lv_obj_get_width(slowFrame) > 20 && lv_obj_get_width(slowFrame) < 100)
        renderer.unmount()

        check(renderer.render(VStack {
            Text("Ready")
            EmptyDataShape().frame(width: 20, height: 20)
        }, in: screen))
        let preservedRoot = lv_obj_get_child(screen, 0)
        check(!renderer.render(Text("Mirror").scaleEffect(x: -1, y: 1), in: screen))
        check(lv_obj_get_child(screen, 0) == preservedRoot)
        renderer.unmount()

        lv_obj_delete(screen)
        lv_display_delete(display)
        lv_deinit()
        print("LVGL backend tests: PASS (layout, low-memory shapes, Bezier, spring, repeat, lifecycle, font, color and scroll)")
    }

    private static func check(_ condition: Bool, line: UInt = #line) {
        if !condition {
            print("LVGL assertion failed at line \(line)")
            fflush(nil)
            fatalError("LVGL assertion")
        }
    }

    private static func findScrollable(_ node: OpaquePointer) -> OpaquePointer? {
        if lv_obj_has_flag(node, LV_OBJ_FLAG_SCROLLABLE) { return node }
        for index in 0..<lv_obj_get_child_count(node) {
            if let child = lv_obj_get_child(node, Int32(index)), let result = findScrollable(child) { return result }
        }
        return nil
    }
    private static func countNodes(_ node: OpaquePointer) -> Int {
        var count = 1
        for index in 0..<lv_obj_get_child_count(node) {
            if let child = lv_obj_get_child(node, Int32(index)) { count += countNodes(child) }
        }
        return count
    }

    private static func descendants(_ node: OpaquePointer) -> [OpaquePointer] {
        var result: [OpaquePointer] = []
        for index in 0..<lv_obj_get_child_count(node) {
            if let child = lv_obj_get_child(node, Int32(index)) {
                result.append(child)
                result.append(contentsOf: descendants(child))
            }
        }
        return result
    }
}
