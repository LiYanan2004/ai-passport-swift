import EmbeddedSwiftUI

public struct RenderSize: Equatable {
    public var width: Int32
    public var height: Int32
    public init(width: Int32, height: Int32) {
        self.width = max(0, width)
        self.height = max(0, height)
    }
}

public struct ScrollOffset: Equatable {
    public var x: Int32
    public var y: Int32
    public init(x: Int32 = 0, y: Int32 = 0) {
        self.x = x
        self.y = y
    }
}

package protocol _DisplayListRenderBackend: RendererProvider {
    associatedtype Node
    associatedtype LayoutProvider: RendererProvider
    var layoutProvider: LayoutProvider { get }
    mutating func beginRender()
    mutating func makeContainer(_ layout: ContainerLayout, proposedSize: RenderSize, parent: Node) -> Node?
    mutating func finishContainer(_ node: Node, layout: ContainerLayout) -> Bool
    mutating func makeText(_ content: String, environment: RenderEnvironment, parent: Node) -> Node?
    mutating func makeImage(_ name: String, size: RenderSize, parent: Node) -> Node?
    mutating func makeShape(
        _ path: Path, color: Color, style: ShapeRenderingStyle, size: RenderSize, parent: Node
    ) -> Node?
    mutating func configure(_ node: Node, item: DisplayList.Item)
    mutating func scrollOffset(of node: Node) -> ScrollOffset
    mutating func setScrollOffset(_ offset: ScrollOffset, of node: Node)
    mutating func remove(_ node: Node)
    mutating func removeAll(from root: Node)
    mutating func replace(_ previous: Node?, with next: Node, animation: Animation?)
}

private struct ScrollTarget<Node> {
    let identity: DisplayList.Identity
    let node: Node
    let axes: Axis.Set
    let focusable: Bool
}

private struct MountFrame<Node> {
    let item: DisplayList.Item
    let node: Node
    let container: ContainerLayout?
    var nextChildIndex = 0
}

