import EmbeddedSwiftUI

func yieldDuringSoftwareRasterization() {
#if ESP_PLATFORM
    passport_lvgl_cooperative_yield()
#endif
}

private struct LVGLShapeContext {
    let path: Path
    let color: Color.Resolved
    let style: ShapeRenderingStyle
    private let edges: [LVGLPathEdge]
    private var intersections: [(x: Float, winding: Int)]

    init(path: Path, color: Color.Resolved, style: ShapeRenderingStyle) {
        self.path = path
        self.color = color
        self.style = style
        edges = LVGLPathRasterizer.flattenedEdges(path)
        var intersections: [(x: Float, winding: Int)] = []
        intersections.reserveCapacity(edges.count)
        self.intersections = intersections
    }

    func point(_ point: ShapePoint, in coordinates: lv_area_t) -> lv_point_precise_t {
        lv_point_precise_t(x: coordinates.x1 + Int32(point.x.rounded()),
                           y: coordinates.y1 + Int32(point.y.rounded()))
    }

    mutating func draw(in object: OpaquePointer, layer: UnsafeMutablePointer<lv_layer_t>) {
        var coordinates = lv_area_t()
        lv_obj_get_coords(object, &coordinates)
        switch style {
        case let .fill(fillStyle):
            drawFill(layer, coordinates: coordinates, style: fillStyle)
        case let .stroke(strokeStyle):
            drawStroke(layer, coordinates: coordinates, style: strokeStyle)
        }
    }

    private mutating func drawFill(
        _ layer: UnsafeMutablePointer<lv_layer_t>,
        coordinates: lv_area_t,
        style: FillStyle
    ) {
        let width = coordinates.x2 - coordinates.x1 + 1
        let height = coordinates.y2 - coordinates.y1 + 1
        guard width > 0, height > 0 else { return }
        guard !edges.isEmpty else { return }
        var descriptor = lv_draw_fill_dsc_t()
        lv_draw_fill_dsc_init(&descriptor)
        descriptor.color = lv_color_hex(color.rgb)
        descriptor.opa = color.opacity
        for localY in 0..<height {
            if localY > 0 && localY % 16 == 0 {
                yieldDuringSoftwareRasterization()
            }
            collectIntersections(at: Float(localY) + 0.5)
            if style.isEOFilled {
                var index = 0
                while index + 1 < intersections.count {
                    drawFillRange(
                        from: intersections[index].x,
                        to: intersections[index + 1].x,
                        localY: localY,
                        width: width,
                        coordinates: coordinates,
                        layer: layer,
                        descriptor: &descriptor
                    )
                    index += 2
                }
            } else {
                var winding = 0
                var rangeStart: Float?
                for intersection in intersections {
                    let wasInside = winding != 0
                    winding += intersection.winding
                    if !wasInside && winding != 0 {
                        rangeStart = intersection.x
                    } else if wasInside && winding == 0, let start = rangeStart {
                        drawFillRange(
                            from: start,
                            to: intersection.x,
                            localY: localY,
                            width: width,
                            coordinates: coordinates,
                            layer: layer,
                            descriptor: &descriptor
                        )
                        rangeStart = nil
                    }
                }
            }
        }
    }

    private mutating func collectIntersections(at y: Float) {
        intersections.removeAll(keepingCapacity: true)
        for edge in edges {
            let start = edge.start
            let end = edge.end
            guard (start.y <= y && end.y > y) || (end.y <= y && start.y > y) else {
                continue
            }
            let x = start.x + (y - start.y) * (end.x - start.x) / (end.y - start.y)
            guard x.isFinite else { continue }
            intersections.append((x: x, winding: end.y > start.y ? 1 : -1))
        }
        intersections.sort { $0.x < $1.x }
    }

    private func drawFillRange(
        from start: Float,
        to end: Float,
        localY: Int32,
        width: Int32,
        coordinates: lv_area_t,
        layer: UnsafeMutablePointer<lv_layer_t>,
        descriptor: inout lv_draw_fill_dsc_t
    ) {
        guard start.isFinite, end.isFinite, end > start else { return }
        let firstValue = max(-0.5, start - 0.5)
        let lastValue = min(Float(width) - 0.5, end - 0.5)
        guard lastValue >= firstValue else { return }
        let first = max(0, Int32(firstValue.rounded(.up)))
        let last = min(width - 1, Int32(lastValue.rounded(.up)) - 1)
        guard first <= last else { return }
        var area = lv_area_t()
        area.x1 = coordinates.x1 + first
        area.x2 = coordinates.x1 + last
        area.y1 = coordinates.y1 + localY
        area.y2 = area.y1
        lv_draw_fill(layer, &descriptor, &area)
    }

