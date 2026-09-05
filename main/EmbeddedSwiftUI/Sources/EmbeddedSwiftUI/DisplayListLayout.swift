// Embedded adaptation: OpenSwiftUI can defer this work to its graph and render
// pipeline. The embedded profile resolves the transient command stream in one
// bounded pass using adaptor-supplied limits, while retaining proposal-aware
// layout, stable identity, lifecycle, traits, and local transactions.

package struct AppearanceEffect {
    package var modifier: _AppearanceActionModifier
    package var isVisible = false
    package var resetSeed: UInt32 = 0

    package init(modifier: _AppearanceActionModifier) {
        self.modifier = modifier
    }

    package mutating func appeared() {
        guard !isVisible else { return }
        isVisible = true
        modifier.appear?()
    }

    package mutating func disappeared() {
        guard isVisible else { return }
        isVisible = false
        modifier.disappear?()
    }

    package mutating func updateValue(modifier: _AppearanceActionModifier) {
        if resetSeed != modifier.phase.resetSeed {
            disappeared()
            resetSeed = modifier.phase.resetSeed
        }
        self.modifier = modifier
        if modifier.phase.isBeingRemoved { disappeared() } else { appeared() }
    }
}

package struct ValueTransactionSeed {
    package var value: DisplayList.AnimationValue
    package var transactionSeed: UInt64
    package var changedSeed: UInt64

    package init(value: DisplayList.AnimationValue, transactionSeed: UInt64, previous: Self?) {
        self.value = value
        self.transactionSeed = transactionSeed
        if let previous {
            changedSeed = value.matches(previous.value) ? previous.changedSeed : transactionSeed
        } else {
            changedSeed = .max
        }
    }
}

package struct ChildTransaction {
    package var transaction: Transaction

    package init(
        transaction: Transaction,
        animation: Animation?,
        valueTransactionSeed: ValueTransactionSeed,
        transactionSeed: UInt64
    ) {
        self.transaction = transaction
        if !transaction.disablesAnimations, valueTransactionSeed.changedSeed == transactionSeed {
            self.transaction.animation = animation
        }
    }
}

package struct DisplayListUpdate {
    package let displayList: DisplayList
    package let appearances: [_ViewList_ID: _AppearanceActionModifier]
    package let appearanceOrder: [_ViewList_ID]
    package let animationValues: [_ViewList_ID: ValueTransactionSeed]
}

private final class LayoutNode {
    var value: DisplayList.Item.Value
    let identity: _ViewList_ID
    var children: [LayoutNode] = []
    var traits: ViewTraitCollection
    var transaction: Transaction
    var focusable: Bool?
    var frame = EmbeddedRect(width: 0, height: 0)
    var proposal = ProposedViewSize.unspecified
    var placementProposal = ProposedViewSize.unspecified
    var measuredProposal: ProposedViewSize?
    var measuredSize = EmbeddedSize.zero
    var layout: _AnyLayout?
    var stackOrientation: Axis?
    var alignmentProposal: ProposedViewSize?
    var explicitAlignments: [AlignmentKey: Int32?] = [:]
    var hasExplicitAlignments: Bool?

    init(
        value: DisplayList.Item.Value,
        identity: _ViewList_ID,
        traits: ViewTraitCollection,
        transaction: Transaction,
        focusable: Bool?
    ) {
        self.value = value
        self.identity = identity
        self.traits = traits
        self.transaction = transaction
        self.focusable = focusable
    }
}

private enum ParseScopeEnd {
    case root
    case identity
    case container
}

private struct ParseFrame {
    var commands: [DisplayList.Command]
    var index = 0
    let scopeEnd: ParseScopeEnd
}

