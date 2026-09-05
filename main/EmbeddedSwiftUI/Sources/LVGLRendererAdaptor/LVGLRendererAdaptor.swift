import EmbeddedSwiftUI

// Keep resized image pixels outside LVGL's fixed 48 KiB allocator. A native
// RGB565 image with no transform can use LVGL's bounded scanline radius path,
// while a scaled image bypasses that path and loses clip-radius handling.
private let maximumResizedImageBytes = 32 * 1024

private func makeResizedRGB565Image(
    source: UnsafeRawPointer,
    sourceSize: EmbeddedSize,
    targetSize: RenderSize
) -> UnsafeMutablePointer<lv_image_dsc_t>? {
    guard sourceSize.width != targetSize.width || sourceSize.height != targetSize.height,
       sourceSize.width > 0, sourceSize.height > 0,
       targetSize.width > 0, targetSize.height > 0 else {
        return nil
    }

    let sourceDescriptor = source.assumingMemoryBound(to: lv_image_dsc_t.self)
    let colorFormat = sourceDescriptor.pointee.header.cf
    let rgb565 = UInt32(LV_COLOR_FORMAT_RGB565.rawValue)
    let swappedRGB565 = UInt32(LV_COLOR_FORMAT_RGB565_SWAPPED.rawValue)
    guard sourceDescriptor.pointee.header.magic == UInt32(LV_IMAGE_HEADER_MAGIC),
       colorFormat == rgb565 || colorFormat == swappedRGB565,
       let sourcePixels = sourceDescriptor.pointee.data else {
        return nil
    }

    let sourceWidth = Int(sourceSize.width)
    let sourceHeight = Int(sourceSize.height)
    let targetWidth = Int(targetSize.width)
    let targetHeight = Int(targetSize.height)
    let sourceStride = Int(sourceDescriptor.pointee.header.stride)
    let targetStride = targetWidth * 2
    let targetByteCount = targetStride * targetHeight
    guard sourceStride >= sourceWidth * 2,
       Int(sourceDescriptor.pointee.data_size) >= sourceStride * sourceHeight,
       targetByteCount <= maximumResizedImageBytes,
       let storage = malloc(targetByteCount) else {
        return nil
    }

    let targetPixels = storage.assumingMemoryBound(to: UInt8.self)
    for targetY in 0..<targetHeight {
        if targetY > 0 && targetY % 16 == 0 {
            yieldDuringSoftwareRasterization()
        }
        let sourceY = targetY * sourceHeight / targetHeight
        let sourceRowOffset = sourceY * sourceStride
        let targetRowOffset = targetY * targetStride
        for targetX in 0..<targetWidth {
            let sourceX = targetX * sourceWidth / targetWidth
            let sourceIndex = sourceRowOffset + sourceX * 2
            let targetIndex = targetRowOffset + targetX * 2
            targetPixels[targetIndex] = sourcePixels[sourceIndex]
            targetPixels[targetIndex + 1] = sourcePixels[sourceIndex + 1]
        }
    }

    let descriptor = UnsafeMutablePointer<lv_image_dsc_t>.allocate(capacity: 1)
    memset(descriptor, 0, MemoryLayout<lv_image_dsc_t>.stride)
    descriptor.pointee.header.magic = UInt32(LV_IMAGE_HEADER_MAGIC)
    descriptor.pointee.header.cf = colorFormat
    descriptor.pointee.header.w = UInt32(targetWidth)
    descriptor.pointee.header.h = UInt32(targetHeight)
    descriptor.pointee.header.stride = UInt32(targetStride)
    descriptor.pointee.data_size = UInt32(targetByteCount)
    descriptor.pointee.data = UnsafePointer(targetPixels)
    return descriptor
}

private func destroyResizedRGB565Image(
    _ descriptor: UnsafeMutablePointer<lv_image_dsc_t>
) {
    if let pixels = descriptor.pointee.data {
        free(UnsafeMutableRawPointer(mutating: pixels))
    }
    descriptor.deallocate()
}

private func releaseResizedRGB565Image(_ event: OpaquePointer?) {
    guard let event, lv_event_get_code(event) == LV_EVENT_DELETE,
       let storage = lv_event_get_user_data(event) else {
        return
    }
    destroyResizedRGB565Image(storage.assumingMemoryBound(to: lv_image_dsc_t.self))
}

func lvglOpacityComponent(_ value: Double) -> UInt8 {
    if value.isNaN || value <= 0 {
        return 0
    }
    if value >= 1 {
        return 255
    }
    return UInt8(value * 255 + 0.5)
}

private func refreshOverflowDrawSize(_ event: OpaquePointer?) {
    guard let event,
       let object = lv_event_get_current_target_obj(event),
       let display = lv_obj_get_display(object) else {
        return
    }
    lv_event_set_ext_draw_size(
        event,
        max(
            lv_display_get_horizontal_resolution(display),
            lv_display_get_vertical_resolution(display)
        )
    )
}