    private func drawStroke(
        _ layer: UnsafeMutablePointer<lv_layer_t>,
        coordinates: lv_area_t,
        style: StrokeStyle
    ) {
        var current = lv_point_precise_t()
        var subpathStart = lv_point_precise_t()
        var hasCurrent = false
        for element in path.elements {
            if case let .move(position) = element {
                current = point(position, in: coordinates)
                subpathStart = current
                hasCurrent = true
                continue
            }
            guard hasCurrent else { continue }
            if case .closeSubpath = element {
                drawSegment(layer, current, subpathStart, style: style)
                current = subpathStart
                continue
            }
            let end: lv_point_precise_t
            let firstControl: lv_point_precise_t
            let secondControl: lv_point_precise_t
            let segmentCount: Int
            switch element {
            case let .line(position):
                end = point(position, in: coordinates)
                firstControl = current
                secondControl = end
                segmentCount = 1
            case let .quadCurve(position, control):
                end = point(position, in: coordinates)
                let controlPoint = point(control, in: coordinates)
                firstControl = quadraticControl(from: current, toward: controlPoint)
                secondControl = quadraticControl(from: end, toward: controlPoint)
                segmentCount = 6
            case let .curve(position, control1, control2):
                end = point(position, in: coordinates)
                firstControl = point(control1, in: coordinates)
                secondControl = point(control2, in: coordinates)
                segmentCount = 6
            case .move, .closeSubpath:
                continue
            }
            var segmentStart = current
            for segment in 1...segmentCount {
                let segmentEnd = segmentCount == 1 ? end : cubicPoint(
                    current, firstControl, secondControl, end,
                    progress: Float(segment) / Float(segmentCount))
                drawSegment(layer, segmentStart, segmentEnd, style: style)
                segmentStart = segmentEnd
            }
            current = end
        }
    }

    private func drawSegment(
        _ layer: UnsafeMutablePointer<lv_layer_t>,
        _ first: lv_point_precise_t, _ second: lv_point_precise_t,
        style: StrokeStyle
    ) {
        var descriptor = lv_draw_line_dsc_t()
        lv_draw_line_dsc_init(&descriptor)
        descriptor.p1 = first
        descriptor.p2 = second
        descriptor.color = lv_color_hex(color.rgb)
        descriptor.opa = color.opacity
        descriptor.width = Int32(max(1, style.lineWidth.rounded()))
        descriptor.round_start = style.lineCap == .round ? 1 : 0
        descriptor.round_end = style.lineCap == .round ? 1 : 0
        descriptor.dash_width = Int32((style.dash.first ?? 0).rounded())
        descriptor.dash_gap = Int32((style.dash.count > 1 ? style.dash[1] : 0).rounded())
        lv_draw_line(layer, &descriptor)
    }

    private func quadraticControl(
        from start: lv_point_precise_t, toward control: lv_point_precise_t
    ) -> lv_point_precise_t {
        lv_point_precise_t(
            x: start.x + Int32((Float(control.x - start.x) * 2 / 3).rounded()),
            y: start.y + Int32((Float(control.y - start.y) * 2 / 3).rounded()))
    }

    private func cubicPoint(
        _ start: lv_point_precise_t, _ first: lv_point_precise_t,
        _ second: lv_point_precise_t, _ end: lv_point_precise_t, progress: Float
    ) -> lv_point_precise_t {
        let inverse = 1 - progress
        func coordinate(_ start: Int32, _ first: Int32, _ second: Int32, _ end: Int32) -> Int32 {
            let value = inverse * inverse * inverse * Float(start)
                + 3 * inverse * inverse * progress * Float(first)
                + 3 * inverse * progress * progress * Float(second)
                + progress * progress * progress * Float(end)
            return Int32(value.rounded())
        }
        return lv_point_precise_t(x: coordinate(start.x, first.x, second.x, end.x),
                                  y: coordinate(start.y, first.y, second.y, end.y))
    }
}

private struct LVGLPathEdge {
    let start: ShapePoint
    let end: ShapePoint
}