/// Mounts resolved items and preserves platform state by the core's identities.
package struct _DisplayListRenderer<Backend: _DisplayListRenderBackend> {
    private var backend: Backend
    private var root: Backend.Node?
    private var scrollTargets: [ScrollTarget<Backend.Node>] = []
    private var focusIdentity: DisplayList.Identity?
    private var animationValues: [_ViewList_ID: ValueTransactionSeed] = [:]
    private var appearances: [_ViewList_ID: AppearanceEffect] = [:]
    private var appearanceOrder: [_ViewList_ID] = []
    private var physicalButtonActions: [_PhysicalButtonAction] = []
    private var version = DisplayList.Version()
    private var nextScrollTargets: [ScrollTarget<Backend.Node>] = []
    private let graph = ViewGraph()
    private let stableIDs = DisplayList.StableIdentityRoot()

    public init(backend: Backend) {
        self.backend = backend
    }

    package var configuration: RendererConfiguration { backend.configuration }

    @discardableResult
    public mutating func render<Content: View>(
        _ content: Content, in parent: Backend.Node, rootGeometry: RootGeometry,
        animation: Animation? = nil
    ) -> Bool {
        render(content, in: parent, rootGeometry: rootGeometry, transaction: Transaction(animation: animation))
    }

    @discardableResult
    public mutating func render<Content: View>(
        _ content: Content, in parent: Backend.Node, rootGeometry: RootGeometry,
        transaction: Transaction
    ) -> Bool {
        graph.beginUpdate()
        var inputs = _ViewInputs()
        inputs.graph = graph
        inputs.phase = graph.phase
        inputs.transaction = transaction
        inputs.configuration = backend.configuration
        inputs.environment.systemColorDefinition = backend.configuration.systemColor
        var outputs = Content.makeDebuggableView(view: content, inputs: inputs)
        graph.endUpdate()
        let success = render(
            &outputs,
            in: parent, rootGeometry: rootGeometry, transaction: transaction
        )
        if success { graph.commit() }
        return success
    }

    @discardableResult
    public mutating func render<Content: View>(
        _ content: Content, in parent: Backend.Node, size: RenderSize,
        animation: Animation? = nil
    ) -> Bool {
        render(content, in: parent, size: size, transaction: Transaction(animation: animation))
    }

    @discardableResult
    public mutating func render<Content: View>(
        _ content: Content, in parent: Backend.Node, size: RenderSize,
        transaction: Transaction
    ) -> Bool {
        render(
            content, in: parent,
            rootGeometry: RootGeometry(screenSize: EmbeddedSize(width: size.width, height: size.height)),
            transaction: transaction
        )
    }

    package mutating func render(
        _ outputs: inout _ViewOutputs, in parent: Backend.Node, rootGeometry: RootGeometry,
        transaction: Transaction
    ) -> Bool {
        version.value &+= 1
        guard let update = resolveLayout(
            &outputs.displayList, rootGeometry: rootGeometry, transaction: transaction
        ), let rootItem = update.displayList.items.first else { return false }
        let nextPhysicalButtonActions = outputs.viewResponders.compactMap {
            $0.value as? _PhysicalButtonAction
        }
        // Embedded adaptation: release the consumed construction outputs
        // before mounting a replacement LVGL tree. The ESP32-C3 has no PSRAM,
        // and an eager List beside an animated view otherwise raises the
        // transient internal-RAM peak beyond the available heap.
        outputs = _ViewOutputs()

        backend.beginRender()
        nextScrollTargets = []
        guard let nextRoot = mount(rootItem, parent: parent) else { return false }
        for next in nextScrollTargets {
            if let previous = scrollTargets.first(where: { $0.identity == next.identity && $0.axes == next.axes }) {
                let offset = backend.scrollOffset(of: previous.node)
                backend.setScrollOffset(offset, of: next.node)
            }
        }
        backend.replace(root, with: nextRoot, animation: transaction.animation)
        stableIDs.commit()
        root = nextRoot
        scrollTargets = nextScrollTargets
        nextScrollTargets = []
        if !scrollTargets.contains(where: { $0.identity == focusIdentity && $0.focusable }) {
            focusIdentity = scrollTargets.first(where: { $0.focusable })?.identity
        }
        animationValues = update.animationValues
        physicalButtonActions = nextPhysicalButtonActions

        for identity in appearanceOrder.reversed() where update.appearances[identity] == nil {
            var effect = appearances.removeValue(forKey: identity)
            effect?.disappeared()
        }
        for identity in update.appearanceOrder {
            guard let modifier = update.appearances[identity] else { continue }
            var effect = appearances[identity] ?? AppearanceEffect(modifier: modifier)
            effect.updateValue(modifier: modifier)
            appearances[identity] = effect
        }
        appearanceOrder = update.appearanceOrder
        return true
    }

    // Embedded adaptation: release LayoutNodes and measurement caches before
    // mounting adds the next LVGL tree alongside the currently visible tree.
    @inline(never)
    private func resolveLayout(
        _ displayList: inout DisplayList,
        rootGeometry: RootGeometry,
        transaction: Transaction
    ) -> DisplayListUpdate? {
        var layout = DisplayListLayout(
            provider: backend.layoutProvider,
            transaction: transaction,
            previousAnimations: animationValues,
            stableIDs: stableIDs
        )
        return layout.updateConsuming(
            &displayList, size: rootGeometry.contentBounds.size,
            alignment: rootGeometry.centersRootView ? .center : .topLeading,
            version: version
        )
    }

    private mutating func mount(_ item: DisplayList.Item, parent: Backend.Node) -> Backend.Node? {
        // Embedded adaptation: upstream render traversal can rely on graph
        // indirection. Use an explicit post-order frame stack so a deep resolved
        // item tree does not consume one 1.7 KiB RISC-V call frame per level.
        guard let rootFrame = makeMountFrame(item, parent: parent) else { return nil }
        let rootNode = rootFrame.node
        var frames = [rootFrame]
        while !frames.isEmpty {
            let frameIndex = frames.count - 1
            if frames[frameIndex].nextChildIndex < frames[frameIndex].item.children.count {
                let childIndex = frames[frameIndex].nextChildIndex
                let child = frames[frameIndex].item.children[childIndex]
                frames[frameIndex].nextChildIndex += 1
                guard let childFrame = makeMountFrame(
                    child,
                    parent: frames[frameIndex].node
                ) else {
                    backend.remove(rootNode)
                    return nil
                }
                frames.append(childFrame)
                continue
            }
            let completed = frames.removeLast()
            guard finishMountFrame(completed) else {
                backend.remove(rootNode)
                return nil
            }
        }
        return rootNode
    }

    private mutating func makeMountFrame(
        _ item: DisplayList.Item,
        parent: Backend.Node
    ) -> MountFrame<Backend.Node>? {
        let size = RenderSize(width: item.frame.width, height: item.frame.height)
        let node: Backend.Node?
        var container: ContainerLayout?
        switch item.value {
        case let .container(layout):
            container = layout
            node = backend.makeContainer(layout, proposedSize: size, parent: parent)
        case let .text(text, environment):
            node = backend.makeText(text, environment: environment, parent: parent)
        case let .image(name, _):
            node = backend.makeImage(name, size: size, parent: parent)
        case let .shape(shape):
            let path = shape.path(ShapeRect(width: Float(size.width), height: Float(size.height)))
            node = backend.makeShape(
                path, color: shape.resolvedColor(backend.configuration.defaultForegroundColor),
                style: shape.renderingStyle, size: size, parent: parent
            )
        case let .effect(effect):
            container = effectLayout(effect.resolve(item.frame.size))
            guard let container else { return nil }
            node = backend.makeContainer(container, proposedSize: size, parent: parent)
        }
        guard let node else { return nil }
        backend.configure(node, item: item)
        return MountFrame(item: item, node: node, container: container)
    }

    private mutating func finishMountFrame(
        _ frame: MountFrame<Backend.Node>
    ) -> Bool {
        if let container = frame.container {
            guard backend.finishContainer(frame.node, layout: container) else {
                return false
            }
            if case let .scroll(axes, _, _) = container {
                nextScrollTargets.append(ScrollTarget(
                    identity: frame.item.identity,
                    node: frame.node,
                    axes: axes,
                    focusable: frame.item.focusable != false
                ))
            }
        }
        return true
    }

    private func effectLayout(_ effect: DisplayList.Effect) -> ContainerLayout? {
        switch effect {
        case let .opacity(opacity): return .opacity(opacity)
        case let .clip(shape, style): return .clip(shape: shape, style: style)
        case let .geometry(transform):
            switch transform.storage {
            case .identity: return .overlay(alignment: .topLeading)
            case let .translation(x, y): return .offset(x: Int32(x.rounded()), y: Int32(y.rounded()))
            case let .scale(x, y, anchor): return .scale(x: x, y: y, anchor: anchor)
            case let .rotation(angle, anchor): return .rotation(angle: angle, anchor: anchor)
            case .projection: return .projection(transform)
            }
        }
    }

    @discardableResult
    public mutating func handlePhysicalButton(_ button: PhysicalButton) -> Bool {
        for action in physicalButtonActions where action.button == button {
            action.action()
            return true
        }
        guard let scroll = scrollTargets.first(where: { $0.identity == focusIdentity }) else { return false }
        var offset = backend.scrollOffset(of: scroll.node)
        guard button != .ok else { return false }
        let delta: Int32 = button == .up ? -32 : 32
        if scroll.axes.contains(.vertical) { offset.y += delta }
        else if scroll.axes.contains(.horizontal) { offset.x += delta }
        else { return false }
        backend.setScrollOffset(offset, of: scroll.node)
        return true
    }

    public mutating func focusNext() {
        let targets = scrollTargets.filter { $0.focusable }
        guard !targets.isEmpty else { return }
        let index = targets.firstIndex { $0.identity == focusIdentity } ?? -1
        focusIdentity = targets[(index + 1) % targets.count].identity
    }

    public mutating func unmount() {
        if let root { backend.removeAll(from: root) }
        root = nil
        scrollTargets = []
        nextScrollTargets = []
        focusIdentity = nil
        animationValues = [:]
        physicalButtonActions = []
        for identity in appearanceOrder.reversed() {
            var effect = appearances.removeValue(forKey: identity)
            effect?.disappeared()
        }
        appearanceOrder = []
        graph.unmount()
        stableIDs.reset()
    }
}