private func refreshLayerOverflowDrawSize(_ event: OpaquePointer?) {
    guard let event, let object = lv_event_get_current_target_obj(event) else {
        return
    }
    var objectBounds = lv_area_t()
    lv_obj_get_coords(object, &objectBounds)
    var subtreeBounds = objectBounds
    includeOverflowBounds(ofChildrenOf: object, in: &subtreeBounds)
    let horizontalExtension = max(
        objectBounds.x1 - subtreeBounds.x1,
        subtreeBounds.x2 - objectBounds.x2
    )
    let verticalExtension = max(
        objectBounds.y1 - subtreeBounds.y1,
        subtreeBounds.y2 - objectBounds.y2
    )
    let extensionSize = max(0, max(horizontalExtension, verticalExtension))
    lv_event_set_ext_draw_size(event, extensionSize)
}

private func includeOverflowBounds(
    ofChildrenOf object: OpaquePointer,
    in bounds: inout lv_area_t
) {
    for index in 0..<lv_obj_get_child_count(object) {
        guard let child = lv_obj_get_child(object, Int32(index)) else { continue }
        var childBounds = lv_area_t()
        lv_obj_get_coords(child, &childBounds)
        let intrinsicExtension = lv_obj_calculate_ext_draw_size(child, LV_PART_MAIN)
        lv_area_increase(&childBounds, intrinsicExtension, intrinsicExtension)
        if lv_obj_has_flag(child, LV_OBJ_FLAG_OVERFLOW_VISIBLE) {
            includeOverflowBounds(ofChildrenOf: child, in: &childBounds)
        }
        lv_obj_get_transformed_area(child, &childBounds, LV_OBJ_POINT_TRANSFORM_FLAG_NONE)
        bounds.x1 = min(bounds.x1, childBounds.x1)
        bounds.y1 = min(bounds.y1, childBounds.y1)
        bounds.x2 = max(bounds.x2, childBounds.x2)
        bounds.y2 = max(bounds.y2, childBounds.y2)
    }
}

/// Owns the LVGL screen and the mounted EmbeddedSwiftUI subtree.
///
/// Call all methods from the LVGL task or while holding `bsp_lvgl_lock()`.
public final class LVGLHostingController<Content: View> {
    private let display: OpaquePointer
    private let safeAreaInsets: EdgeInsets
    private let centersRootView: Bool
    private let viewHost: EmbeddedViewHost<Content>
    private var screen: OpaquePointer?
    private var contentRoot: OpaquePointer?
    private var renderedDisplaySize: EmbeddedSize?
    private var renderer: _DisplayListRenderer<LVGLRenderBackend>

    public init(
        display: OpaquePointer,
        safeAreaInsets: EdgeInsets = .init(),
        centersRootView: Bool = true,
        configuration: RendererConfiguration? = nil,
        imageResolver: @escaping (String) -> UnsafeRawPointer? = { _ in nil },
        @ViewBuilder rootView: () -> Content
    ) {
        self.display = display
        self.safeAreaInsets = safeAreaInsets
        self.centersRootView = centersRootView
        renderer = _DisplayListRenderer(backend: LVGLRenderBackend(
            configuration: configuration ?? LVGLRenderBackend.defaultConfiguration,
            imageResolver: imageResolver
        ))
        viewHost = EmbeddedViewHost(content: rootView)
    }

    public convenience init(
        display: OpaquePointer,
        safeAreaInsets: EdgeInsets = .init(),
        centersRootView: Bool = true,
        rootView: Content
    ) {
        self.init(
            display: display,
            safeAreaInsets: safeAreaInsets,
            centersRootView: centersRootView
        ) {
            rootView
        }
    }

    /// Reading this from the application tick also detects logical display
    /// resolution changes without a platform-specific fixed screen size.
    public var needsRender: Bool {
        viewHost.needsRender || renderedDisplaySize != logicalDisplaySize
    }

    @discardableResult
    public func present() -> Bool {
        guard screen == nil else { return false }
        let previousDisplay = lv_display_get_default()
        lv_display_set_default(display)
        defer {
            lv_display_set_default(previousDisplay)
        }
        guard let nextScreen = lv_obj_create(nil) else { return false }
        guard let nextContentRoot = lv_obj_create(nextScreen) else {
            lv_obj_delete(nextScreen)
            return false
        }
        lv_obj_remove_style_all(nextScreen)
        lv_obj_set_style_bg_color(nextScreen, lv_color_hex(0x000000), 0)
        lv_obj_set_style_bg_opa(nextScreen, 255, 0)
        lv_obj_remove_style_all(nextContentRoot)
        lv_obj_remove_flag(nextContentRoot, LV_OBJ_FLAG_SCROLLABLE)
        screen = nextScreen
        contentRoot = nextContentRoot
        guard render() else {
            screen = nil
            contentRoot = nil
            lv_obj_delete(nextScreen)
            return false
        }
        lv_screen_load(nextScreen)
        lv_refr_now(display)
        bsp_display_backlight(100)
        return true
    }