// Embedded adaptation: OpenSwiftUI delegates curve rasterization to a richer
// graphics stack. The LVGL adaptor flattens each curve to a fixed eight edges,
// bounding temporary storage and draw work while preserving Path fill rules.
private enum LVGLPathRasterizer {
    static func flattenedEdges(_ path: Path) -> [LVGLPathEdge] {
        var edges: [LVGLPathEdge] = []
        var current: ShapePoint?
        var subpathStart: ShapePoint?
        for element in path.elements {
            switch element {
            case let .move(point):
                closeCurrentSubpath(current, subpathStart, into: &edges)
                current = point
                subpathStart = point
            case let .line(point):
                if let current {
                    edges.append(.init(start: current, end: point))
                }

                current = point
            case let .quadCurve(point, control):
                guard let start = current else { continue }
                var segmentStart = start
                for segment in 1...8 {
                    let progress = Float(segment) / 8
                    let inverse = 1 - progress
                    let segmentEnd = ShapePoint(
                        x: inverse * inverse * start.x
                            + 2 * inverse * progress * control.x
                            + progress * progress * point.x,
                        y: inverse * inverse * start.y
                            + 2 * inverse * progress * control.y
                            + progress * progress * point.y
                    )
                    edges.append(.init(start: segmentStart, end: segmentEnd))
                    segmentStart = segmentEnd
                }
                current = point
            case let .curve(point, control1, control2):
                guard let start = current else { continue }
                var segmentStart = start
                for segment in 1...8 {
                    let progress = Float(segment) / 8
                    let inverse = 1 - progress
                    let segmentEnd = ShapePoint(
                        x: inverse * inverse * inverse * start.x
                            + 3 * inverse * inverse * progress * control1.x
                            + 3 * inverse * progress * progress * control2.x
                            + progress * progress * progress * point.x,
                        y: inverse * inverse * inverse * start.y
                            + 3 * inverse * inverse * progress * control1.y
                            + 3 * inverse * progress * progress * control2.y
                            + progress * progress * progress * point.y
                    )
                    edges.append(.init(start: segmentStart, end: segmentEnd))
                    segmentStart = segmentEnd
                }
                current = point
            case .closeSubpath:
                closeCurrentSubpath(current, subpathStart, into: &edges)
                current = subpathStart
            }
        }
        closeCurrentSubpath(current, subpathStart, into: &edges)
        return edges
    }

    private static func closeCurrentSubpath(
        _ current: ShapePoint?, _ subpathStart: ShapePoint?,
        into edges: inout [LVGLPathEdge]
    ) {
        if let current, let subpathStart, current != subpathStart {
            edges.append(.init(start: current, end: subpathStart))
        }
    }
}

/// Retains the immutable path until LVGL deletes its drawing object.
enum LVGLShapeRenderer {
    static func create(
        _ path: Path, color: Color.Resolved, style: ShapeRenderingStyle,
        size: RenderSize, parent: OpaquePointer
    ) -> OpaquePointer? {
        // Embedded adaptation: reject unusually complex paths before retaining
        // rasterizer state; standard Shapes stay within this adaptor-owned cap.
        guard path.elements.count <= 64,
           let storage = malloc(MemoryLayout<LVGLShapeContext>.stride) else {
            return nil
        }
        let context = storage.bindMemory(to: LVGLShapeContext.self, capacity: 1)
        context.initialize(to: LVGLShapeContext(path: path, color: color, style: style))
        guard let object = lv_obj_create(parent) else {
            release(context)
            return nil
        }
        lv_obj_remove_style_all(object)
        lv_obj_remove_flag(object, LV_OBJ_FLAG_SCROLLABLE)
        lv_obj_set_size(object, size.width, size.height)
        guard lv_obj_add_event_cb(object, handleShapeEvent, LV_EVENT_ALL, storage) != nil else {
            lv_obj_delete(object)
            release(context)
            return nil
        }
        return object
    }

    fileprivate static func release(_ context: UnsafeMutablePointer<LVGLShapeContext>) {
        context.deinitialize(count: 1)
        free(context)
    }
}

private func handleShapeEvent(_ event: OpaquePointer?) {
    guard let event, let storage = lv_event_get_user_data(event) else { return }
    let context = storage.assumingMemoryBound(to: LVGLShapeContext.self)
    if lv_event_get_code(event) == LV_EVENT_DELETE {
        LVGLShapeRenderer.release(context)
        return
    }
    guard lv_event_get_code(event) == LV_EVENT_DRAW_MAIN,
       let object = lv_event_get_current_target_obj(event), let layer = lv_event_get_layer(event) else {
        return
    }
    context.pointee.draw(in: object, layer: layer)
}