package struct DisplayListLayout<Provider: RendererProvider> {
    private let provider: Provider
    private let stableIDs: DisplayList.StableIdentityRoot
    private let transactionSeed: UInt64
    private var identities: [(_ViewList_ID, Int)] = [(_ViewList_ID(), 0)]
    private var traits = ViewTraitCollection()
    private var traitStack: [ViewTraitCollection] = []
    private var transactions: [Transaction]
    private var focusScopes: [Bool?] = [nil]
    private var parents: [LayoutNode] = []
    private var roots: [LayoutNode] = []
    private var count = 1
    private var failed = false
    private let previousAnimations: [_ViewList_ID: ValueTransactionSeed]
    private var animations: [_ViewList_ID: ValueTransactionSeed] = [:]
    private var appearances: [_ViewList_ID: _AppearanceActionModifier] = [:]
    private var appearanceOrder: [_ViewList_ID] = []

    package init(
        provider: Provider,
        transaction: Transaction,
        previousAnimations: [_ViewList_ID: ValueTransactionSeed],
        stableIDs: DisplayList.StableIdentityRoot = DisplayList.StableIdentityRoot()
    ) {
        self.provider = provider
        self.stableIDs = stableIDs
        transactionSeed = (previousAnimations.values.map(\.transactionSeed).max() ?? 0) &+ 1
        transactions = [transaction]
        self.previousAnimations = previousAnimations
    }

    package mutating func update(
        _ displayList: DisplayList,
        size: EmbeddedSize,
        alignment: Alignment,
        version: DisplayList.Version
    ) -> DisplayListUpdate? {
        var displayList = displayList
        return updateConsuming(
            &displayList, size: size, alignment: alignment, version: version
        )
    }

    package mutating func updateConsuming(
        _ displayList: inout DisplayList,
        size: EmbeddedSize,
        alignment: Alignment,
        version: DisplayList.Version
    ) -> DisplayListUpdate? {
        stableIDs.beginUpdate()
        parseConsuming(&displayList)
        guard !failed, parents.isEmpty else { return nil }
        let root = LayoutNode(
            value: .container(.frame(width: size.width, height: size.height, alignment: alignment)),
            identity: _ViewList_ID(), traits: ViewTraitCollection(),
            transaction: transactions[0], focusable: nil
        )
        root.children = roots
        place(root, in: EmbeddedRect(width: size.width, height: size.height), proposal: ProposedViewSize(size))
        guard !failed else { return nil }
        var result = DisplayList()
        result.items = [item(root, version: version)]
        return DisplayListUpdate(
            displayList: result, appearances: appearances,
            appearanceOrder: appearanceOrder, animationValues: animations
        )
    }

    private mutating func nextIdentity() -> _ViewList_ID {
        let index = identities.count - 1
        let identity = identities[index].0.appending(.index(identities[index].1))
        identities[index].1 += 1
        return identity
    }

    private mutating func append(_ value: DisplayList.Item.Value, isContainer: Bool = false) {
        guard count < provider.configuration.maximumNodes,
              parents.count < provider.configuration.maximumDepth else {
            failed = true
            return
        }
        count += 1
        let node = LayoutNode(
            value: value, identity: nextIdentity(), traits: traits,
            transaction: transactions.last!, focusable: focusScopes.last!
        )
        traits = ViewTraitCollection()
        if let parent = parents.last { parent.children.append(node) } else { roots.append(node) }
        if isContainer { parents.append(node) }
    }

    private mutating func parseConsuming(_ list: inout DisplayList) {
        // Embedded adaptation: nested identity/effect commands avoid copying
        // command arrays during construction. Walk those scopes with an
        // explicit heap-backed frame stack so parsing does not consume one
        // native call frame per View on the ESP32-C3's 16 KiB task stack.
        // Consume each command payload after creating its LayoutNode. The
        // ESP32-C3 has no PSRAM, so retaining a large eager List's construction
        // graph while allocating its layout graph can exhaust internal RAM
        // whenever an animated sibling rebuilds the shared root view.
        let rootCommands = list.commands
        list.commands = []
        var frames = [ParseFrame(commands: rootCommands, scopeEnd: .root)]
        while !frames.isEmpty {
            guard !failed else { return }
            let frameIndex = frames.count - 1
            if frames[frameIndex].index == frames[frameIndex].commands.count {
                switch frames.removeLast().scopeEnd {
                case .root:
                    break
                case .identity:
                    identities.removeLast()
                case .container:
                    parents.removeLast()
                }
                continue
            }
            let commandIndex = frames[frameIndex].index
            let command = frames[frameIndex].commands[commandIndex]
            frames[frameIndex].commands[commandIndex] = .invalid
            frames[frameIndex].index += 1
            switch command {
            case .invalid:
                failed = true
            case let .identity(identity, content):
                identities.append((identity, 0))
                frames.append(ParseFrame(
                    commands: content.commands,
                    scopeEnd: .identity
                ))
            case let .beginIdentity(identity):
                identities.append((identity, 0))
            case .endIdentity:
                guard identities.count > 1 else { failed = true; return }
                identities.removeLast()
            case let .beginContainer(layout):
                append(.container(layout), isContainer: true)
            case .beginImplicitRoot:
                append(.container(.layout(provider.configuration.implicitRootLayout)), isContainer: true)
            case .endContainer:
                guard !parents.isEmpty else { failed = true; return }
                parents.removeLast()
            case let .text(text, environment):
                append(.text(text, environment.resolved(in: provider.configuration)))
            case let .shape(shape):
                append(.shape(shape))
            case let .image(name, resizable):
                append(.image(name, resizable))
            case let .effect(effect, content):
                append(.effect(effect), isContainer: true)
                guard !failed else { return }
                frames.append(ParseFrame(
                    commands: content.commands,
                    scopeEnd: .container
                ))
            case let .beginTraits(value):
                traitStack.append(traits)
                traits.mergeValues(value)
            case .endTraits:
                guard let previous = traitStack.popLast() else { failed = true; return }
                traits = previous
            case let .beginFocusable(enabled):
                focusScopes.append(enabled)
            case .endFocusable:
                guard focusScopes.count > 1 else { failed = true; return }
                focusScopes.removeLast()
            case let .appearance(modifier):
                let identity = nextIdentity()
                appearances[identity] = modifier
                appearanceOrder.append(identity)
            case let .beginAnimation(animation, value):
                let identity = nextIdentity()
                // Preserve upstream's changed-value/current-transaction seed
                // gate, using a committed synchronous snapshot instead of
                // transactional AttributeGraph evaluation.
                let seed = ValueTransactionSeed(
                    value: value, transactionSeed: transactionSeed, previous: previousAnimations[identity]
                )
                let child = ChildTransaction(
                    transaction: transactions.last!, animation: animation,
                    valueTransactionSeed: seed, transactionSeed: transactionSeed
                )
                transactions.append(child.transaction)
                animations[identity] = seed
            case .endAnimation:
                guard transactions.count > 1 else { failed = true; return }
                transactions.removeLast()
            }
        }
    }

    private func insets(_ edges: Edge.Set) -> EdgeInsets {
        let value = provider.configuration.defaultPadding
        return EdgeInsets(
            top: edges.contains(.top) ? value.top : 0,
            leading: edges.contains(.leading) ? value.leading : 0,
            bottom: edges.contains(.bottom) ? value.bottom : 0,
            trailing: edges.contains(.trailing) ? value.trailing : 0
        )
    }

    private func layout(for node: LayoutNode) -> _AnyLayout? {
        if let layout = node.layout { return layout }
        let layout = makeLayout(for: node)
        node.layout = layout
        return layout
    }

    private func makeLayout(for node: LayoutNode) -> _AnyLayout? {
        guard case let .container(container) = node.value else { return nil }
        switch container {
        case let .layout(layout):
            return layout
        case let .stack(axis, spacing, alignment):
            if axis == .vertical {
                return _AnyLayout(VStackLayout(alignment: alignment.horizontal, spacing: spacing))
            }
            return _AnyLayout(HStackLayout(alignment: alignment.vertical, spacing: spacing))
        case let .scroll(axes, _, isList):
            if axes == .horizontal {
                return _AnyLayout(HStackLayout(alignment: .top, spacing: 0))
            }
            return _AnyLayout(VStackLayout(
                alignment: .leading, spacing: isList ? provider.configuration.listSpacing : 0
            ))
        default:
            return nil
        }
    }

    private func proxies(_ node: LayoutNode) -> LayoutSubviews {
        LayoutSubviews(node.children.map { child in
            child.stackOrientation = layout(for: node)?.properties.stackOrientation ?? node.stackOrientation
            return LayoutSubview(
                storage: _LayoutSubviewStorage(
                    sizeThatFits: { proposal in measure(child, proposal: proposal) },
                    place: { rect in child.frame = rect },
                    dimensions: { proposal in dimensions(child, proposal: proposal) },
                    spacing: { spacing(child) },
                    didPlace: { child.placementProposal = $0 }
                ),
                traits: child.traits
            )
        }, defaultSpacing: provider.configuration.defaultSpacing,
           maximumDimension: provider.configuration.maximumDimension)
    }

    private func contentProposal(_ node: LayoutNode, proposal: ProposedViewSize) -> ProposedViewSize {
        guard case let .container(layout) = node.value else { return proposal }
        switch layout {
        case let .frame(width, height, _):
            return ProposedViewSize(width: width ?? proposal.width, height: height ?? proposal.height)
        case let .padding(insets):
            return ProposedViewSize(
                width: proposal.width.map { max(0, $0 - insets.leading - insets.trailing) },
                height: proposal.height.map { max(0, $0 - insets.top - insets.bottom) }
            )
        case let .defaultPadding(edges):
            let insets = insets(edges)
            return ProposedViewSize(
                width: proposal.width.map { max(0, $0 - insets.leading - insets.trailing) },
                height: proposal.height.map { max(0, $0 - insets.top - insets.bottom) }
            )
        case let .scroll(axes, _, _):
            return ProposedViewSize(
                width: axes.contains(.horizontal) ? nil : proposal.width,
                height: axes.contains(.vertical) ? nil : proposal.height
            )
        default:
            return proposal
        }
    }

    private func measure(_ node: LayoutNode, proposal: ProposedViewSize) -> EmbeddedSize {
        node.proposal = proposal
        if node.measuredProposal == proposal { return node.measuredSize }
        let size = measureUncached(node, proposal: proposal)
        node.measuredProposal = proposal
        node.measuredSize = size
        return size
    }

    private func measureUncached(_ node: LayoutNode, proposal: ProposedViewSize) -> EmbeddedSize {
        switch node.value {
        case let .text(text, environment):
            return provider.measureText(text, environment: environment, proposal: proposal)
        case let .image(name, resizable):
            let size = provider.imageSize(named: name) ?? .zero
            return resizable ? proposal.replacingUnspecifiedDimensions(by: size) : size
        case let .shape(shape):
            return shape.sizeThatFits(proposal)
        case .effect:
            return overlaySize(node.children, proposal: proposal)
        case let .container(container):
            let childProposal = contentProposal(node, proposal: proposal)
            switch container {
            case .color:
                return proposal.replacingUnspecifiedDimensions()
            case let .spacer(minimum):
                let minimum = minimum ?? provider.configuration.defaultSpacing
                if node.stackOrientation == .horizontal {
                    return EmbeddedSize(width: max(minimum, proposal.width ?? minimum), height: 0)
                }
                if node.stackOrientation == .vertical {
                    return EmbeddedSize(width: 0, height: max(minimum, proposal.height ?? minimum))
                }
                return EmbeddedSize(width: max(minimum, proposal.width ?? minimum),
                                    height: max(minimum, proposal.height ?? minimum))
            case .secondaryBackground:
                return node.children.last.map { measure($0, proposal: proposal) } ?? .zero
            default:
                break
            }
            let contentSize: EmbeddedSize
            if let layout = layout(for: node) {
                contentSize = layout.sizeThatFits(childProposal, subviews: proxies(node))
            } else {
                contentSize = overlaySize(node.children, proposal: childProposal)
            }
            switch container {
            case let .frame(width, height, _):
                return EmbeddedSize(width: width ?? contentSize.width, height: height ?? contentSize.height)
            case let .padding(insets):
                return EmbeddedSize(width: contentSize.width + insets.leading + insets.trailing,
                                    height: contentSize.height + insets.top + insets.bottom)
            case let .defaultPadding(edges):
                let insets = insets(edges)
                return EmbeddedSize(width: contentSize.width + insets.leading + insets.trailing,
                                    height: contentSize.height + insets.top + insets.bottom)
            case .scroll:
                return proposal.replacingUnspecifiedDimensions(by: contentSize)
            default:
                return contentSize
            }
        }
    }

    private func overlaySize(_ children: [LayoutNode], proposal: ProposedViewSize) -> EmbeddedSize {
        var size = EmbeddedSize.zero
        for child in children {
            let childSize = measure(child, proposal: proposal)
            size.width = max(size.width, childSize.width)
            size.height = max(size.height, childSize.height)
        }
        return size
    }

    private func spacing(_ node: LayoutNode) -> ViewSpacing {
        if let layout = layout(for: node) { return layout.spacing(subviews: proxies(node)) }
        if !node.children.isEmpty {
            return node.children.reduce(into: ViewSpacing()) { $0.formUnion(spacing($1)) }
        }
        let value = provider.configuration.defaultSpacing
        return ViewSpacing(insets: EdgeInsets(top: value, leading: value, bottom: value, trailing: value))
    }

    private func dimensions(_ node: LayoutNode, proposal: ProposedViewSize) -> ViewDimensions {
        let size = measure(node, proposal: proposal)
        guard hasExplicitAlignments(node) else {
            return ViewDimensions(width: size.width, height: size.height)
        }
        return ViewDimensions(
            size: size,
            horizontal: { explicitAlignment(.horizontal($0), node: node, size: size, proposal: proposal) },
            vertical: { explicitAlignment(.vertical($0), node: node, size: size, proposal: proposal) }
        )
    }

    private func explicitAlignment(
        _ guide: AlignmentKey, node: LayoutNode, size: EmbeddedSize, proposal: ProposedViewSize
    ) -> Int32? {
        guard hasExplicitAlignments(node) else { return nil }
        if node.alignmentProposal != proposal {
            node.explicitAlignments.removeAll(keepingCapacity: true)
            node.alignmentProposal = proposal
        }
        if let cached = node.explicitAlignments[guide] { return cached }
        let value = computeExplicitAlignment(guide, node: node, size: size, proposal: proposal)
        node.explicitAlignments[guide] = .some(value)
        return value
    }

    private func hasExplicitAlignments(_ node: LayoutNode) -> Bool {
        if let cached = node.hasExplicitAlignments { return cached }
        let result: Bool
        if case .container(.layout) = node.value {
            result = true
        } else {
            result = node.children.contains { hasExplicitAlignments($0) }
        }
        node.hasExplicitAlignments = result
        return result
    }

    private func computeExplicitAlignment(
        _ guide: AlignmentKey, node: LayoutNode, size: EmbeddedSize, proposal: ProposedViewSize
    ) -> Int32? {
        guard !node.children.isEmpty else { return nil }
        let bounds = EmbeddedRect(width: size.width, height: size.height)
        let childProposal = contentProposal(node, proposal: proposal)
        if let layout = layout(for: node) {
            let subviews = proxies(node)
            _ = layout.sizeThatFits(childProposal, subviews: subviews)
            _ = layout.placeSubviews(in: bounds, proposal: childProposal, subviews: subviews)
            let value: Int32?
            switch guide {
            case let .horizontal(guide):
                value = layout.explicitAlignment(of: guide, in: bounds, proposal: childProposal, subviews: subviews)
            case let .vertical(guide):
                value = layout.explicitAlignment(of: guide, in: bounds, proposal: childProposal, subviews: subviews)
            }
            if let value { return value }
        } else {
            let (childBounds, alignment) = placementBounds(node, size: size)
            for child in node.children {
                let proposed = placementProposal(node, child: child, bounds: childBounds, proposal: childProposal)
                child.frame = alignment.rect(dimensions: dimensions(child, proposal: proposed), in: childBounds)
                child.placementProposal = proposed
            }
        }
        var total: Int64 = 0
        var count: Int64 = 0
        for child in node.children {
            guard let value = guide.explicit(in: dimensions(child, proposal: child.placementProposal)) else { continue }
            switch guide {
            case .horizontal: total += Int64(value) + Int64(child.frame.x)
            case .vertical: total += Int64(value) + Int64(child.frame.y)
            }
            count += 1
        }
        return count == 0 ? nil : Int32(total / count)
    }

    private mutating func place(_ node: LayoutNode, in frame: EmbeddedRect, proposal: ProposedViewSize) {
        // Embedded adaptation: layout placement needs sizeable callback
        // frames. An explicit work stack keeps those frames from accumulating
        // before native font measurement on the fixed 16 KiB renderer task.
        node.frame = frame
        node.placementProposal = proposal
        var pending = [node]
        while let current = pending.popLast(), !failed {
            placeChildren(current, in: current.frame, proposal: current.placementProposal)
            pending.append(contentsOf: current.children.reversed())
        }
    }

    private mutating func placeChildren(_ node: LayoutNode, in frame: EmbeddedRect, proposal: ProposedViewSize) {
        node.frame = frame
        guard frame.width <= provider.configuration.maximumDimension,
              frame.height <= provider.configuration.maximumDimension else {
            failed = true
            return
        }
        let childProposal = contentProposal(node, proposal: proposal)
        if let layout = layout(for: node) {
            let subviews = proxies(node)
            let contentSize = layout.sizeThatFits(childProposal, subviews: subviews)
            let bounds: EmbeddedRect
            if case .container(.scroll) = node.value {
                bounds = EmbeddedRect(width: contentSize.width, height: contentSize.height)
            } else {
                bounds = EmbeddedRect(width: frame.width, height: frame.height)
            }
            _ = layout.placeSubviews(in: bounds, proposal: childProposal, subviews: subviews)
            return
        }
        let (bounds, alignment) = placementBounds(node, size: frame.size)
        for child in node.children {
            child.stackOrientation = node.stackOrientation
            let proposed = placementProposal(node, child: child, bounds: bounds, proposal: childProposal)
            let dimensions = dimensions(child, proposal: proposed)
            child.frame = alignment.rect(dimensions: dimensions, in: bounds)
            child.placementProposal = proposed
        }
    }

    private func placementProposal(
        _ node: LayoutNode, child: LayoutNode, bounds: EmbeddedRect, proposal: ProposedViewSize
    ) -> ProposedViewSize {
        // Backgrounds use the primary view's chosen size. Transparent layout
        // wrappers retain the parent's proposal even when the child declines it.
        if case .container(.secondaryBackground) = node.value, child !== node.children.last {
            return ProposedViewSize(bounds.size)
        }
        return proposal
    }

    private func placementBounds(_ node: LayoutNode, size: EmbeddedSize) -> (EmbeddedRect, Alignment) {
        var bounds = EmbeddedRect(width: size.width, height: size.height)
        var alignment = Alignment.topLeading
        if case let .container(container) = node.value {
            switch container {
            case let .frame(_, _, value), let .overlay(value), let .secondaryBackground(value):
                alignment = value
            case let .padding(insets):
                bounds = EmbeddedRect(
                    x: insets.leading, y: insets.top,
                    width: max(0, size.width - insets.leading - insets.trailing),
                    height: max(0, size.height - insets.top - insets.bottom)
                )
            case let .defaultPadding(edges):
                let insets = insets(edges)
                bounds = EmbeddedRect(
                    x: insets.leading, y: insets.top,
                    width: max(0, size.width - insets.leading - insets.trailing),
                    height: max(0, size.height - insets.top - insets.bottom)
                )
            default:
                break
            }
        }
        return (bounds, alignment)
    }

    private func item(_ node: LayoutNode, version: DisplayList.Version) -> DisplayList.Item {
        let stableIdentity = DisplayList.StableIdentity(scope: node.identity)
        return DisplayList.Item(
            frame: node.frame, identity: stableIDs.identity(for: stableIdentity),
            stableIdentity: stableIdentity, version: version,
            value: node.value, children: node.children.map { item($0, version: version) },
            traits: node.traits, transaction: node.transaction, focusable: node.focusable
        )
    }
}