    @discardableResult
    public func handlePhysicalButton(_ button: PhysicalButton) -> Bool {
        guard processPhysicalButton(button) else { return false }
        guard viewHost.needsRender else { return true }
        return render()
    }

    @discardableResult
    package func processPhysicalButton(_ button: PhysicalButton) -> Bool {
        guard screen != nil else { return false }
        return renderer.handlePhysicalButton(button)
    }

    @discardableResult
    public func render(transaction: Transaction = Transaction()) -> Bool {
        guard let screen, let contentRoot, let displaySize = logicalDisplaySize else {
            return false
        }
        guard safeAreaInsets.leading + safeAreaInsets.trailing <= displaySize.width,
              safeAreaInsets.top + safeAreaInsets.bottom <= displaySize.height else {
            return false
        }
        let rootGeometry = RootGeometry(
            screenSize: displaySize,
            safeAreaInsets: safeAreaInsets,
            centersRootView: centersRootView
        )
        let contentBounds = rootGeometry.contentBounds
        lv_obj_set_size(screen, displaySize.width, displaySize.height)
        lv_obj_set_pos(contentRoot, contentBounds.x, contentBounds.y)
        lv_obj_set_size(contentRoot, contentBounds.width, contentBounds.height)
        let revision = viewHost.currentRevision
        let transaction = viewHost.transactionForUpdate(transaction)
        var outputs = viewHost.makeViewOutputs(
            transaction: transaction, configuration: renderer.configuration
        )
        guard renderer.render(
            &outputs,
            in: contentRoot,
            rootGeometry: rootGeometry,
            transaction: transaction
        ) else {
            return false
        }
        viewHost.acknowledgeRender(startedAt: revision)
        renderedDisplaySize = displaySize
        return true
    }

    public func unmount() {
        renderer.unmount()
        viewHost.unmount()
        if let screen {
            lv_obj_delete(screen)
            self.screen = nil
        }
        contentRoot = nil
        renderedDisplaySize = nil
    }

    private var logicalDisplaySize: EmbeddedSize? {
        let width = lv_display_get_horizontal_resolution(display)
        let height = lv_display_get_vertical_resolution(display)
        guard (1...32767).contains(width), (1...32767).contains(height) else {
            return nil
        }
        return EmbeddedSize(width: width, height: height)
    }
}

public final class LVGLTimer {
    private var opaquePointer: OpaquePointer?

    public init?(period: UInt32, callback: @escaping () -> Void) {
        guard let timer = lv_timer_create(lvglTimerCallback, period, nil) else { return nil }
        opaquePointer = timer
        activeLVGLTimerCallbacks.append(
            LVGLTimerCallbackRegistration(timer: timer, callback: callback)
        )
    }

    public func invalidate() {
        guard let opaquePointer else { return }
        activeLVGLTimerCallbacks.removeAll { $0.timer == opaquePointer }
        lv_timer_delete(opaquePointer)
        self.opaquePointer = nil
    }

    deinit {
        invalidate()
    }
}

private func lvglTimerCallback(_ timer: OpaquePointer?) {
    guard let timer else { return }
    guard let registration = activeLVGLTimerCallbacks.first(where: { $0.timer == timer }) else {
        return
    }
    withExtendedLifetime(registration) {
        registration.callback()
    }
}

private final class LVGLTimerCallbackRegistration {
    let timer: OpaquePointer
    let callback: () -> Void

    init(timer: OpaquePointer, callback: @escaping () -> Void) {
        self.timer = timer
        self.callback = callback
    }
}

private var activeLVGLTimerCallbacks: [LVGLTimerCallbackRegistration] = []

package struct LVGLLayoutProvider: RendererProvider {
    package let configuration: RendererConfiguration
    private let imageResolver: (String) -> UnsafeRawPointer?

    package init(
        configuration: RendererConfiguration,
        imageResolver: @escaping (String) -> UnsafeRawPointer?
    ) {
        self.configuration = configuration
        self.imageResolver = imageResolver
    }

    package func measureText(
        _ text: String,
        environment: RenderEnvironment,
        proposal: ProposedViewSize
    ) -> EmbeddedSize {
        var size = lv_point_t()
        text.withCString {
            lv_text_get_size(
                &size,
                $0,
                LVGLFont.pointer(
                    pointSize: (environment.font ?? configuration.defaultFont).pointSize
                ),
                0,
                0,
                max(1, proposal.width ?? configuration.maximumDimension),
                LV_TEXT_FLAG_NONE
            )
        }
        return EmbeddedSize(width: max(0, size.x), height: max(0, size.y))
    }

    package func imageSize(named name: String) -> EmbeddedSize? {
        guard let source = imageResolver(name) else { return nil }
        var header = lv_image_header_t()
        guard lv_image_decoder_get_info(source, &header) == LV_RESULT_OK else { return nil }
        return EmbeddedSize(width: Int32(header.w), height: Int32(header.h))
    }
}