enum LVGLClipRenderer {
    // Embedded adaptation: custom clipping uses an A8 bitmap because LVGL has
    // no upstream-equivalent vector clip graph. Bound the temporary allocation
    // on no-PSRAM devices and fail the render instead of exhausting heap.
    private static let maximumMaskBytes = 32 * 1024

    // Embedded adaptation: the generic winding rasterizer is prohibitively
    // expensive for an antialiased ellipse on the ESP32-C3. An analytic
    // coverage test preserves the same four-sample A8 mask while removing the
    // per-sample edge traversal.
    static func applyEllipse(
        style: FillStyle,
        size: RenderSize,
        to object: OpaquePointer
    ) -> Bool {
        guard size.width > 0, size.height > 0,
           Int64(size.width) * Int64(size.height) <= Int64(maximumMaskBytes) else {
            return false
        }
        guard let drawBuffer = makeClipMask(size: size) else { return false }
        guard let data = drawBuffer.pointee.data,
           Int(drawBuffer.pointee.data_size) <= maximumMaskBytes else {
            destroyClipMask(drawBuffer)
            return false
        }
        for index in 0..<Int(drawBuffer.pointee.data_size) {
            data[index] = 0
        }
        let sampleOffsets: [(Float, Float)] = style.isAntialiased
            ? [(0.25, 0.25), (0.75, 0.25), (0.25, 0.75), (0.75, 0.75)]
            : [(0.5, 0.5)]
        let centerX = Float(size.width) / 2
        let centerY = Float(size.height) / 2
        let inverseRadiusX = 1 / centerX
        let inverseRadiusY = 1 / centerY
        let stride = Int(drawBuffer.pointee.header.stride)
        for y in 0..<Int(size.height) {
            if y > 0 && y % 16 == 0 {
                yieldDuringSoftwareRasterization()
            }
            for x in 0..<Int(size.width) {
                var coveredSamples = 0
                for sample in sampleOffsets {
                    let normalizedX = (Float(x) + sample.0 - centerX) * inverseRadiusX
                    let normalizedY = (Float(y) + sample.1 - centerY) * inverseRadiusY
                    if normalizedX * normalizedX + normalizedY * normalizedY <= 1 {
                        coveredSamples += 1
                    }
                }
                data[y * stride + x] = UInt8(coveredSamples * 255 / sampleOffsets.count)
            }
        }
        return install(drawBuffer, on: object)
    }

    static func applyCircle(
        style: FillStyle,
        size: RenderSize,
        to object: OpaquePointer
    ) -> Bool {
        guard size.width > 0, size.height > 0,
           Int64(size.width) * Int64(size.height) <= Int64(maximumMaskBytes) else {
            return false
        }
        guard let drawBuffer = makeClipMask(size: size) else { return false }
        guard let data = drawBuffer.pointee.data,
           Int(drawBuffer.pointee.data_size) <= maximumMaskBytes else {
            destroyClipMask(drawBuffer)
            return false
        }
        for index in 0..<Int(drawBuffer.pointee.data_size) {
            data[index] = 0
        }
        let sampleOffsets: [(Float, Float)] = style.isAntialiased
            ? [(0.25, 0.25), (0.75, 0.25), (0.25, 0.75), (0.75, 0.75)]
            : [(0.5, 0.5)]
        let centerX = Float(size.width) / 2
        let centerY = Float(size.height) / 2
        let radius = Float(min(size.width, size.height)) / 2
        let inverseRadius = 1 / radius
        let stride = Int(drawBuffer.pointee.header.stride)
        for y in 0..<Int(size.height) {
            if y > 0 && y % 16 == 0 {
                yieldDuringSoftwareRasterization()
            }
            for x in 0..<Int(size.width) {
                var coveredSamples = 0
                for sample in sampleOffsets {
                    let normalizedX = (Float(x) + sample.0 - centerX) * inverseRadius
                    let normalizedY = (Float(y) + sample.1 - centerY) * inverseRadius
                    if normalizedX * normalizedX + normalizedY * normalizedY <= 1 {
                        coveredSamples += 1
                    }
                }
                data[y * stride + x] = UInt8(coveredSamples * 255 / sampleOffsets.count)
            }
        }
        return install(drawBuffer, on: object)
    }

    static func apply(
        _ path: Path,
        style: FillStyle,
        size: RenderSize,
        to object: OpaquePointer
    ) -> Bool {
        guard size.width > 0, size.height > 0,
           Int64(size.width) * Int64(size.height) <= Int64(maximumMaskBytes) else {
            return false
        }
        guard let drawBuffer = makeClipMask(size: size) else { return false }
        guard let data = drawBuffer.pointee.data,
           Int(drawBuffer.pointee.data_size) <= maximumMaskBytes else {
            destroyClipMask(drawBuffer)
            return false
        }
        for index in 0..<Int(drawBuffer.pointee.data_size) {
            data[index] = 0
        }

        let edges = LVGLPathRasterizer.flattenedEdges(path)
        guard !edges.isEmpty else {
            destroyClipMask(drawBuffer)
            return false
        }
        let sampleOffsets: [(Float, Float)] = style.isAntialiased
            ? [(0.25, 0.25), (0.75, 0.25), (0.25, 0.75), (0.75, 0.75)]
            : [(0.5, 0.5)]
        let stride = Int(drawBuffer.pointee.header.stride)
        for y in 0..<Int(size.height) {
            if y > 0 && y % 16 == 0 {
                yieldDuringSoftwareRasterization()
            }
            for x in 0..<Int(size.width) {
                var coveredSamples = 0
                for sample in sampleOffsets where contains(
                    ShapePoint(x: Float(x) + sample.0, y: Float(y) + sample.1),
                    edges: edges,
                    evenOdd: style.isEOFilled
                ) {
                    coveredSamples += 1
                }
                data[y * stride + x] = UInt8(coveredSamples * 255 / sampleOffsets.count)
            }
        }
        return install(drawBuffer, on: object)
    }

    private static func install(
        _ drawBuffer: UnsafeMutablePointer<lv_draw_buf_t>,
        on object: OpaquePointer
    ) -> Bool {
        lv_draw_buf_flush_cache(drawBuffer, nil)
        lv_obj_set_style_bitmap_mask_src(object, UnsafeRawPointer(drawBuffer), 0)
        guard lv_obj_add_event_cb(
            object, releaseClipMask, LV_EVENT_DELETE, UnsafeMutableRawPointer(drawBuffer)
        ) != nil else {
            lv_obj_set_style_bitmap_mask_src(object, nil, 0)
            destroyClipMask(drawBuffer)
            return false
        }
        return true
    }

    private static func makeClipMask(
        size: RenderSize
    ) -> UnsafeMutablePointer<lv_draw_buf_t>? {
        let stride = Int(lv_draw_buf_width_to_stride(UInt32(size.width), LV_COLOR_FORMAT_A8))
        let byteCount = stride * Int(size.height)
        guard byteCount > 0, byteCount <= maximumMaskBytes,
           let pixels = malloc(byteCount) else {
            return nil
        }
        let drawBuffer = UnsafeMutablePointer<lv_draw_buf_t>.allocate(capacity: 1)
        guard lv_draw_buf_init(
            drawBuffer,
            UInt32(size.width),
            UInt32(size.height),
            LV_COLOR_FORMAT_A8,
            UInt32(stride),
            pixels,
            UInt32(byteCount)
        ) == LV_RESULT_OK else {
            drawBuffer.deallocate()
            free(pixels)
            return nil
        }
        return drawBuffer
    }

    private static func contains(
        _ point: ShapePoint,
        edges: [LVGLPathEdge],
        evenOdd: Bool
    ) -> Bool {
        var crossings = 0
        var winding = 0
        for edge in edges {
            let start = edge.start
            let end = edge.end
            guard (start.y <= point.y && end.y > point.y)
                    || (end.y <= point.y && start.y > point.y) else { continue }
            let intersectionX = start.x
                + (point.y - start.y) * (end.x - start.x) / (end.y - start.y)
            guard intersectionX > point.x else { continue }
            crossings += 1
            winding += end.y > start.y ? 1 : -1
        }
        return evenOdd ? crossings % 2 == 1 : winding != 0
    }
}

private func releaseClipMask(_ event: OpaquePointer?) {
    guard let event, lv_event_get_code(event) == LV_EVENT_DELETE,
       let storage = lv_event_get_user_data(event) else {
        return
    }
    destroyClipMask(storage.assumingMemoryBound(to: lv_draw_buf_t.self))
}

private func destroyClipMask(_ drawBuffer: UnsafeMutablePointer<lv_draw_buf_t>) {
    if let pixels = drawBuffer.pointee.unaligned_data {
        free(pixels)
    }
    drawBuffer.deallocate()
}