/// Maps platform-independent render operations onto LVGL objects.
package struct LVGLRenderBackend: _DisplayListRenderBackend {
    public typealias Node = OpaquePointer

    private struct ZIndexEntry {
        let node: Node
        let value: Double
    }

    private final class NodeTransaction {
        let value: Transaction

        init(_ value: Transaction) {
            self.value = value
        }
    }

    private var zIndexEntries: [ZIndexEntry] = []
    private var nodeIdentities: [Node: LVGLNodeIdentity] = [:]
    // Embedded adaptation: Transaction occupies 80 bytes on ESP32-C3. Store
    // references to equal resolved values so dictionary growth stays small.
    private var nodeTransactions: [Node: NodeTransaction] = [:]
    private var renderTransactions: [NodeTransaction] = []
    package let configuration: RendererConfiguration
    private let imageResolver: (String) -> UnsafeRawPointer?
    private var nextChildIndices: [Node: Int] = [:]
    private var nextRootIndex = 0

    // Embedded adaptation: layout needs metrics but not mutable node maps.
    // Copying the complete backend kept three large Dictionary buffers shared
    // and forced an OOM-inducing COW copy during the next mount.
    package var layoutProvider: LVGLLayoutProvider {
        LVGLLayoutProvider(
            configuration: configuration,
            imageResolver: imageResolver
        )
    }

    // Embedded adaptation: OpenSwiftUI obtains these values from platform glue
    // and graph configuration. Keep conservative no-PSRAM defaults in the
    // adaptor; callers can replace every metric and resource limit.
    public static var defaultConfiguration: RendererConfiguration {
        RendererConfiguration(
            maximumNodes: 64, maximumDepth: 16, maximumDimension: 32767,
            defaultSpacing: 8, defaultPadding: EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8),
            listSpacing: 6, defaultFont: .body, defaultForegroundColor: .white,
            implicitRootLayout: VStackLayout(),
            systemColor: { LVGLSystemColorDefinition.value(for: $0, environment: EnvironmentValues()) }
        )
    }

    public init(
        configuration: RendererConfiguration = Self.defaultConfiguration,
        imageResolver: @escaping (String) -> UnsafeRawPointer? = { _ in nil }
    ) {
        self.configuration = configuration
        self.imageResolver = imageResolver
    }

    package func measureText(
        _ text: String, environment: RenderEnvironment, proposal: ProposedViewSize
    ) -> EmbeddedSize {
        layoutProvider.measureText(
            text,
            environment: environment,
            proposal: proposal
        )
    }

    package func imageSize(named name: String) -> EmbeddedSize? {
        layoutProvider.imageSize(named: name)
    }

    package mutating func configure(_ node: Node, item: DisplayList.Item) {
        lv_obj_set_pos(node, item.frame.x, item.frame.y)
        lv_obj_set_size(node, item.frame.width, item.frame.height)
        if let previous = nodeIdentities[node] {
            nodeIdentities[node] = LVGLNodeIdentity(identity: item.identity, kind: previous.kind)
        }
        if let transaction = renderTransactions.first(where: { $0.value == item.transaction }) {
            nodeTransactions[node] = transaction
        } else {
            let transaction = NodeTransaction(item.transaction)
            renderTransactions.append(transaction)
            nodeTransactions[node] = transaction
        }
        setTraits(item.traits, of: node)
        lv_obj_invalidate(node)
    }

    package mutating func makeImage(_ name: String, size: RenderSize, parent: Node) -> Node? {
        guard let source = imageResolver(name),
              let intrinsic = imageSize(named: name),
              intrinsic.width > 0, intrinsic.height > 0,
              let node = lv_image_create(parent) else { return nil }
        if let resizedSource = makeResizedRGB565Image(
            source: source,
            sourceSize: intrinsic,
            targetSize: size
        ) {
            guard lv_obj_add_event_cb(
                node,
                releaseResizedRGB565Image,
                LV_EVENT_DELETE,
                UnsafeMutableRawPointer(resizedSource)
            ) != nil else {
                destroyResizedRGB565Image(resizedSource)
                lv_obj_delete(node)
                return nil
            }
            lv_image_set_src(node, UnsafeRawPointer(resizedSource))
        } else {
            lv_image_set_src(node, source)
            lv_image_set_pivot(node, 0, 0)
            lv_image_set_scale_x(node, UInt32(max(1, size.width * 256 / intrinsic.width)))
            lv_image_set_scale_y(node, UInt32(max(1, size.height * 256 / intrinsic.height)))
        }
        registerIdentity(of: node, parent: parent, kind: .image)
        return node
    }

    public mutating func beginRender() {
        nextChildIndices.removeAll(keepingCapacity: true)
        nextRootIndex = 0
        renderTransactions.removeAll(keepingCapacity: true)
    }

    public mutating func makeContainer(
        _ layout: ContainerLayout,
        proposedSize: RenderSize,
        parent: Node
    ) -> Node? {
        guard let node = lv_obj_create(parent) else { return nil }
        lv_obj_remove_style_all(node)
        lv_obj_remove_flag(node, LV_OBJ_FLAG_SCROLLABLE)
        lv_obj_add_flag(node, LV_OBJ_FLAG_OVERFLOW_VISIBLE)
        lv_obj_set_size(node, proposedSize.width, proposedSize.height)
        switch layout {
        case .stack:
            break
        case .overlay:
            break
        case let .scroll(axes, showsIndicators, _):
            lv_obj_set_size(node, proposedSize.width, proposedSize.height)
            lv_obj_add_flag(node, LV_OBJ_FLAG_SCROLLABLE)
            lv_obj_remove_flag(node, LV_OBJ_FLAG_OVERFLOW_VISIBLE)
            lv_obj_remove_flag(node, LV_OBJ_FLAG_SCROLL_ELASTIC)
            lv_obj_remove_flag(node, LV_OBJ_FLAG_SCROLL_MOMENTUM)
            lv_obj_remove_flag(node, LV_OBJ_FLAG_SCROLL_CHAIN_HOR)
            lv_obj_remove_flag(node, LV_OBJ_FLAG_SCROLL_CHAIN_VER)
            let direction: lv_dir_t
            if axes == [.horizontal, .vertical] {
                direction = LV_DIR_ALL
            } else if axes.contains(.vertical) {
                direction = LV_DIR_VER
            } else if axes.contains(.horizontal) {
                direction = LV_DIR_HOR
            } else {
                direction = LV_DIR_NONE
            }
            lv_obj_set_scroll_dir(node, direction)
            lv_obj_set_scrollbar_mode(
                node,
                showsIndicators ? LV_SCROLLBAR_MODE_AUTO : LV_SCROLLBAR_MODE_OFF
            )
            lv_obj_set_style_bg_color(
                node,
                lv_color_hex(0x6EE7B7),
                UInt32(LV_PART_SCROLLBAR.rawValue)
            )
            lv_obj_set_style_bg_opa(node, 255, UInt32(LV_PART_SCROLLBAR.rawValue))

        case let .frame(width, height, _):
            if let width {
                lv_obj_set_width(node, width)
            }

            if let height {
                lv_obj_set_height(node, height)
            }

        case .padding, .defaultPadding, .secondaryBackground:
            break
        case let .background(color):
            let resolved = color.resolve(in: configuration)
            lv_obj_set_style_bg_color(node, lv_color_hex(resolved.rgb), 0)
            lv_obj_set_style_bg_opa(node, resolved.opacity, 0)
        case .offset:
            break
        case let .opacity(opacity):
            lv_obj_set_style_opa_layered(node, lvglOpacityComponent(opacity), 0)
        case .scale:
            break
        case .rotation, .projection:
            break
        case let .color(color):
            let resolved = color.resolve(in: configuration)
            lv_obj_set_size(node, proposedSize.width, proposedSize.height)
            lv_obj_set_style_bg_color(node, lv_color_hex(resolved.rgb), 0)
            lv_obj_set_style_bg_opa(node, resolved.opacity, 0)
        case .clip:
            lv_obj_remove_flag(node, LV_OBJ_FLAG_OVERFLOW_VISIBLE)
        case .spacer:
            break
        case .layout:
            lv_obj_set_size(node, proposedSize.width, proposedSize.height)
        }
        registerIdentity(of: node, parent: parent, kind: identityKind(of: layout))
        if case .scroll = layout {
            return node
        }

        if case .clip = layout {
            return node
        }

        let registeredOverflowCallback: Bool
        if case .scale = layout {
            registeredOverflowCallback = lv_obj_add_event_cb(
                node,
                refreshLayerOverflowDrawSize,
                LV_EVENT_REFR_EXT_DRAW_SIZE,
                nil
            ) != nil
        } else if case .rotation = layout {
            registeredOverflowCallback = lv_obj_add_event_cb(
                node,
                refreshLayerOverflowDrawSize,
                LV_EVENT_REFR_EXT_DRAW_SIZE,
                nil
            ) != nil
        } else if case .opacity = layout {
            registeredOverflowCallback = lv_obj_add_event_cb(
                node,
                refreshLayerOverflowDrawSize,
                LV_EVENT_REFR_EXT_DRAW_SIZE,
                nil
            ) != nil
        } else {
            registeredOverflowCallback = lv_obj_add_event_cb(
                node,
                refreshOverflowDrawSize,
                LV_EVENT_REFR_EXT_DRAW_SIZE,
                nil
            ) != nil
        }
        guard registeredOverflowCallback else {
            nodeIdentities.removeValue(forKey: node)
            lv_obj_delete(node)
            return nil
        }
        lv_obj_refresh_ext_draw_size(node)
        return node
    }

    public mutating func finishContainer(_ node: Node, layout: ContainerLayout) -> Bool {
        switch layout {
        case .frame, .overlay:
            break
        case let .offset(x, y):
            lv_obj_update_layout(node)
            let width = lv_obj_get_width(node)
            let height = lv_obj_get_height(node)
            lv_obj_set_size(node, width, height)
            for index in 0..<lv_obj_get_child_count(node) {
                if let child = lv_obj_get_child(node, Int32(index)) {
                    lv_obj_set_style_translate_x(child, x, 0)
                    lv_obj_set_style_translate_y(child, y, 0)
                }
            }
        case let .scale(x, y, anchor):
            // Embedded adaptation: LVGL's software layer skips negative
            // scales. Reject unsupported reflection instead of committing an
            // invisible tree; a zero scale deliberately draws nothing.
            guard x.isFinite, y.isFinite, x >= 0, y >= 0, x <= 127, y <= 127 else { return false }
            lv_obj_update_layout(node)
            lv_obj_set_style_transform_pivot_x(
                node,
                Int32((Double(lv_obj_get_width(node)) * anchor.x).rounded()),
                0
            )
            lv_obj_set_style_transform_pivot_y(
                node,
                Int32((Double(lv_obj_get_height(node)) * anchor.y).rounded()),
                0
            )
            lv_obj_set_style_transform_scale_x(node, Int32((x * 256).rounded()), 0)
            lv_obj_set_style_transform_scale_y(node, Int32((y * 256).rounded()), 0)
            lv_obj_refresh_ext_draw_size(node)
        case let .projection(transform):
            // Embedded adaptation: LVGL exposes translation, orthogonal scale,
            // and rotation, but no perspective or shear matrix. Accept exactly
            // the decomposable affine subset and report failure for the rest.
            guard transform.isAffine else { return false }
            let scaleX = (transform.m11 * transform.m11 + transform.m12 * transform.m12).squareRoot()
            let scaleY = (transform.m21 * transform.m21 + transform.m22 * transform.m22).squareRoot()
            let dot = transform.m11 * transform.m21 + transform.m12 * transform.m22
            guard scaleX.isFinite, scaleY.isFinite, scaleX <= 127, scaleY <= 127,
                  abs(dot) < 0.000001,
                  transform.m31.isFinite, transform.m32.isFinite,
                  abs(transform.m31) <= Double(configuration.maximumDimension),
                  abs(transform.m32) <= Double(configuration.maximumDimension) else { return false }
            let determinant = transform.m11 * transform.m22 - transform.m12 * transform.m21
            guard determinant >= 0 else { return false }
            lv_obj_set_style_transform_pivot_x(node, 0, 0)
            lv_obj_set_style_transform_pivot_y(node, 0, 0)
            lv_obj_set_style_transform_scale_x(node, Int32((scaleX * 256).rounded()), 0)
            lv_obj_set_style_transform_scale_y(node, Int32((scaleY * (determinant < 0 ? -256 : 256)).rounded()), 0)
            lv_obj_set_style_transform_rotation(
                node, lvglRotation(.radians(atan2(transform.m12, transform.m11))), 0
            )
            lv_obj_set_style_translate_x(node, Int32(transform.m31.rounded()), 0)
            lv_obj_set_style_translate_y(node, Int32(transform.m32.rounded()), 0)
            lv_obj_refresh_ext_draw_size(node)
        case let .rotation(angle, anchor):
            lv_obj_update_layout(node)
            lv_obj_set_style_transform_pivot_x(
                node,
                Int32((Double(lv_obj_get_width(node)) * anchor.x).rounded()),
                0
            )
            lv_obj_set_style_transform_pivot_y(
                node,
                Int32((Double(lv_obj_get_height(node)) * anchor.y).rounded()),
                0
            )
            lv_obj_set_style_transform_rotation(node, lvglRotation(angle), 0)
            lv_obj_refresh_ext_draw_size(node)
        case .opacity:
            lv_obj_update_layout(node)
            lv_obj_refresh_ext_draw_size(node)
        case let .clip(shape, style):
            lv_obj_update_layout(node)
            let size = RenderSize(width: lv_obj_get_width(node), height: lv_obj_get_height(node))
            let rect = ShapeRect(
                width: Float(size.width),
                height: Float(size.height)
            )
            let path = shape.path(in: rect)
            let radius = clipRadius(for: path, size: size)
            let isFullCircle = size.width == size.height
                && radius == size.width / 2
            if path == Circle().path(in: rect) || isFullCircle {
                guard applyCircleClip(node, style: style, size: size) else { return false }
            } else if let radius {
                if radius > 0 {
                    lv_obj_set_style_radius(node, radius, 0)
                    lv_obj_set_style_clip_corner(node, true, 0)
                }
            } else if path == Ellipse().path(in: rect) {
                guard LVGLClipRenderer.applyEllipse(
                    style: style,
                    size: size,
                    to: node
                ) else {
                    return false
                }
            } else if !LVGLClipRenderer.apply(path, style: style, size: size, to: node) {
                return false
            }
        case .layout:
            sortOverlappingChildren(of: node)
        default:
            break
        }
        if case .overlay = layout {
            sortOverlappingChildren(of: node)
        } else {
            discardZIndices(ofChildrenOf: node)
        }
        lv_obj_update_layout(node)
        return true
    }

    public mutating func makeText(
        _ content: String,
        environment: RenderEnvironment,
        parent: Node
    ) -> Node? {
        guard let node = lv_label_create(parent) else { return nil }
        lv_obj_remove_flag(node, LV_OBJ_FLAG_SCROLLABLE)
        let foreground = (environment.foregroundColor ?? configuration.defaultForegroundColor)
            .resolve(in: configuration)
        lv_obj_set_style_text_color(node, lv_color_hex(foreground.rgb), 0)
        lv_obj_set_style_text_opa(node, foreground.opacity, 0)
        lv_obj_set_style_text_font(node, LVGLFont.pointer(pointSize: (environment.font ?? configuration.defaultFont).pointSize), 0)
        content.withCString { lv_label_set_text(node, $0) }
        registerIdentity(of: node, parent: parent, kind: .text)
        return node
    }

    public mutating func makeShape(
        _ path: Path,
        color: Color,
        style: ShapeRenderingStyle,
        size: RenderSize,
        parent: Node
    ) -> Node? {
        guard let node = LVGLShapeRenderer.create(
            path,
            color: color.resolve(in: configuration),
            style: style,
            size: size,
            parent: parent
        ) else {
            return nil
        }
        registerIdentity(of: node, parent: parent, kind: .shape)
        return node
    }

    public func scrollOffset(of node: Node) -> ScrollOffset {
        lv_obj_update_layout(node)
        return ScrollOffset(x: lv_obj_get_scroll_x(node), y: lv_obj_get_scroll_y(node))
    }

    public func setScrollOffset(_ offset: ScrollOffset, of node: Node) {
        lv_obj_update_layout(node)
        let maximumX = max(0, lv_obj_get_scroll_x(node) + lv_obj_get_scroll_right(node))
        let maximumY = max(0, lv_obj_get_scroll_y(node) + lv_obj_get_scroll_bottom(node))
        lv_obj_scroll_to(
            node,
            min(maximumX, max(0, offset.x)),
            min(maximumY, max(0, offset.y)),
            false
        )
    }

    public mutating func setTraits(_ traits: ViewTraitCollection, of node: Node) {
        zIndexEntries.append(ZIndexEntry(node: node, value: traits.zIndex))
    }

    public mutating func remove(_ node: Node) {
        zIndexEntries.removeAll(keepingCapacity: true)
        removeIdentities(in: node)
        lv_obj_delete(node)
    }

    public mutating func removeAll(from root: Node) {
        zIndexEntries.removeAll(keepingCapacity: true)
        nodeIdentities.removeAll(keepingCapacity: true)
        nodeTransactions.removeAll(keepingCapacity: true)
        renderTransactions.removeAll(keepingCapacity: true)
        LVGLAnimation.removeTree(root)
    }

    public mutating func replace(_ previous: Node?, with next: Node, animation: Animation?) {
        guard let previous else { return }
        let previousNodes = nodes(in: previous)
        replaceItems(previous, with: next)
        // Embedded adaptation: the previous implementation rebuilt the
        // shared dictionaries after every replacement, forcing COW copies on
        // the no-PSRAM target. Collect stale keys before animation lookup, then
        // prune them in place after the lookup snapshots leave scope.
        for node in previousNodes {
            nodeIdentities.removeValue(forKey: node)
            nodeTransactions.removeValue(forKey: node)
        }
    }

    private func replaceItems(_ previous: Node, with next: Node) {
        let identities = nodeIdentities
        let transactions = nodeTransactions
        LVGLAnimation.replaceItems(
            previous, with: next,
            identityOf: { identities[$0] },
            transactionOf: { transactions[$0]?.value ?? Transaction() }
        )
    }

    private mutating func sortOverlappingChildren(of parent: Node) {
        let childCount = Int(lv_obj_get_child_count(parent))
        guard childCount > 0 else { return }
        var children: [Node] = []
        children.reserveCapacity(childCount)
        for index in 0..<childCount {
            if let child = lv_obj_get_child(parent, Int32(index)) {
                children.append(child)
            }
        }
        if children.count > 1 {
            for end in 1..<children.count {
                var index = end
                while index > 0,
                      zIndex(of: children[index]) < zIndex(of: children[index - 1]) {
                    children.swapAt(index, index - 1)
                    index -= 1
                }
            }
            for index in children.indices {
                lv_obj_move_to_index(children[index], Int32(index))
            }
        }
        zIndexEntries.removeAll { entry in
            children.contains { $0 == entry.node }
        }
    }

    private mutating func discardZIndices(ofChildrenOf parent: Node) {
        let childCount = Int(lv_obj_get_child_count(parent))
        guard childCount > 0 else { return }
        var children: [Node] = []
        children.reserveCapacity(childCount)
        for index in 0..<childCount {
            if let child = lv_obj_get_child(parent, Int32(index)) {
                children.append(child)
            }
        }
        zIndexEntries.removeAll { entry in
            children.contains { $0 == entry.node }
        }
    }

    private func zIndex(of node: Node) -> Double {
        zIndexEntries.last { $0.node == node }?.value ?? 0
    }

    private mutating func registerIdentity(
        of node: Node,
        parent: Node,
        kind: LVGLNodeIdentity.Kind
    ) {
        nodeIdentities[node] = LVGLNodeIdentity(
            identity: .none,
            kind: kind
        )
    }

    private mutating func removeIdentities(in root: Node) {
        for node in nodes(in: root) {
            nodeIdentities.removeValue(forKey: node)
            nodeTransactions.removeValue(forKey: node)
        }
    }

    private func nodes(in root: Node) -> [Node] {
        var result: [Node] = []
        var pending = [root]
        while let node = pending.popLast() {
            result.append(node)
            for index in 0..<lv_obj_get_child_count(node) {
                if let child = lv_obj_get_child(node, Int32(index)) {
                    pending.append(child)
                }
            }
        }
        return result
    }

    private func identityKind(of layout: ContainerLayout) -> LVGLNodeIdentity.Kind {
        switch layout {
        case .stack: return .stack
        case .overlay: return .overlay
        case .scroll: return .scroll
        case .frame: return .frame
        case .padding, .defaultPadding: return .padding
        case .background, .secondaryBackground: return .background
        case .offset: return .offset
        case .opacity: return .opacity
        case .scale: return .scale
        case .rotation, .projection: return .rotation
        case .color: return .color
        case .clip: return .clip
        case .spacer: return .spacer
        case .layout: return .layout
        }
    }

    private func applyCircleClip(
        _ node: Node,
        style: FillStyle,
        size: RenderSize
    ) -> Bool {
        let diameter = min(size.width, size.height)
        guard diameter > 0 else { return false }
        if size.width == diameter, size.height == diameter,
           let image = singleFullSizeImageDescendant(of: node, diameter: diameter) {
            lv_obj_set_style_radius(image, LV_RADIUS_CIRCLE, 0)
            return true
        }
        return LVGLClipRenderer.applyCircle(style: style, size: size, to: node)
    }

    private func singleFullSizeImageDescendant(of node: Node, diameter: Int32) -> Node? {
        var descendant = node
        while lv_obj_get_child_count(descendant) == 1 {
            guard let child = lv_obj_get_child(descendant, 0),
                  lv_obj_get_x(child) == 0,
                  lv_obj_get_y(child) == 0,
                  lv_obj_get_width(child) == diameter,
                  lv_obj_get_height(child) == diameter else {
                return nil
            }
            if nodeIdentities[child]?.kind == .image {
                return child
            }
            descendant = child
        }
        return nil
    }

    private func clipRadius(for path: Path, size: RenderSize) -> Int32? {
        let rect = ShapeRect(width: Float(size.width), height: Float(size.height))
        if path == Rectangle().path(in: rect) {
            return 0
        }

        guard case let .move(first)? = path.elements.first else { return nil }
        let radius = max(0, first.x - rect.x)
        guard path == RoundedRectangle(cornerRadius: radius).path(in: rect) else { return nil }
        return Int32(radius.rounded())
    }

    private func horizontal(_ alignment: HorizontalAlignment) -> lv_flex_align_t {
        switch alignment {
        case .leading: return LV_FLEX_ALIGN_START
        case .center: return LV_FLEX_ALIGN_CENTER
        case .trailing: return LV_FLEX_ALIGN_END
        default: return LV_FLEX_ALIGN_START
        }
    }

    private func vertical(_ alignment: VerticalAlignment) -> lv_flex_align_t {
        switch alignment {
        case .top: return LV_FLEX_ALIGN_START
        case .center: return LV_FLEX_ALIGN_CENTER
        case .bottom: return LV_FLEX_ALIGN_END
        default: return LV_FLEX_ALIGN_START
        }
    }

    private func position(_ alignment: Alignment) -> lv_align_t {
        switch (alignment.horizontal, alignment.vertical) {
        case (.leading, .top): return LV_ALIGN_TOP_LEFT
        case (.center, .top): return LV_ALIGN_TOP_MID
        case (.trailing, .top): return LV_ALIGN_TOP_RIGHT
        case (.leading, .center): return LV_ALIGN_LEFT_MID
        case (.center, .center): return LV_ALIGN_CENTER
        case (.trailing, .center): return LV_ALIGN_RIGHT_MID
        case (.leading, .bottom): return LV_ALIGN_BOTTOM_LEFT
        case (.center, .bottom): return LV_ALIGN_BOTTOM_MID
        case (.trailing, .bottom): return LV_ALIGN_BOTTOM_RIGHT
        default: return LV_ALIGN_TOP_LEFT
        }
    }
}

private func lvglRotation(_ angle: Angle) -> Int32 {
    let value = angle.degrees * 10
    guard value.isFinite else { return 0 }
    return Int32(min(Double(Int32.max), max(Double(Int32.min), value)).rounded())
}
